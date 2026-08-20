-- Configurable scoring/sorting algorithm for OneMind (Joel, 2026-07-15).
--
-- Architecture: server-authoritative, config-driven STRATEGY pattern.
--   • Single source of truth = proposition_global_scores. Client display,
--     winner-at-seal, and results all READ it; nothing scores client-side.
--   • Each algorithm is one function score_x(round_id) -> writes those scores.
--   • chats.scoring_algorithm picks the strategy (null = auto by rating_mode).
--   • A dispatcher resolves config -> strategy. Adding an algorithm = one
--     function + one CASE arm + one enum value; the client never changes.
--   • Recompute: 30-min cron for active rounds w/ new votes + fresh at seal.
--   • Winner = MAX(global_score), unchanged, works for every strategy.

-- 1) Config column ----------------------------------------------------------
ALTER TABLE public.chats
  ADD COLUMN IF NOT EXISTS scoring_algorithm text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chats_scoring_algorithm_check'
  ) THEN
    ALTER TABLE public.chats
      ADD CONSTRAINT chats_scoring_algorithm_check
      CHECK (scoring_algorithm IS NULL OR scoring_algorithm IN
             ('bradley_terry', 'head_to_head', 'elo_movda'));
  END IF;
END $$;

COMMENT ON COLUMN public.chats.scoring_algorithm IS
  'Scoring strategy for this chat''s rankings/winner. NULL = auto (matches -> bradley_terry, grid -> elo_movda). See 20260715020000.';

-- Resolve the effective algorithm for a round.
CREATE OR REPLACE FUNCTION public.resolve_scoring_algorithm(p_round_id bigint)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
           ch.scoring_algorithm,
           CASE WHEN ch.rating_mode = 'matches' THEN 'bradley_terry'
                ELSE 'elo_movda' END)
  FROM rounds r
  JOIN cycles c ON c.id = r.cycle_id
  JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = p_round_id;
$$;

-- 2) Bradley-Terry strategy -------------------------------------------------
-- Latent-strength model: P(i beats j) = s_i/(s_i+s_j), fit by MM iteration
-- (Hunter 2004). Ties = half a win to each side; skips are not edges. Unlike
-- the head-to-head sort it yields a definitive ranking from ANY votes (no need
-- for every boundary contested), so rounds always resolve. global_score =
-- field win probability (avg over opponents of s_i/(s_i+s_j)) * 100; unplayed
-- props sit at 0.
CREATE OR REPLACE FUNCTION public.score_bradley_terry(p_round_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  it int;
  n_played int;
BEGIN
  DROP TABLE IF EXISTS _bt_items, _bt_w, _bt_pairs, _bt_p;
  CREATE TEMP TABLE _bt_items ON COMMIT DROP AS
    SELECT p.id AS prop_id FROM propositions p
    WHERE p.round_id = p_round_id
      AND EXISTS (SELECT 1 FROM pairwise_comparisons pc
                  WHERE pc.round_id = p_round_id AND pc.is_skip = false
                    AND (pc.winner_proposition_id = p.id OR pc.loser_proposition_id = p.id));
  SELECT count(*) INTO n_played FROM _bt_items;

  DELETE FROM proposition_global_scores WHERE round_id = p_round_id;

  IF n_played = 0 THEN
    RETURN;  -- no votes yet → no ranking
  ELSIF n_played = 1 THEN
    INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
    SELECT p_round_id, prop_id, 100.0::real, NOW() FROM _bt_items;
    -- other props (unplayed) stay unscored (absent) → render below the scored one
    RETURN;
  END IF;

  CREATE TEMP TABLE _bt_w ON COMMIT DROP AS
    SELECT i.prop_id, COALESCE(SUM(CASE
        WHEN pc.winner_proposition_id = i.prop_id AND pc.is_tie = false THEN 1.0
        WHEN pc.is_tie THEN 0.5 ELSE 0 END), 0)::double precision AS w
    FROM _bt_items i
    LEFT JOIN pairwise_comparisons pc ON pc.round_id = p_round_id AND pc.is_skip = false
      AND (pc.winner_proposition_id = i.prop_id OR pc.loser_proposition_id = i.prop_id)
    GROUP BY i.prop_id;

  CREATE TEMP TABLE _bt_pairs ON COMMIT DROP AS
    SELECT LEAST(pc.winner_proposition_id, pc.loser_proposition_id) a,
           GREATEST(pc.winner_proposition_id, pc.loser_proposition_id) b,
           COUNT(*)::double precision n
    FROM pairwise_comparisons pc
    WHERE pc.round_id = p_round_id AND pc.is_skip = false
    GROUP BY 1, 2;

  CREATE TEMP TABLE _bt_p ON COMMIT DROP AS
    SELECT prop_id, 1.0::double precision AS p FROM _bt_items;

  FOR it IN 1..200 LOOP
    WITH terms AS (
      SELECT pr.a id, pr.n / (pa.p + pb.p) t
        FROM _bt_pairs pr JOIN _bt_p pa ON pa.prop_id = pr.a JOIN _bt_p pb ON pb.prop_id = pr.b
      UNION ALL
      SELECT pr.b id, pr.n / (pa.p + pb.p) t
        FROM _bt_pairs pr JOIN _bt_p pa ON pa.prop_id = pr.a JOIN _bt_p pb ON pb.prop_id = pr.b
    ),
    denom AS (SELECT id, SUM(t) d FROM terms GROUP BY id),
    newp AS (SELECT w.prop_id, CASE WHEN d.d > 0 THEN w.w / d.d ELSE 1e-9 END np
             FROM _bt_w w JOIN denom d ON d.id = w.prop_id),
    norm AS (SELECT SUM(np) s FROM newp)
    UPDATE _bt_p SET p = GREATEST(n.np / (SELECT s FROM norm), 1e-12)
    FROM newp n WHERE _bt_p.prop_id = n.prop_id;
  END LOOP;

  INSERT INTO proposition_global_scores (round_id, proposition_id, global_score, last_updated)
  SELECT p_round_id, pr.id,
         LEAST(100.0, GREATEST(0.0, COALESCE((
           SELECT AVG(pi.p / (pi.p + pj.p)) * 100.0
           FROM _bt_p pi, _bt_p pj
           WHERE pi.prop_id = pr.id AND pj.prop_id <> pr.id
         ), 0.0)))::real,
         NOW()
  FROM propositions pr
  WHERE pr.round_id = p_round_id
    AND EXISTS (SELECT 1 FROM _bt_items i WHERE i.prop_id = pr.id);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.score_bradley_terry(bigint) FROM PUBLIC, anon, authenticated;

-- 3) Config-driven dispatcher (keeps the name both seal paths already call) --
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
  v_algo text;
