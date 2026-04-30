-- Expand the inactive-kick trigger from "official chat only" to "all
-- public chats."
--
-- Originally (20260419010911) the auto-kick was scoped to chats with
-- is_official = true on the theory that other hosts moderate manually.
-- In practice, every public chat reachable from Discover accumulates
-- the same tab-closer / abandoned-anonymous-session ghosts that were
-- the original problem — they hold up early-advance thresholds for
-- engaged users in chats with custom hosts who have no realistic way
-- to babysit kicks.
--
-- New scope: any chat with access_method = 'public' (which includes
-- the official chat). Invite-only and personal-code chats are still
-- host-moderated — those hosts curated the participants and may
-- legitimately want quiet-but-still-on-the-list members.
--
-- Function name retained (`kick_inactive_from_official_on_round_completion`)
-- for migration-history stability. Body and comment now reflect the
-- broader scope; the "from_official" suffix in the name is legacy.

CREATE OR REPLACE FUNCTION public.kick_inactive_from_official_on_round_completion()
RETURNS TRIGGER AS $$
DECLARE
  v_chat_id BIGINT;
  v_access_method TEXT;
BEGIN
  -- Fire only on the NULL → non-NULL transition.
  IF OLD.completed_at IS NOT NULL OR NEW.completed_at IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT cy.chat_id, c.access_method
  INTO v_chat_id, v_access_method
  FROM public.cycles cy
  JOIN public.chats c ON c.id = cy.chat_id
  WHERE cy.id = NEW.cycle_id;

  -- Public chats only (official chats are public, so they're covered).
  -- Invite-only and personal-code chats stay host-moderated.
  IF v_access_method != 'public' THEN
    RETURN NEW;
  END IF;

  UPDATE public.participants p
  SET status = 'kicked'
  WHERE p.chat_id = v_chat_id
    AND p.status = 'active'
    -- Never kick the host of the chat (they OWN it).
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

COMMENT ON FUNCTION public.kick_inactive_from_official_on_round_completion IS
  'Kicks ghost participants (no participation across either phase) at '
  'round completion from any public chat (access_method = ''public''), '
  'including the official OneMind chat. Hosts and mid-round joiners are '
  'spared. Invite-only and personal-code chats are skipped (host moderates '
  'manually). Function name retained from when this only applied to the '
  'official chat — see migration 20260430140000.';
