-- Persona API Keys Tests
-- Tests for migration: 20260210000000_register_persona_api_keys.sql
--
-- Covers:
-- 1. All 5 personas registered in agent_api_keys
-- 2. Vault secrets exist for each persona
-- 3. get_persona_api_keys() returns correct data
-- 4. API keys validate via validate_agent_api_key()
-- 5. Security: get_persona_api_keys() not callable by anon/authenticated/public
BEGIN;
SET search_path TO public, extensions;
SELECT plan(14);

-- =============================================================================
-- TEST GROUP 1: All 5 personas have entries in agent_api_keys
-- =============================================================================

SELECT is(
    (SELECT count(*)::int FROM agent_api_keys
     WHERE agent_name IN ('the_executor', 'the_demand_detector', 'the_clock', 'the_compounder', 'the_breaker')),
    5,
    '5 persona API keys registered in agent_api_keys'
);

SELECT ok(
    EXISTS (SELECT 1 FROM agent_api_keys WHERE agent_name = 'the_executor'),
    'the_executor has an API key'
);

SELECT ok(
    EXISTS (SELECT 1 FROM agent_api_keys WHERE agent_name = 'the_demand_detector'),
    'the_demand_detector has an API key'
);

SELECT ok(
    EXISTS (SELECT 1 FROM agent_api_keys WHERE agent_name = 'the_clock'),
    'the_clock has an API key'
);

SELECT ok(
    EXISTS (SELECT 1 FROM agent_api_keys WHERE agent_name = 'the_compounder'),
    'the_compounder has an API key'
);

SELECT ok(
    EXISTS (SELECT 1 FROM agent_api_keys WHERE agent_name = 'the_breaker'),
    'the_breaker has an API key'
);

-- =============================================================================
-- TEST GROUP 2: Persona user_ids match between agent_personas and agent_api_keys
-- =============================================================================

SELECT is(
    (SELECT count(*)::int FROM agent_personas ap
     JOIN agent_api_keys ak ON ak.agent_name = ap.name AND ak.user_id = ap.user_id
     WHERE ap.is_active = true),
    5,
    'All 5 persona user_ids match between agent_personas and agent_api_keys'
);

-- =============================================================================
-- TEST GROUP 3: get_persona_api_keys() function exists and returns data
-- =============================================================================

SELECT has_function('get_persona_api_keys', 'get_persona_api_keys() function exists');

SELECT is(
    (SELECT count(*)::int FROM get_persona_api_keys()),
    5,
    'get_persona_api_keys() returns 5 rows'
);

-- Verify all returned keys start with onemind_sk_ prefix
SELECT is(
    (SELECT count(*)::int FROM get_persona_api_keys() WHERE api_key LIKE 'onemind_sk_%'),
    5,
    'All persona API keys have onemind_sk_ prefix'
);

-- =============================================================================
-- TEST GROUP 4: API keys validate correctly
-- =============================================================================

SELECT ok(
    (SELECT is_valid FROM validate_agent_api_key(
        (SELECT api_key FROM get_persona_api_keys() WHERE persona_name = 'the_executor')
    )),
    'the_executor API key validates successfully'
);

-- =============================================================================
-- TEST GROUP 5: Security — function not callable by anon/authenticated/public
-- =============================================================================

SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
        WHERE routine_name = 'get_persona_api_keys'
          AND grantee = 'anon'
          AND privilege_type = 'EXECUTE'
    ),
    'get_persona_api_keys() not executable by anon'
);

SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
        WHERE routine_name = 'get_persona_api_keys'
          AND grantee = 'authenticated'
          AND privilege_type = 'EXECUTE'
    ),
    'get_persona_api_keys() not executable by authenticated'
);

SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
        WHERE routine_name = 'get_persona_api_keys'
          AND grantee IN ('public', 'PUBLIC')
          AND privilege_type = 'EXECUTE'
    ),
    'get_persona_api_keys() not executable by public'
);

SELECT * FROM finish();
ROLLBACK;
