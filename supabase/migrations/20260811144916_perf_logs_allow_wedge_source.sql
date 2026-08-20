-- perf_logs.source predates the web client: it allowed only flutter/db_func/
-- edge_function. The wedge (the actual product since the 2026-07 pivot) now
-- reports the room's cold-start chain, so admit 'wedge'.
--
-- The phase constraint (start|end|error) is deliberate and UNCHANGED — wedge
-- rows use phase='end' (or 'error'), put the step name in `action`, and carry
-- the flow name in payload->>'flow'.
ALTER TABLE public.perf_logs DROP CONSTRAINT IF EXISTS perf_logs_source_check;
ALTER TABLE public.perf_logs ADD CONSTRAINT perf_logs_source_check
  CHECK (source = ANY (ARRAY['flutter'::text, 'db_func'::text, 'edge_function'::text, 'wedge'::text]));
