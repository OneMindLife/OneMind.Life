-- Migration: auto-kick inactive participants from the official OneMind chat.
--
-- The official chat (`chats.is_official = true`) is the public square — it
-- accumulates ghost participants (closed tabs, abandoned anonymous sessions)
-- that hold up early-advance thresholds for everyone else. This trigger
-- removes them from the chat the moment a round completes if they did
-- nothing across BOTH phases of that round.
--
-- Scope is intentionally narrow: ONLY chats where `is_official = true`.
-- Other chats keep their full active-participant population — host gets to
-- moderate manually.
--
-- "Did nothing this round" =
--   * no authored, non-carried proposition
--   * no proposing skip
--   * no grid ranking
--   * no rating skip
-- Any one of those keeps you in.
--
-- Mid-round joiners (`participants.created_at > rounds.created_at`) are
-- spared — they couldn't have participated in the part they missed.
--
-- Effect: kicked users are simply set to `status = 'kicked'`. The existing
-- early-advance triggers and most queries filter on `status = 'active'`
-- already, so kicked users instantly stop counting toward thresholds and
-- disappear from leaderboards / participant lists. They can manually
-- re-join via Discover if they want back in.

CREATE OR REPLACE FUNCTION public.kick_inactive_from_official_on_round_completion()
RETURNS TRIGGER AS $$
DECLARE
  v_chat_id BIGINT;
  v_is_official BOOLEAN;
BEGIN
  -- Fire only on the NULL → non-NULL transition.
  IF OLD.completed_at IS NOT NULL OR NEW.completed_at IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT cy.chat_id, c.is_official
  INTO v_chat_id, v_is_official
  FROM public.cycles cy
  JOIN public.chats c ON c.id = cy.chat_id
  WHERE cy.id = NEW.cycle_id;

  -- Only the official chat. Other chats keep their participants.
  IF v_is_official IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  UPDATE public.participants p
  SET status = 'kicked'
  WHERE p.chat_id = v_chat_id
    AND p.status = 'active'
    -- Never kick the host of the official chat (they OWN it).
    AND p.is_host IS NOT TRUE
    -- Only kick participants who were in the chat for the entire round.
    AND p.created_at <= NEW.created_at
    AND NOT EXISTS (
      SELECT 1 FROM public.propositions prop
      WHERE prop.round_id = NEW.id
        AND prop.participant_id = p.id
        AND prop.carried_from_id IS NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.round_skips rs
      WHERE rs.round_id = NEW.id AND rs.participant_id = p.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.grid_rankings gr
      WHERE gr.round_id = NEW.id AND gr.participant_id = p.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.rating_skips rs
      WHERE rs.round_id = NEW.id AND rs.participant_id = p.id
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_kick_inactive_from_official ON public.rounds;
CREATE TRIGGER trg_kick_inactive_from_official
AFTER UPDATE OF completed_at ON public.rounds
FOR EACH ROW
EXECUTE FUNCTION public.kick_inactive_from_official_on_round_completion();

COMMENT ON FUNCTION public.kick_inactive_from_official_on_round_completion IS
  'Kicks ghost participants (no participation across either phase) from '
  'the official OneMind chat at round completion. Hosts and mid-round '
  'joiners are spared. Only fires on chats with is_official = true.';
