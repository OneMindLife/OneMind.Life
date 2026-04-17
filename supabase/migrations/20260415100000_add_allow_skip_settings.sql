-- =============================================================================
-- MIGRATION: Add per-chat skip settings
-- =============================================================================
-- Adds allow_skip_proposing and allow_skip_rating boolean columns to chats.
-- When false, users cannot skip the respective phase.
-- Defaults to true for backward compatibility.
--
-- Updates:
-- 1. chats table: two new columns
-- 2. round_skips INSERT policy: check allow_skip_proposing
-- 3. rating_skips INSERT policy: check allow_skip_rating
-- 4. skip_rating_with_cleanup RPC: check allow_skip_rating
-- 5. count_rating_skips helper: unchanged
-- =============================================================================

-- Add columns to chats table
ALTER TABLE public.chats
  ADD COLUMN allow_skip_proposing BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN allow_skip_rating BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.chats.allow_skip_proposing IS
  'When false, participants cannot skip the proposing phase';
COMMENT ON COLUMN public.chats.allow_skip_rating IS
  'When false, participants cannot skip the rating phase';

-- =============================================================================
-- Update round_skips INSERT policy to check allow_skip_proposing
-- =============================================================================
DROP POLICY IF EXISTS "Users can skip in rounds they participate in" ON public.round_skips;

CREATE POLICY "Users can skip in rounds they participate in" ON public.round_skips
    FOR INSERT WITH CHECK (
        -- Verify chat allows skipping proposing
        EXISTS (
            SELECT 1 FROM chats ch
            JOIN cycles c ON c.chat_id = ch.id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_id AND ch.allow_skip_proposing = true
        )
        -- Verify participant belongs to current user
        AND participant_id IN (
            SELECT id FROM participants WHERE user_id = auth.uid()
        )
        -- Verify round is in proposing phase
        AND EXISTS (
            SELECT 1 FROM rounds WHERE id = round_id AND phase = 'proposing'
        )
        -- Verify user hasn't already submitted a proposition
        AND NOT EXISTS (
            SELECT 1 FROM propositions
            WHERE round_id = round_skips.round_id
            AND participant_id = round_skips.participant_id
            AND carried_from_id IS NULL
        )
        -- Verify skip quota not exceeded
        AND (
            SELECT COUNT(*) FROM round_skips rs WHERE rs.round_id = round_skips.round_id
        ) < (
            SELECT COUNT(*) FROM participants p
            JOIN cycles c ON p.chat_id = c.chat_id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_skips.round_id AND p.status = 'active'
        ) - (
            SELECT ch.proposing_minimum FROM chats ch
            JOIN cycles c ON c.chat_id = ch.id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_skips.round_id
        )
    );

-- =============================================================================
-- Update rating_skips INSERT policy to check allow_skip_rating
-- =============================================================================
DROP POLICY IF EXISTS "Users can skip rating in rounds they participate in" ON public.rating_skips;

CREATE POLICY "Users can skip rating in rounds they participate in" ON public.rating_skips
    FOR INSERT WITH CHECK (
        -- Verify chat allows skipping rating
        EXISTS (
            SELECT 1 FROM chats ch
            JOIN cycles c ON c.chat_id = ch.id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = round_id AND ch.allow_skip_rating = true
        )
        -- Verify participant belongs to current user
        AND participant_id IN (
            SELECT id FROM participants WHERE user_id = auth.uid()
        )
        -- Verify round is in rating phase
        AND EXISTS (
            SELECT 1 FROM rounds WHERE id = round_id AND phase = 'rating'
        )
        -- Verify user hasn't already submitted any ratings for this round
        AND NOT EXISTS (
            SELECT 1 FROM grid_rankings gr
            JOIN propositions p ON p.id = gr.proposition_id
            WHERE p.round_id = rating_skips.round_id
            AND gr.participant_id = rating_skips.participant_id
        )
        -- Verify skip quota not exceeded
        AND count_rating_skips(round_id) < (
            SELECT COUNT(*)::INTEGER FROM participants p
            JOIN cycles c ON p.chat_id = c.chat_id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = rating_skips.round_id AND p.status = 'active'
        ) - COALESCE((
            SELECT ch.rating_minimum FROM chats ch
            JOIN cycles c ON c.chat_id = ch.id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = rating_skips.round_id
        ), 2)
    );

-- =============================================================================
-- Update skip_rating_with_cleanup RPC to check allow_skip_rating
-- =============================================================================
CREATE OR REPLACE FUNCTION skip_rating_with_cleanup(
  p_round_id BIGINT,
  p_participant_id BIGINT
)
RETURNS VOID
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
  -- Verify the participant belongs to the calling user
  SELECT user_id INTO v_user_id
  FROM participants WHERE id = p_participant_id;

  IF v_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Participant does not belong to current user';
  END IF;

  -- Verify round is in rating phase and get chat_id
  SELECT r.phase, c.chat_id INTO v_round_phase, v_chat_id
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  WHERE r.id = p_round_id;

  IF v_round_phase IS DISTINCT FROM 'rating' THEN
    RAISE EXCEPTION 'Round is not in rating phase';
  END IF;

  -- Check chat allows skipping rating
  SELECT allow_skip_rating INTO v_allow_skip
  FROM chats WHERE id = v_chat_id;

  IF v_allow_skip IS NOT TRUE THEN
    RAISE EXCEPTION 'Skipping rating is not allowed in this chat';
  END IF;

  -- Check not already skipped
  IF EXISTS (
    SELECT 1 FROM rating_skips
    WHERE round_id = p_round_id AND participant_id = p_participant_id
  ) THEN
    RAISE EXCEPTION 'Already skipped this round';
  END IF;

  -- Check skip quota
  SELECT COUNT(*) INTO v_skip_count FROM rating_skips WHERE round_id = p_round_id;
  SELECT COUNT(*) INTO v_total_participants FROM participants WHERE chat_id = v_chat_id AND status = 'active';
  SELECT rating_minimum INTO v_rating_minimum FROM chats WHERE id = v_chat_id;
  v_rating_minimum := COALESCE(v_rating_minimum, 2);

  IF v_skip_count >= (v_total_participants - v_rating_minimum) THEN
    RAISE EXCEPTION 'Rating skip quota exceeded';
  END IF;

  -- Delete any intermediate grid_rankings for this round + participant
  DELETE FROM grid_rankings
  WHERE participant_id = p_participant_id
    AND proposition_id IN (
      SELECT id FROM propositions WHERE round_id = p_round_id
    );

  -- Insert the rating skip
  INSERT INTO rating_skips (round_id, participant_id)
  VALUES (p_round_id, p_participant_id);
END;
$$;

COMMENT ON FUNCTION skip_rating_with_cleanup IS
  'Atomically skips rating: deletes any intermediate grid_rankings, then inserts a rating_skip. '
  'Validates ownership, phase, chat settings, and skip quota. Called from the rating screen skip button.';
