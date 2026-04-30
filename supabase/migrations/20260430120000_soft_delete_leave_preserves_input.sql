-- =============================================================================
-- MIGRATION: Soft-delete leave + active-status skip-count filter
-- =============================================================================
-- Background: leaveChat() in the Flutter client now sets status='left' on
-- the participant row instead of DELETE-ing it. This preserves all of the
-- user's input (propositions, ratings, skips, leaderboard rankings, billing
-- rows) so a rejoin can pick up exactly where they left off.
--
-- Two server-side adjustments are needed for that contract to hold:
--
--   1) join_chat_returning_participant must flip a previously-left row
--      back to status='active' (current behaviour is ON CONFLICT DO NOTHING,
--      which leaves the user stranded as 'left').
--
--   2) Auto-advance and skip-quota functions count rows from rating_skips
--      with no participant-status filter. Once skip rows survive a leave,
--      a left skipper's preserved skip would inflate the skip count and
--      drop active_raters below the actual number of expected raters,
--      triggering premature "everyone skipped" advances. JOIN participants
--      and require status='active' so only currently-active skippers count.
--
-- All updated functions retain their existing signatures and security
-- attributes; only their bodies change.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) join_chat_returning_participant — upsert on leave/rejoin
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_chat_returning_participant(
  p_chat_id bigint,
  p_display_name text
)
RETURNS TABLE (
  id bigint,
  display_name text,
  status text,
  is_host boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM chats c
    WHERE c.id = p_chat_id
      AND c.is_active = true
      AND c.access_method IN ('public', 'code')
  ) THEN
    RAISE EXCEPTION 'Chat does not allow direct joining';
  END IF;

  -- Upsert: insert if first join, otherwise flip an existing row's status
  -- back to 'active'. NEVER reactivate a kicked user — that path requires
  -- host approval (or auto-approval based on require_approval). We only
  -- transition 'left' → 'active' here.
  INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
  VALUES (p_chat_id, v_user_id, p_display_name, false, 'active')
  ON CONFLICT (chat_id, user_id) WHERE user_id IS NOT NULL
  DO UPDATE SET
    -- Reactivate left participants. Active and kicked rows are unaffected.
    status = CASE WHEN participants.status = 'left' THEN 'active' ELSE participants.status END,
    -- Refresh display_name only on a real rejoin (left → active). Otherwise
    -- a duplicate join call from an already-active user would overwrite
    -- their established name (test 76:6 contract).
    display_name = CASE WHEN participants.status = 'left' THEN EXCLUDED.display_name ELSE participants.display_name END;

  RETURN QUERY
  SELECT p.id, p.display_name, p.status, p.is_host
  FROM participants p
  WHERE p.chat_id = p_chat_id
    AND p.user_id = v_user_id;
END;
$$;

COMMENT ON FUNCTION public.join_chat_returning_participant(bigint, text) IS
  'Joins a chat (idempotent). If the user previously left (status=left), flips back to active. Kicked users are not auto-reactivated.';

-- -----------------------------------------------------------------------------
-- 2) check_early_advance_on_rating — skip-count filtered by active status
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_early_advance_on_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round_id INTEGER;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 10;
    v_phase TEXT;
    v_chat_id INTEGER;
BEGIN
    SELECT round_id INTO v_round_id FROM new_ratings LIMIT 1;
    IF v_round_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT r.phase, c.chat_id
      INTO v_phase, v_chat_id
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = v_round_id;

    IF v_phase IS DISTINCT FROM 'rating' THEN
        RETURN NULL;
    END IF;

    SELECT * INTO v_chat FROM chats WHERE id = v_chat_id;

    IF v_chat.rating_threshold_percent IS NULL
       AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NULL;
    END IF;

    IF v_chat.start_mode = 'manual' THEN
        RETURN NULL;
    END IF;

    PERFORM pg_advisory_xact_lock(v_round_id);

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase IS DISTINCT FROM 'rating' THEN
        RETURN NULL;
    END IF;

    v_total_participants := public.get_funded_participant_count(v_round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NULL;
    END IF;

    -- Skipper count, restricted to currently-active participants. With
    -- soft-delete leaves preserving rating_skips rows, a left skipper's
    -- preserved skip must NOT count or active_raters drops below the
    -- actual number of expected raters and the round advances early.
    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips rs
    JOIN participants p ON p.id = rs.participant_id
    WHERE rs.round_id = v_round_id
      AND p.status = 'active';

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
        RETURN NULL;
    END IF;

    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

    SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
    FROM (
        SELECT
            p.id,
            (SELECT COUNT(*)
               FROM grid_rankings gr
              WHERE gr.proposition_id = p.id
                AND gr.round_id = v_round_id) AS cnt
        FROM propositions p
        WHERE p.round_id = v_round_id
    ) prop_ratings;

    IF v_min_ratings >= v_threshold THEN
        RAISE NOTICE '[EARLY ADVANCE] Per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
            v_min_ratings, v_threshold, v_active_raters, v_skip_count, v_round_id;
        PERFORM complete_round_with_winner(v_round_id);
        PERFORM apply_adaptive_duration(v_round_id);
    END IF;

    RETURN NULL;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3) check_early_advance_on_rating_skip — same skip-count filter fix
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_early_advance_on_rating_skip()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_skip_count INTEGER;
    v_active_raters INTEGER;
    v_min_ratings INTEGER;
    v_threshold INTEGER;
    v_has_funding BOOLEAN;
    v_cap CONSTANT INTEGER := 10;
