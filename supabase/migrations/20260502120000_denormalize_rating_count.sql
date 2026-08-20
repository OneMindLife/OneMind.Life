-- =============================================================================
-- Lever 1: denormalize rating_count on propositions to kill the LRP cascade
-- =============================================================================
-- Stress runs (RAISE LOG instrumentation, see 20260502*_instrument_*) showed
-- get_least_rated_propositions slowing 60-100ms → 334-1492ms under 14-way
-- concurrency at 20-bot scale. The hot cost is the inline aggregate:
--
--     LEFT JOIN (
--       SELECT proposition_id, COUNT(*) AS cnt
--       FROM grid_rankings WHERE round_id = p_round_id
--       GROUP BY proposition_id
--     ) gr_count ON ...
--
-- which scans grid_rankings while it is being heavily INSERTed (the rating
-- cascade itself), with RLS planning per row. Each LRP caller redoes the
-- same aggregate from scratch.
--
-- This migration replaces the aggregate with a denormalized counter on
-- propositions, maintained by a row-level trigger on grid_rankings. The
-- LRP query then becomes a single index scan on propositions(round_id)
-- with no aggregate and no JOIN.
-- =============================================================================

ALTER TABLE public.propositions
  ADD COLUMN IF NOT EXISTS rating_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.propositions.rating_count IS
  'Number of grid_rankings rows that reference this proposition. Maintained '
  'by trigger sync_proposition_rating_count_trg on AFTER INSERT/DELETE of '
  'grid_rankings. Read by get_least_rated_propositions to avoid an inline '
  'aggregate that previously dominated rating-cascade latency.';

-- Backfill from current state.
UPDATE public.propositions p
SET rating_count = sub.cnt
FROM (
  SELECT proposition_id, COUNT(*)::INT AS cnt
  FROM public.grid_rankings
  GROUP BY proposition_id
) sub
WHERE sub.proposition_id = p.id
  AND p.rating_count IS DISTINCT FROM sub.cnt;

-- Trigger function: ±1 on each grid_rankings INSERT/DELETE.
-- Kept tiny — the only work per row is one indexed UPDATE.
CREATE OR REPLACE FUNCTION public.sync_proposition_rating_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.propositions
    SET rating_count = rating_count + 1
    WHERE id = NEW.proposition_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.propositions
    SET rating_count = GREATEST(rating_count - 1, 0)
    WHERE id = OLD.proposition_id;
  END IF;
  RETURN NULL; -- AFTER trigger return value is ignored
END;
$$;

DROP TRIGGER IF EXISTS sync_proposition_rating_count_trg ON public.grid_rankings;
CREATE TRIGGER sync_proposition_rating_count_trg
AFTER INSERT OR DELETE ON public.grid_rankings
FOR EACH ROW
EXECUTE FUNCTION public.sync_proposition_rating_count();

-- Rewrite LRP to read the denormalized counter — no JOIN, no GROUP BY.
-- LANGUAGE plpgsql VOLATILE so the LRP_PROBE RAISE LOGs from the
-- instrumentation migration keep firing for comparison.
CREATE OR REPLACE FUNCTION public.get_least_rated_propositions(
    p_round_id BIGINT,
    p_participant_id BIGINT,
    p_count INT DEFAULT 2,
    p_exclude_ids BIGINT[] DEFAULT '{}'
)
RETURNS TABLE (
    id BIGINT, round_id BIGINT, participant_id BIGINT, content TEXT,
    carried_from_id BIGINT, created_at TIMESTAMPTZ, rating_count BIGINT
)
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  v_t0 TIMESTAMPTZ := clock_timestamp();
  v_t1 TIMESTAMPTZ;
  v_pid INT := pg_backend_pid();
BEGIN
  RAISE LOG 'LRP_PROBE pid=% round=% stage=enter ms=0', v_pid, p_round_id;

  RETURN QUERY
    SELECT p.id, p.round_id, p.participant_id, p.content, p.carried_from_id,
           p.created_at, p.rating_count::BIGINT
    FROM public.propositions p
    WHERE p.round_id = p_round_id
      AND (p.participant_id IS NULL OR p.participant_id != p_participant_id)
      AND NOT (p.id = ANY(p_exclude_ids))
    ORDER BY p.rating_count ASC, random()
    LIMIT p_count;

  v_t1 := clock_timestamp();
  RAISE LOG 'LRP_PROBE pid=% round=% stage=done ms=%',
    v_pid, p_round_id,
    (EXTRACT(EPOCH FROM (v_t1 - v_t0)) * 1000)::INT;
END;
$$;
