-- Quick-create real runs: fund late joiners so they can actually vote.
--
-- The "Invite others to rank these" flow seeds a RATING round up front and funds
-- only the host (via seed_prioritization_round → fund_round_participants at that
-- moment). When an invitee later opens the link and joins, the round is already
-- running and they have no round_funding row — so get_chat_detail_bootstrap
-- reports is_my_participant_funded = false (because another participant IS
-- funded), the matches voting panel is hidden, and they just see the placeholder
-- card. They're also counted as an eligible rater, so the round can't even
-- complete until the 24h timer.
--
-- Fix: when an active human joins a quick-create chat (chats.max_cycles set) that
-- has an open rating round, fund them for it. Quick-create chats carry a very high
-- credit balance, so this never stalls on credits. Scoped to max_cycles chats so
-- normal chats (whose rounds fund everyone at creation via auto-start) are
-- untouched.
--
-- SECURITY DEFINER + search_path: cross-table DML from a participants trigger must
-- run as owner or RLS silently drops the round_funding insert.

CREATE OR REPLACE FUNCTION public.fund_quick_create_late_joiner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_max_cycles INTEGER;
  v_round_id BIGINT;
BEGIN
  -- Only active humans; pending/approval rows and agents are handled elsewhere.
  IF NEW.status <> 'active' OR COALESCE(NEW.is_agent, false) THEN
    RETURN NEW;
  END IF;

  SELECT max_cycles INTO v_max_cycles FROM public.chats WHERE id = NEW.chat_id;
  IF v_max_cycles IS NULL THEN
    RETURN NEW; -- not a quick-create chat
  END IF;

  SELECT r.id INTO v_round_id
  FROM public.rounds r
  JOIN public.cycles cy ON r.cycle_id = cy.id
  WHERE cy.chat_id = NEW.chat_id
    AND r.phase = 'rating'
    AND r.completed_at IS NULL
  ORDER BY r.id DESC
  LIMIT 1;

  IF v_round_id IS NOT NULL THEN
    INSERT INTO public.round_funding (round_id, participant_id)
    VALUES (v_round_id, NEW.id)
    ON CONFLICT (round_id, participant_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fund_quick_create_late_joiner ON public.participants;
CREATE TRIGGER trg_fund_quick_create_late_joiner
  AFTER INSERT ON public.participants
  FOR EACH ROW
  EXECUTE FUNCTION public.fund_quick_create_late_joiner();

COMMENT ON FUNCTION public.fund_quick_create_late_joiner() IS
  'Funds an active human who joins a quick-create chat (max_cycles set) that has an open rating round, so invitees to "Invite others to rank these" can vote (and count toward completion) instead of seeing the placeholder.';

-- Backfill: fund invitees who already joined an open quick-create rating round
-- before this fix existed (they're currently stuck on the placeholder).
INSERT INTO public.round_funding (round_id, participant_id)
SELECT r.id, p.id
FROM public.chats c
JOIN public.cycles cy ON cy.chat_id = c.id
JOIN public.rounds r ON r.cycle_id = cy.id
JOIN public.participants p ON p.chat_id = c.id
WHERE c.max_cycles IS NOT NULL
  AND r.phase = 'rating'
  AND r.completed_at IS NULL
  AND p.status = 'active'
  AND COALESCE(p.is_agent, false) = false
ON CONFLICT (round_id, participant_id) DO NOTHING;
