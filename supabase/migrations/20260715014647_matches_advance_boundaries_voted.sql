-- Matches-mode advance rule (Joel, 2026-07-15): only seal a rating round once
-- EVERY adjacent boundary in the current comparison-sort order has at least one
-- vote. If any neighbour pair in the live ordering has 0 votes, the order there
-- is undetermined → do NOT advance (the timer just extends and the attention
-- router keeps routing voters to the uncovered boundaries).
--
-- This replaces the old matches timer-advance gate (done >= 1 finished raters),
-- which could leave a large-board round hanging at an expired timer.

-- Single source of truth for the head-to-head comparison-sort ORDER (Copeland
-- seed + adjacent bubble, swap on any margin). Both the winner scorer and the
-- advance gate use it, so the "boundaries" checked are exactly the boundaries
-- the winner is derived from.
CREATE OR REPLACE FUNCTION public.pairwise_comparison_order(p_round_id bigint)
RETURNS bigint[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  ids     bigint[];
  n       int;
  i       int;
  pass    int;
  swapped boolean;
  tmp     bigint;
  ab      int;
  ba      int;
BEGIN
  DROP TABLE IF EXISTS _pco_h;
  CREATE TEMP TABLE _pco_h ON COMMIT DROP AS
    SELECT winner_proposition_id AS w, loser_proposition_id AS l, COUNT(*)::int AS c
    FROM pairwise_comparisons
    WHERE round_id = p_round_id AND is_tie = false AND is_skip = false
    GROUP BY 1, 2;
  CREATE INDEX ON _pco_h (w, l);

  DROP TABLE IF EXISTS _pco_s;
  CREATE TEMP TABLE _pco_s ON COMMIT DROP AS
    SELECT p.id,
           ROW_NUMBER() OVER (ORDER BY p.created_at, p.id) AS seed_idx,
           0::int AS copeland
    FROM propositions p
    WHERE p.round_id = p_round_id;

  UPDATE _pco_s a SET copeland = (
    SELECT COALESCE(SUM(CASE
             WHEN COALESCE(hx.c, 0) > COALESCE(hy.c, 0) THEN 1
             WHEN COALESCE(hx.c, 0) < COALESCE(hy.c, 0) THEN -1
             ELSE 0 END), 0)
    FROM _pco_s b
    LEFT JOIN _pco_h hx ON hx.w = a.id AND hx.l = b.id
    LEFT JOIN _pco_h hy ON hy.w = b.id AND hy.l = a.id
    WHERE b.id <> a.id
  );

  SELECT array_agg(id ORDER BY copeland DESC, seed_idx ASC) INTO ids FROM _pco_s;
  n := COALESCE(array_length(ids, 1), 0);
  IF n < 2 THEN RETURN ids; END IF;

  FOR pass IN 1..n LOOP
    swapped := false;
    FOR i IN 1..(n - 1) LOOP
      SELECT c INTO ab FROM _pco_h WHERE w = ids[i]     AND l = ids[i + 1];
      SELECT c INTO ba FROM _pco_h WHERE w = ids[i + 1] AND l = ids[i];
      IF COALESCE(ba, 0) > COALESCE(ab, 0) THEN
        tmp := ids[i]; ids[i] := ids[i + 1]; ids[i + 1] := tmp;
        swapped := true;
      END IF;
    END LOOP;
    EXIT WHEN NOT swapped;
  END LOOP;

  RETURN ids;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.pairwise_comparison_order(bigint) FROM PUBLIC, anon, authenticated;

-- Winner scorer now delegates ordering to the shared function.
CREATE OR REPLACE FUNCTION public.calculate_pairwise_comparison_scores(p_round_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  ids bigint[];
  n   int;
BEGIN
  ids := public.pairwise_comparison_order(p_round_id);
  n := COALESCE(array_length(ids, 1), 0);
  DELETE FROM proposition_global_scores WHERE round_id = p_round_id;
  IF n = 0 THEN RETURN; END IF;
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
  SELECT p_round_id, ids[s.pos],
         (CASE WHEN n <= 1 THEN 100.0
               ELSE 100.0 * (n - s.pos) / (n - 1) END)::real,
         NOW()
  FROM generate_subscripts(ids, 1) AS s(pos);
END;
$$;

-- The advance gate: true iff every adjacent boundary in the current order has
-- >= 1 vote (a non-skip comparison; a tie counts — it's a judgment, a skip
-- isn't). n < 2 ⇒ nothing to sort ⇒ ready.
CREATE OR REPLACE FUNCTION public.matches_all_boundaries_voted(p_round_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  ids bigint[];
  n   int;
  i   int;
BEGIN
  ids := public.pairwise_comparison_order(p_round_id);
  n := COALESCE(array_length(ids, 1), 0);
  IF n < 2 THEN RETURN true; END IF;
  FOR i IN 1..(n - 1) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pairwise_comparisons pc
      WHERE pc.round_id = p_round_id AND pc.is_skip = false
        AND ( (pc.winner_proposition_id = ids[i]   AND pc.loser_proposition_id = ids[i + 1])
           OR (pc.winner_proposition_id = ids[i + 1] AND pc.loser_proposition_id = ids[i]) )
    ) THEN
      RETURN false;  -- this neighbour boundary has no vote → not ready
    END IF;
  END LOOP;
  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.matches_all_boundaries_voted(bigint) TO service_role;
REVOKE EXECUTE ON FUNCTION public.matches_all_boundaries_voted(bigint) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.pairwise_comparison_order(bigint) IS
  'Head-to-head comparison-sort order (Copeland + adjacent bubble). Shared by the winner scorer and the advance gate so both agree. See 20260715014000.';
COMMENT ON FUNCTION public.matches_all_boundaries_voted(bigint) IS
  'Matches advance gate: true iff every adjacent boundary in the current comparison-sort order has >=1 non-skip vote. Used by process-timers to hold a round open until the ordering is fully contested.';
