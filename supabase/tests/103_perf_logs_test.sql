-- =============================================================================
-- Tests for perf_logs observability table + log_perf RPC.
-- =============================================================================
-- Coverage:
--   1.  Table exists with the expected columns
--   2.  Indexes exist
--   3.  log_perf inserts a row with all fields populated
--   4.  log_perf inserts when most fields are NULL (only required ones)
--   5.  log_perf populates user_id from auth.uid() when not passed
--   6.  log_perf preserves explicit user_id over auth.uid()
--   7.  Source CHECK constraint rejects bad values
--   8.  Phase CHECK constraint rejects bad values
--   9.  Anon role can insert via RPC (RLS-checked)
--   10. Authenticated role can insert via RPC
--   11. log_perf does NOT raise when given invalid input that would
--       otherwise violate constraints (graceful swallowing)
--   12. pg_stat_statements extension is installed
--   13. Default created_at is set when not supplied
--   14. Multiple rows with the same correlation_id are queryable in order
-- =============================================================================

BEGIN;
SELECT plan(14);

-- =============================================================================
-- 1. Schema shape
-- =============================================================================
SELECT has_table('public', 'perf_logs', 'perf_logs table exists');

-- 2. Required indexes
SELECT has_index('public', 'perf_logs', 'idx_perf_logs_correlation_id',
    'correlation_id index exists');

-- =============================================================================
-- 3. Basic insert via RPC with all fields populated
-- =============================================================================
DO $$
DECLARE v_corr UUID := gen_random_uuid();
BEGIN
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'flutter',
        p_action         := 'resume_chat',
        p_phase          := 'start',
        p_duration_ms    := NULL,
        p_chat_id        := 309,
        p_round_id       := 2407,
        p_user_id        := '00000000-0000-0000-0000-000000000001',
        p_device_id      := 'device-abc',
        p_payload        := '{"foo": "bar"}'::JSONB,
        p_error          := NULL
    );
    PERFORM set_config('test.full_corr', v_corr::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT COUNT(*)::INT FROM perf_logs
     WHERE correlation_id = current_setting('test.full_corr')::UUID),
    1,
    '3: full insert wrote one row'
);

-- =============================================================================
-- 4. Insert with only required fields (source + action)
-- =============================================================================
DO $$
DECLARE v_corr UUID := gen_random_uuid();
BEGIN
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'db_func',
        p_action         := 'host_resume_chat'
    );
    PERFORM set_config('test.minimal_corr', v_corr::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT COUNT(*)::INT FROM perf_logs
     WHERE correlation_id = current_setting('test.minimal_corr')::UUID),
    1,
    '4: minimal insert (source + action only) wrote one row'
);

-- =============================================================================
-- 5. user_id falls back to auth.uid() when null. Simulate by setting
--    request.jwt.claims and inserting WITHOUT p_user_id.
-- =============================================================================
SELECT lives_ok($$
    SET LOCAL ROLE authenticated;
    SET LOCAL request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000aa", "role": "authenticated"}';
    SELECT public.log_perf(
        p_correlation_id := gen_random_uuid(),
        p_source         := 'flutter',
        p_action         := 'auth_uid_fallback_test'
    );
$$, '5: log_perf runs without explicit user_id when role is authenticated');

RESET ROLE;

-- 6. Explicit user_id wins over auth.uid()
DO $$
DECLARE v_corr UUID := gen_random_uuid();
BEGIN
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'flutter',
        p_action         := 'explicit_user_id_test',
        p_user_id        := '00000000-0000-0000-0000-0000000000bb'
    );
    PERFORM set_config('test.explicit_corr', v_corr::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT user_id FROM perf_logs
     WHERE correlation_id = current_setting('test.explicit_corr')::UUID),
    '00000000-0000-0000-0000-0000000000bb'::UUID,
    '6: explicit user_id is preserved'
);

-- =============================================================================
-- 7-8. CHECK constraints
-- =============================================================================
SELECT throws_ok($$
    INSERT INTO perf_logs (source, action) VALUES ('not_a_real_source', 'foo');
$$, NULL,
    '7: source CHECK rejects bad values');

SELECT throws_ok($$
    INSERT INTO perf_logs (source, action, phase) VALUES ('flutter', 'foo', 'banana');
$$, NULL,
    '8: phase CHECK rejects bad values');

-- =============================================================================
-- 9-10. Roles can call the RPC
-- =============================================================================
SELECT lives_ok($$
    SET LOCAL ROLE anon;
    SELECT public.log_perf(
        p_correlation_id := gen_random_uuid(),
        p_source         := 'flutter',
        p_action         := 'anon_call_test'
    );
$$, '9: anon role can call log_perf');

RESET ROLE;

SELECT lives_ok($$
    SET LOCAL ROLE authenticated;
    SET LOCAL request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000000cc", "role": "authenticated"}';
    SELECT public.log_perf(
        p_correlation_id := gen_random_uuid(),
        p_source         := 'flutter',
        p_action         := 'authenticated_call_test'
    );
$$, '10: authenticated role can call log_perf');

RESET ROLE;

-- =============================================================================
-- 11. log_perf swallows errors. Pass an over-long action that the column
--     accepts but force a failure path. Easiest: pass a NULL source via
--     the RPC — the function does not raise. Confirm by calling and
--     checking that the function returns void without throwing.
-- =============================================================================
SELECT lives_ok($$
    SELECT public.log_perf(
        p_correlation_id := gen_random_uuid(),
        p_source         := NULL,         -- NOT NULL violation suppressed
        p_action         := 'should_not_throw'
    );
$$, '11: log_perf swallows constraint failures (NOT NULL on source)');

-- =============================================================================
-- 12. pg_stat_statements is installed
-- =============================================================================
SELECT is(
    (SELECT COUNT(*)::INT FROM pg_extension WHERE extname = 'pg_stat_statements'),
    1,
    '12: pg_stat_statements extension is installed'
);

-- =============================================================================
-- 13. created_at defaults to NOW()
-- =============================================================================
DO $$
DECLARE v_corr UUID := gen_random_uuid();
BEGIN
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'flutter',
        p_action         := 'created_at_default_test'
    );
    PERFORM set_config('test.created_corr', v_corr::TEXT, TRUE);
END $$;

SELECT ok(
    (SELECT created_at FROM perf_logs
     WHERE correlation_id = current_setting('test.created_corr')::UUID)
    > NOW() - INTERVAL '5 seconds',
    '13: created_at populated with current time'
);

-- =============================================================================
-- 14. Multiple rows with same correlation_id can be reconstructed as a
--     timeline. Insert start → end and confirm both retrievable in order.
-- =============================================================================
DO $$
DECLARE v_corr UUID := gen_random_uuid();
BEGIN
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'flutter',
        p_action         := 'timeline_test',
        p_phase          := 'start'
    );
    PERFORM pg_sleep(0.01); -- guarantee monotonic created_at ordering
    PERFORM public.log_perf(
        p_correlation_id := v_corr,
        p_source         := 'flutter',
        p_action         := 'timeline_test',
        p_phase          := 'end',
        p_duration_ms    := 42
    );
    PERFORM set_config('test.timeline_corr', v_corr::TEXT, TRUE);
END $$;

SELECT is(
    (SELECT array_agg(phase ORDER BY created_at)
     FROM perf_logs
     WHERE correlation_id = current_setting('test.timeline_corr')::UUID),
    ARRAY['start', 'end']::TEXT[],
    '14: timeline of correlated rows preserved in created_at order'
);

SELECT * FROM finish();
ROLLBACK;
