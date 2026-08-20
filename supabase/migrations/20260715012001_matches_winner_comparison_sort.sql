-- Winner determination for MATCHES (pairwise) mode = the head-to-head
-- COMPARISON SORT the users actually watched — not the Elo/MOVDA score.
--
-- The bug: the wedge LIVE RANKING sorts by comparisonSort (head-to-head:
-- position from direct matchups vs neighbours, swap on any margin), but the
-- sealed winner was chosen by calculate_movda_scores_for_round (Elo SGD) →
-- ORDER BY global_score DESC. So the idea shown winning the sort could lose
-- the seal. This aligns them: for matches mode, global_score now encodes the
-- comparison-sort rank (#1 → 100), so BOTH seal paths
-- (complete_round_with_winner and the process-timers TS sealer, which both
-- select MAX(global_score)) crown the comparison-sort #1. Grid mode is
-- untouched — the Elo body is preserved verbatim under a new name and only
-- reached for non-matches rounds.
--
-- Mirrors wedge/lib/onemind/treeChat.ts comparisonSort exactly:
--   • head-to-head win counts (ties + skips carry NO margin → excluded)
--   • Copeland seed: (#opponents beaten) − (#lost to), tiebreak submission order
--   • adjacent bubble passes, swap on any margin, bounded to n (cycles settle)

-- 1) Preserve the existing Elo/MOVDA implementation verbatim (rename, not
--    re-transcribe). Guarded so the migration is idempotent.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'calculate_movda_elo_scores_for_round'
  ) THEN
    ALTER FUNCTION public.calculate_movda_scores_for_round(bigint, double precision)
      RENAME TO calculate_movda_elo_scores_for_round;
  END IF;
END $$;

-- 2) The head-to-head comparison sort → proposition_global_scores.
CREATE OR REPLACE FUNCTION public.calculate_pairwise_comparison_scores(p_round_id bigint)
RETURNS void
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
  ab      int;  -- times ids[i]   beat ids[i+1]
  ba      int;  -- times ids[i+1] beat ids[i]
BEGIN
  -- Direct head-to-head win counts. Ties and skips are NOT edges (no margin).
  DROP TABLE IF EXISTS _cs_h;
  CREATE TEMP TABLE _cs_h ON COMMIT DROP AS
    SELECT winner_proposition_id AS w, loser_proposition_id AS l, COUNT(*)::int AS c
    FROM pairwise_comparisons
    WHERE round_id = p_round_id AND is_tie = false AND is_skip = false
    GROUP BY 1, 2;
  CREATE INDEX ON _cs_h (w, l);

  -- Copeland seed (net head-to-head matchups), stable tiebreak = submission order.
  DROP TABLE IF EXISTS _cs_s;
  CREATE TEMP TABLE _cs_s ON COMMIT DROP AS
    SELECT p.id,
           ROW_NUMBER() OVER (ORDER BY p.created_at, p.id) AS seed_idx,
           0::int AS copeland
    FROM propositions p
    WHERE p.round_id = p_round_id;

  UPDATE _cs_s a SET copeland = (
    SELECT COALESCE(SUM(CASE
             WHEN COALESCE(hx.c, 0) > COALESCE(hy.c, 0) THEN 1
             WHEN COALESCE(hx.c, 0) < COALESCE(hy.c, 0) THEN -1
             ELSE 0 END), 0)
    FROM _cs_s b
    LEFT JOIN _cs_h hx ON hx.w = a.id AND hx.l = b.id
    LEFT JOIN _cs_h hy ON hy.w = b.id AND hy.l = a.id
    WHERE b.id <> a.id
  );

  SELECT array_agg(id ORDER BY copeland DESC, seed_idx ASC) INTO ids FROM _cs_s;
  n := COALESCE(array_length(ids, 1), 0);
  IF n = 0 THEN
    DELETE FROM proposition_global_scores WHERE round_id = p_round_id;
    RETURN;
  END IF;

  -- Adjacent bubble passes: a lower neighbour that beat the upper one directly
  -- rises past it (ANY margin). Bounded to n ⇒ a non-transitive cycle settles.
  FOR pass IN 1..n LOOP
    swapped := false;
    FOR i IN 1..(n - 1) LOOP
      SELECT c INTO ab FROM _cs_h WHERE w = ids[i]     AND l = ids[i + 1];
      SELECT c INTO ba FROM _cs_h WHERE w = ids[i + 1] AND l = ids[i];
      IF COALESCE(ba, 0) > COALESCE(ab, 0) THEN
        tmp := ids[i]; ids[i] := ids[i + 1]; ids[i + 1] := tmp;
        swapped := true;
      END IF;
    END LOOP;
    EXIT WHEN NOT swapped;
  END LOOP;

  -- position 1 → 100, position n → 0. Winner = highest = comparison-sort #1.
  DELETE FROM proposition_global_scores WHERE round_id = p_round_id;
  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
  SELECT p_round_id, ids[s.pos],
         (CASE WHEN n <= 1 THEN 100.0
               ELSE 100.0 * (n - s.pos) / (n - 1) END)::real,
         NOW()
  FROM generate_subscripts(ids, 1) AS s(pos);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.calculate_pairwise_comparison_scores(bigint)
  FROM PUBLIC, anon, authenticated;

-- 3) Dispatcher keeps the original name/signature both seal paths call.
CREATE OR REPLACE FUNCTION public.calculate_movda_scores_for_round(
  p_round_id bigint,
  p_seed double precision DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mode text;
BEGIN
  SELECT ch.rating_mode INTO v_mode
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = p_round_id;

  IF v_mode = 'matches' THEN
    -- Winner must equal the head-to-head sort the room watched.
    PERFORM public.calculate_pairwise_comparison_scores(p_round_id);
  ELSE
    PERFORM public.calculate_movda_elo_scores_for_round(p_round_id, p_seed);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.calculate_movda_scores_for_round(bigint, double precision)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.calculate_pairwise_comparison_scores(bigint) IS
  'Matches-mode winner scoring: head-to-head comparison sort (Copeland seed + adjacent bubble, swap on any margin) → global_score, #1=100. Mirrors wedge treeChat.ts comparisonSort. See 20260714210000.';
COMMENT ON FUNCTION public.calculate_movda_scores_for_round(bigint, double precision) IS
  'Dispatcher: matches mode → head-to-head comparison sort (calculate_pairwise_comparison_scores); else Elo/MOVDA (calculate_movda_elo_scores_for_round). Both seal paths select MAX(global_score).';