BEGIN
  v_algo := public.resolve_scoring_algorithm(p_round_id);
  CASE v_algo
    WHEN 'bradley_terry' THEN PERFORM public.score_bradley_terry(p_round_id);
    WHEN 'head_to_head'  THEN PERFORM public.calculate_pairwise_comparison_scores(p_round_id);
    ELSE                      PERFORM public.calculate_movda_elo_scores_for_round(p_round_id, p_seed);
  END CASE;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.calculate_movda_scores_for_round(bigint, double precision)
  FROM PUBLIC, anon, authenticated;

-- 4) 30-minute recompute for active rounds with new votes -------------------
CREATE OR REPLACE FUNCTION public.recompute_active_round_scores()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT rd.id
    FROM rounds rd
    JOIN cycles c ON c.id = rd.cycle_id
    JOIN chats ch ON ch.id = c.chat_id
    WHERE rd.phase = 'rating'
      AND rd.completed_at IS NULL
      AND ch.rating_mode = 'matches'
      AND EXISTS (SELECT 1 FROM pairwise_comparisons pc WHERE pc.round_id = rd.id)
      -- only if there are new votes since the last score computation
      AND COALESCE((SELECT max(pc.created_at) FROM pairwise_comparisons pc WHERE pc.round_id = rd.id), 'epoch'::timestamptz)
        > COALESCE((SELECT max(pgs.last_updated) FROM proposition_global_scores pgs WHERE pgs.round_id = rd.id), 'epoch'::timestamptz)
  LOOP
    BEGIN
      PERFORM public.calculate_movda_scores_for_round(r.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'recompute_active_round_scores: round % failed: %', r.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- Schedule the 30-min recompute (idempotent; guarded so a pg_cron-less local
-- DB can still load the functions). The winner-at-seal ALSO recomputes via the
-- dispatcher, so this cron only keeps the LIVE display fresh between seals.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'recompute-round-scores') THEN
      PERFORM cron.unschedule('recompute-round-scores');
    END IF;
    PERFORM cron.schedule('recompute-round-scores', '*/30 * * * *',
                          'SELECT public.recompute_active_round_scores()');
  END IF;
END $$;

COMMENT ON FUNCTION public.score_bradley_terry(bigint) IS
  'Bradley-Terry (MM fit) scoring strategy → proposition_global_scores (field win prob *100). See 20260715020000.';
COMMENT ON FUNCTION public.calculate_movda_scores_for_round(bigint, double precision) IS
  'Scoring dispatcher: resolves chats.scoring_algorithm (bradley_terry|head_to_head|elo_movda) and delegates. Both seal paths call this; winner = MAX(global_score).';