BEGIN
    SELECT r.*, c.chat_id
    INTO v_round
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = NEW.round_id;

    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    SELECT * INTO v_chat FROM chats WHERE id = v_round.chat_id;

    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(NEW.round_id);

    SELECT phase INTO v_round.phase
    FROM rounds WHERE id = NEW.round_id;

    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    v_total_participants := public.get_funded_participant_count(NEW.round_id);
    v_has_funding := v_total_participants > 0;

    IF NOT v_has_funding THEN
        SELECT COUNT(*) INTO v_total_participants
        FROM participants
        WHERE chat_id = v_round.chat_id AND status = 'active';
    END IF;

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Active-only skip count (see check_early_advance_on_rating for rationale)
    SELECT COUNT(*) INTO v_skip_count
    FROM rating_skips rs
    JOIN participants p ON p.id = rs.participant_id
    WHERE rs.round_id = NEW.round_id
      AND p.status = 'active';

    v_active_raters := v_total_participants - v_skip_count;

    IF v_active_raters <= 0 THEN
        PERFORM complete_round_with_winner(NEW.round_id);
        PERFORM apply_adaptive_duration(NEW.round_id);
        RETURN NEW;
    END IF;

    v_threshold := LEAST(v_cap, GREATEST(v_active_raters - 1, 1));

    SELECT COALESCE(MIN(prop_ratings.cnt), 0) INTO v_min_ratings
    FROM (
        SELECT
            p.id,
            (
                SELECT COUNT(*) FROM grid_rankings gr
                WHERE gr.proposition_id = p.id
                  AND gr.round_id = NEW.round_id
            ) AS cnt
        FROM propositions p
        WHERE p.round_id = NEW.round_id
    ) prop_ratings;

    IF v_min_ratings >= v_threshold THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating skip — per-proposition threshold met (min_ratings=%, threshold=%, raters=%, skipped=%). Completing round %.',
            v_min_ratings, v_threshold, v_active_raters, v_skip_count, NEW.round_id;

        PERFORM complete_round_with_winner(NEW.round_id);
        PERFORM apply_adaptive_duration(NEW.round_id);
    END IF;

    RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4) skip_rating_with_cleanup — quota check uses active-only skip count
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.skip_rating_with_cleanup(
  p_round_id bigint,
  p_participant_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_round_phase text;
  v_skip_count integer;
  v_total_participants integer;
  v_rating_minimum integer;
  v_chat_id bigint;
  v_allow_skip boolean;
BEGIN
  SELECT user_id INTO v_user_id
  FROM participants WHERE id = p_participant_id;

  IF v_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Participant does not belong to current user';
  END IF;

  SELECT r.phase, c.chat_id INTO v_round_phase, v_chat_id
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE r.id = p_round_id;

  IF v_round_phase IS DISTINCT FROM 'rating' THEN
    RAISE EXCEPTION 'Round is not in rating phase';
  END IF;

  SELECT allow_skip_rating INTO v_allow_skip
  FROM chats WHERE id = v_chat_id;

  IF v_allow_skip IS NOT TRUE THEN
    RAISE EXCEPTION 'Skipping rating is not allowed in this chat';
  END IF;

  IF EXISTS (
    SELECT 1 FROM rating_skips
    WHERE round_id = p_round_id AND participant_id = p_participant_id
  ) THEN
    RAISE EXCEPTION 'Already skipped this round';
  END IF;

  -- Active-only skip count for the quota check (left skippers' preserved
  -- rows must not consume quota meant for currently-active participants)
  SELECT COUNT(*) INTO v_skip_count
  FROM rating_skips rs
  JOIN participants p ON p.id = rs.participant_id
  WHERE rs.round_id = p_round_id
    AND p.status = 'active';

  SELECT COUNT(*) INTO v_total_participants FROM participants WHERE chat_id = v_chat_id AND status = 'active';
  SELECT rating_minimum INTO v_rating_minimum FROM chats WHERE id = v_chat_id;
  v_rating_minimum := COALESCE(v_rating_minimum, 2);

  IF v_skip_count >= (v_total_participants - v_rating_minimum) THEN
    RAISE EXCEPTION 'Rating skip quota exceeded';
  END IF;

  DELETE FROM grid_rankings
  WHERE participant_id = p_participant_id
    AND proposition_id IN (
      SELECT id FROM propositions WHERE round_id = p_round_id
    );

  INSERT INTO rating_skips (round_id, participant_id)
  VALUES (p_round_id, p_participant_id);
END;
$$;
