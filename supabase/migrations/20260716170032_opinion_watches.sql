-- ── Watch an opinion, be shown its votable threads ──────────────────────────
-- A participant "watches" an opinion; the row also caches the LIVE state of that
-- watched thread for THIS watcher: how many pairwise matches they still owe in
-- its direct child thread, and when those pending opinions last arrived. The
-- cache is maintained by triggers (below) so clients realtime-subscribe to their
-- own rows instead of recomputing. The bell "inbox" is just: rows WHERE
-- match_count > 0, ordered most-matches-first then oldest-activity-first.
CREATE TABLE public.opinion_watches (
  participant_id   bigint NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
  proposition_id   bigint NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
  user_id          uuid   NOT NULL,   -- denormalized for same-row RLS + realtime
  match_count      int    NOT NULL DEFAULT 0,
  last_activity_at timestamptz,       -- newest still-unvoted child opinion
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (participant_id, proposition_id)
);
CREATE INDEX opinion_watches_prop_idx ON public.opinion_watches (proposition_id);
CREATE INDEX opinion_watches_user_idx ON public.opinion_watches (user_id);

-- Pending pairwise MATCHES this watcher owes in an opinion's DIRECT child thread
-- (floor(unplaced/2)), plus the newest such opinion's time. "Unplaced" = new
-- (not carried), not the watcher's own, not yet judged by them — same rule as
-- get_unplaced_opinion_count, scoped to the children of one opinion.
CREATE FUNCTION public._watch_state(p_participant_id bigint, p_proposition_id bigint)
RETURNS TABLE(match_count int, last_activity_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT (count(*) / 2)::int, max(cp.created_at)
  FROM cycles cc
  JOIN rounds cr ON cr.cycle_id = cc.id
  JOIN propositions cp ON cp.round_id = cr.id
  WHERE cc.parent_proposition_id = p_proposition_id
    AND cp.carried_from_id IS NULL
    AND cp.participant_id IS DISTINCT FROM p_participant_id
    AND NOT EXISTS (
      SELECT 1 FROM pairwise_comparisons pc
      WHERE pc.round_id = cp.round_id
        AND pc.participant_id = p_participant_id
        AND (pc.winner_proposition_id = cp.id OR pc.loser_proposition_id = cp.id)
    );
$$;

-- A NEW opinion arrived → recache every watcher of its thread's parent (except
-- the author, whose own opinion never counts toward their matches).
CREATE FUNCTION public.sync_watch_on_opinion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_parent bigint;
BEGIN
  SELECT cc.parent_proposition_id INTO v_parent
  FROM rounds cr JOIN cycles cc ON cc.id = cr.cycle_id
  WHERE cr.id = NEW.round_id;
  IF v_parent IS NULL THEN RETURN NEW; END IF;  -- root round, nothing watches it as a thread
  UPDATE opinion_watches ow
  SET (match_count, last_activity_at, updated_at) = (
    SELECT s.match_count, s.last_activity_at, now()
    FROM public._watch_state(ow.participant_id, v_parent) s
  )
  WHERE ow.proposition_id = v_parent
    AND ow.participant_id IS DISTINCT FROM NEW.participant_id;
  RETURN NEW;
END;
$$;

-- A vote happened → only the VOTER's own matches change (matches are per-user),
-- so recache just their row. Hot path: bail instantly if they watch nothing.
CREATE FUNCTION public.sync_watch_on_vote()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_parent bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM opinion_watches WHERE participant_id = NEW.participant_id) THEN
    RETURN NEW;
  END IF;
  SELECT cc.parent_proposition_id INTO v_parent
  FROM rounds cr JOIN cycles cc ON cc.id = cr.cycle_id
  WHERE cr.id = NEW.round_id;
  IF v_parent IS NULL THEN RETURN NEW; END IF;
  UPDATE opinion_watches ow
  SET (match_count, last_activity_at, updated_at) = (
    SELECT s.match_count, s.last_activity_at, now()
    FROM public._watch_state(ow.participant_id, v_parent) s
  )
  WHERE ow.participant_id = NEW.participant_id AND ow.proposition_id = v_parent;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_watch_on_opinion_trg
  AFTER INSERT ON public.propositions
  FOR EACH ROW EXECUTE FUNCTION public.sync_watch_on_opinion();
CREATE TRIGGER sync_watch_on_vote_trg
  AFTER INSERT ON public.pairwise_comparisons
  FOR EACH ROW EXECUTE FUNCTION public.sync_watch_on_vote();

-- Toggle a watch. Ownership-checked (participant must belong to the caller).
CREATE FUNCTION public.set_opinion_watch(
  p_participant_id bigint, p_proposition_id bigint, p_watch boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM participants WHERE id = p_participant_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'not your participant';
  END IF;
  IF p_watch THEN
    INSERT INTO opinion_watches (participant_id, proposition_id, user_id, match_count, last_activity_at)
    SELECT p_participant_id, p_proposition_id, auth.uid(), s.match_count, s.last_activity_at
    FROM public._watch_state(p_participant_id, p_proposition_id) s
    ON CONFLICT (participant_id, proposition_id) DO NOTHING;
  ELSE
    DELETE FROM opinion_watches
    WHERE participant_id = p_participant_id AND proposition_id = p_proposition_id;
  END IF;
END;
$$;

-- The live bell inbox: watched threads that currently have matches, best first.
CREATE FUNCTION public.get_watched_matches(p_participant_id bigint)
RETURNS TABLE(proposition_id bigint, content text, match_count int, last_activity_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT ow.proposition_id, p.content, ow.match_count, ow.last_activity_at
  FROM opinion_watches ow
  JOIN propositions p ON p.id = ow.proposition_id
  WHERE ow.participant_id = p_participant_id AND ow.match_count > 0
  ORDER BY ow.match_count DESC, ow.last_activity_at ASC NULLS LAST;
$$;

-- All watched proposition ids (for the watch-toggle state in the UI).
CREATE FUNCTION public.get_watched_ids(p_participant_id bigint)
RETURNS TABLE(proposition_id bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT proposition_id FROM opinion_watches WHERE participant_id = p_participant_id;
$$;

-- RLS: read your own rows only (single-row check → realtime delivers). Writes
-- go exclusively through the SECURITY DEFINER RPC above.
ALTER TABLE public.opinion_watches ENABLE ROW LEVEL SECURITY;
CREATE POLICY opinion_watches_select_own ON public.opinion_watches
  FOR SELECT USING (user_id = auth.uid());

GRANT SELECT ON public.opinion_watches TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_opinion_watch(bigint, bigint, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_watched_matches(bigint) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_watched_ids(bigint) TO anon, authenticated;

ALTER PUBLICATION supabase_realtime ADD TABLE public.opinion_watches;
