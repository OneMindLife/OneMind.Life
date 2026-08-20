-- Auto-watch your own opinions: posting is the highest-intent watch — you want
-- to know when people reply. Repository chats only (the surface with a watch
-- UI); skips AI/null authors and carried winners. (Column renamed to new_count
-- by the following migration; original used match_count.)
CREATE FUNCTION public.auto_watch_own_opinion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid; v_never_seals boolean;
BEGIN
  IF NEW.participant_id IS NULL OR NEW.carried_from_id IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT c.never_seals, p.user_id INTO v_never_seals, v_uid
  FROM rounds r
  JOIN cycles cy ON cy.id = r.cycle_id
  JOIN chats c ON c.id = cy.chat_id
  JOIN participants p ON p.id = NEW.participant_id
  WHERE r.id = NEW.round_id;
  IF v_never_seals IS NOT TRUE OR v_uid IS NULL THEN
    RETURN NEW;
  END IF;
  INSERT INTO opinion_watches (participant_id, proposition_id, user_id, match_count, last_activity_at)
  VALUES (NEW.participant_id, NEW.id, v_uid, 0, NULL)
  ON CONFLICT (participant_id, proposition_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER auto_watch_own_opinion_trg
  AFTER INSERT ON public.propositions
  FOR EACH ROW EXECUTE FUNCTION public.auto_watch_own_opinion();
