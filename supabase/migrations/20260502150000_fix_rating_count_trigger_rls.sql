-- =============================================================================
-- Fix: sync_proposition_rating_count was silently dropping every UPDATE.
-- =============================================================================
-- The trigger function shipped in 20260502120000 ran as the calling role
-- (authenticated). RLS is enabled on propositions with policies for
-- SELECT/INSERT/DELETE but NOT UPDATE — so the trigger's
-- `UPDATE propositions SET rating_count = ...` was silently filtered to
-- zero rows by default-deny RLS. No error, no warning; the function
-- just no-op'd.
--
-- Effects in production from L1 ship (commit e4b45bf) until this fix:
--   1. propositions.rating_count never moved past 0 for new ratings.
--   2. The new LRP query degenerated to ORDER BY 0 + random() — fast for
--      the wrong reason: the JOIN was gone (good) but the ordering signal
--      was always zero (bad).
--
-- Why pgtap missed it: pgtap runs as the postgres superuser, which
-- bypasses RLS. The trigger UPDATE worked there. We caught it by
-- spot-checking lockstep after a 50-bot cascade and seeing 7 of 21
-- propositions with rating_count=0 vs 49 actual grid_rankings rows.
--
-- Fix: SECURITY DEFINER so the function runs as its owner (postgres,
-- which owns the table) and bypasses the missing UPDATE policy. The
-- trigger only ever does a single indexed UPDATE on propositions(id);
-- there is no user-controlled SQL inside, so DEFINER is safe.
--
-- 105_rating_count_denorm_test.sql gained a regression test that runs
-- the INSERT under SET ROLE authenticated with a JWT — it fails on the
-- old non-DEFINER trigger and passes on this one. Don't drop that test.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sync_proposition_rating_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
  RETURN NULL;
END;
$$;

-- Re-backfill: every proposition.rating_count gets its actual count of
-- grid_rankings. This is idempotent.
UPDATE public.propositions p
SET rating_count = sub.cnt
FROM (
  SELECT proposition_id, COUNT(*)::INT AS cnt
  FROM public.grid_rankings
  GROUP BY proposition_id
) sub
WHERE sub.proposition_id = p.id
  AND p.rating_count IS DISTINCT FROM sub.cnt;

-- Reset propositions where rating_count > 0 but no grid_rankings exist
-- (stranded counters from any partial recovery state).
UPDATE public.propositions p
SET rating_count = 0
WHERE p.rating_count > 0
  AND NOT EXISTS (
    SELECT 1 FROM public.grid_rankings gr WHERE gr.proposition_id = p.id
  );
