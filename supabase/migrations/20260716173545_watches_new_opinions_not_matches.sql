-- Reframe: a watch tracks NEW OPINIONS (replies) in a thread since you last
-- viewed it — the reward is seeing new discussion, not owing votes. `new_count`
-- increments on each reply (except your own) and resets when you view the thread.
-- Votes are now irrelevant to watches, so that machinery is dropped.
DROP TRIGGER IF EXISTS sync_watch_on_vote_trg ON public.pairwise_comparisons;
DROP FUNCTION IF EXISTS public.sync_watch_on_vote();
DROP FUNCTION IF EXISTS public._watch_state(bigint, bigint);
DROP FUNCTION IF EXISTS public.get_watched(bigint);

ALTER TABLE public.opinion_watches RENAME COLUMN match_count TO new_count;

-- A new opinion → every watcher of its thread's parent (except the author) gets
-- one more unseen reply. Carried winners aren't new discussion.
CREATE OR REPLACE FUNCTION public.sync_watch_on_opinion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_parent bigint;
BEGIN
  IF NEW.carried_from_id IS NOT NULL THEN RETURN NEW; END IF;
  SELECT cc.parent_proposition_id INTO v_parent
  FROM rounds cr JOIN cycles cc ON cc.id = cr.cycle_id
  WHERE cr.id = NEW.round_id;
  IF v_parent IS NULL THEN RETURN NEW; END IF;
  UPDATE opinion_watches
  SET new_count = new_count + 1, last_activity_at = NEW.created_at, updated_at = now()
  WHERE proposition_id = v_parent
    AND participant_id IS DISTINCT FROM NEW.participant_id;
  RETURN NEW;
END;
$$;

-- Mark a watched thread seen (reset unseen) — called when you view it.
CREATE FUNCTION public.mark_watch_seen(p_participant_id bigint, p_proposition_id bigint)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  UPDATE public.opinion_watches SET new_count = 0, updated_at = now()
  WHERE participant_id = p_participant_id AND proposition_id = p_proposition_id AND new_count > 0;
$$;
GRANT EXECUTE ON FUNCTION public.mark_watch_seen(bigint, bigint) TO anon, authenticated;

-- A fresh watch starts with 0 unseen (you're watching from now on).
CREATE OR REPLACE FUNCTION public.set_opinion_watch(
  p_participant_id bigint, p_proposition_id bigint, p_watch boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM participants WHERE id = p_participant_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'not your participant';
  END IF;
  IF p_watch THEN
    INSERT INTO opinion_watches (participant_id, proposition_id, user_id, new_count, last_activity_at)
    VALUES (p_participant_id, p_proposition_id, auth.uid(), 0, NULL)
    ON CONFLICT (participant_id, proposition_id) DO NOTHING;
  ELSE
    DELETE FROM opinion_watches WHERE participant_id = p_participant_id AND proposition_id = p_proposition_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.auto_watch_own_opinion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid; v_never_seals boolean;
BEGIN
  IF NEW.participant_id IS NULL OR NEW.carried_from_id IS NOT NULL THEN RETURN NEW; END IF;
  SELECT c.never_seals, p.user_id INTO v_never_seals, v_uid
  FROM rounds r JOIN cycles cy ON cy.id = r.cycle_id
  JOIN chats c ON c.id = cy.chat_id
  JOIN participants p ON p.id = NEW.participant_id
  WHERE r.id = NEW.round_id;
  IF v_never_seals IS NOT TRUE OR v_uid IS NULL THEN RETURN NEW; END IF;
  INSERT INTO opinion_watches (participant_id, proposition_id, user_id, new_count, last_activity_at)
  VALUES (NEW.participant_id, NEW.id, v_uid, 0, NULL)
  ON CONFLICT (participant_id, proposition_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.get_watched(p_participant_id bigint)
RETURNS TABLE(proposition_id bigint, content text, new_count int, last_activity_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT ow.proposition_id, p.content, ow.new_count, ow.last_activity_at
  FROM opinion_watches ow JOIN propositions p ON p.id = ow.proposition_id
  WHERE ow.participant_id = p_participant_id
  ORDER BY (ow.new_count > 0) DESC, ow.new_count DESC,
           ow.last_activity_at ASC NULLS LAST, ow.created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_watched(bigint) TO anon, authenticated;

UPDATE public.opinion_watches SET new_count = 0;
