-- Vault-based Cron Helpers Tests
-- Tests for migration 20260207300000_vault_based_cron_urls.sql
--
-- Covers:
-- 1. Helper functions exist and have correct signatures
-- 2. get_edge_function_url() output format
-- 3. get_cron_headers() output structure
-- 4. All 3 cron jobs exist with correct schedules
-- 5. Cron jobs use vault-based helpers (no hardcoded URLs)
-- 6. Trigger functions use get_edge_function_url() (no hardcoded URLs)
-- 7. Function source code doesn't contain production project ref
--
-- NOTE: We cannot test vault INSERT/DELETE in pgtap because the test runner
-- lacks permission for _crypto_aead_det_noncegen. We verify behavior via
-- function source introspection and cron job command inspection instead.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(18);

-- =============================================================================
-- TEST GROUP 1: Helper functions exist
-- =============================================================================

SELECT has_function(
    'public',
    'get_edge_function_url',
    ARRAY['text'],
    'get_edge_function_url(text) function should exist'
);

SELECT has_function(
    'public',
    'get_cron_headers',
    ARRAY[]::text[],
    'get_cron_headers() function should exist'
);

-- =============================================================================
-- TEST GROUP 2: get_edge_function_url() output format
-- =============================================================================

SELECT matches(
    get_edge_function_url('process-timers'),
    '.*/functions/v1/process-timers$',
    'get_edge_function_url includes /functions/v1/ path and function name'
);

SELECT matches(
    get_edge_function_url('translate'),
    '.*/functions/v1/translate$',
    'get_edge_function_url works for translate function'
);

SELECT matches(
    get_edge_function_url('ai-proposer'),
    '.*/functions/v1/ai-proposer$',
    'get_edge_function_url works for ai-proposer function'
);

-- =============================================================================
-- TEST GROUP 3: get_cron_headers() output structure
-- =============================================================================

SELECT ok(
    (get_cron_headers()) ? 'Content-Type',
    'get_cron_headers() returns JSON with Content-Type key'
);

SELECT ok(
    (get_cron_headers()) ? 'X-Cron-Secret',
    'get_cron_headers() returns JSON with X-Cron-Secret key'
);

SELECT is(
    get_cron_headers()->>'Content-Type',
    'application/json',
    'get_cron_headers() Content-Type is application/json'
);

-- =============================================================================
-- TEST GROUP 4: Cron jobs exist with correct schedules
-- =============================================================================

SELECT is(
    (SELECT count(*)::int FROM cron.job
     WHERE jobname IN ('process-timers', 'process-auto-refills', 'cleanup-inactive-chats')),
    3,
    'All 3 cron jobs should be scheduled'
);

SELECT is(
    (SELECT schedule FROM cron.job WHERE jobname = 'process-timers'),
    '* * * * *',
    'process-timers runs every minute'
);

SELECT is(
    (SELECT schedule FROM cron.job WHERE jobname = 'process-auto-refills'),
    '* * * * *',
    'process-auto-refills runs every minute'
);

-- =============================================================================
-- TEST GROUP 5: Cron jobs use vault-based helpers (no hardcoded URLs)
-- =============================================================================

SELECT ok(
    (SELECT command FROM cron.job WHERE jobname = 'process-timers') LIKE '%get_edge_function_url%',
    'process-timers cron job uses get_edge_function_url()'
);

SELECT ok(
    (SELECT command FROM cron.job WHERE jobname = 'process-auto-refills') LIKE '%get_cron_headers%',
    'process-auto-refills cron job uses get_cron_headers()'
);

SELECT is(
    (SELECT count(*)::int FROM cron.job
     WHERE jobname IN ('process-timers', 'process-auto-refills', 'cleanup-inactive-chats')
       AND command LIKE '%supabase.co%'),
    0,
    'No cron jobs contain hardcoded supabase.co URLs'
);

-- =============================================================================
-- TEST GROUP 6: Trigger functions use get_edge_function_url() (no hardcoded URLs)
-- =============================================================================

SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_translate_chat') LIKE '%get_edge_function_url%',
    'trigger_translate_chat() uses get_edge_function_url()'
);

SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_translate_proposition') LIKE '%get_edge_function_url%',
    'trigger_translate_proposition() uses get_edge_function_url()'
);

SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_ai_proposer_on_proposing') LIKE '%get_edge_function_url%',
    'trigger_ai_proposer_on_proposing() uses get_edge_function_url()'
);

-- =============================================================================
-- TEST GROUP 7: No production project ref in current function source
-- =============================================================================

SELECT is(
    (SELECT count(*)::int FROM pg_proc
     WHERE proname IN ('trigger_translate_chat', 'trigger_translate_proposition', 'trigger_ai_proposer_on_proposing', 'get_edge_function_url')
       AND prosrc LIKE '%ccyuxrtrklgpkzcryzpj%'),
    0,
    'No trigger or helper functions contain hardcoded production project ref'
);

-- =============================================================================
-- DONE
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
