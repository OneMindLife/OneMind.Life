-- Agent Personas & Orchestrator Tests
-- Tests for migrations:
--   20260209000000_add_agent_personas.sql
--   20260209010000_add_orchestrator_trigger.sql
--   20260210100000_add_advocate_persona.sql
--   20260228000000_genericize_agent_personas.sql
--
-- Covers:
-- 1. agent_personas table schema and seed data
-- 2. Pseudo-users created in auth.users
-- 3. join_personas_to_chat() function behavior
-- 4. Orchestrator trigger function and trigger exist
-- 5. Trigger function source introspection (uses vault helpers)
-- 6. Security: REVOKE checks on functions and table
-- 7. Trigger fires on proposing AND rating phase changes
-- 8. Generic display names and empty system_prompts (dynamic persona generation)
--
-- NOTE: Cannot test actual pg_net calls or edge function invocations.
-- We verify via source introspection and data integrity.
BEGIN;
SET search_path TO public, extensions;
SELECT plan(38);

-- =============================================================================
-- TEST GROUP 1: agent_personas table exists with correct schema
-- =============================================================================

SELECT has_table('public', 'agent_personas', 'agent_personas table exists');

SELECT has_column('agent_personas', 'id', 'agent_personas has id column');
SELECT has_column('agent_personas', 'name', 'agent_personas has name column');
SELECT has_column('agent_personas', 'display_name', 'agent_personas has display_name column');
SELECT has_column('agent_personas', 'system_prompt', 'agent_personas has system_prompt column');
SELECT has_column('agent_personas', 'user_id', 'agent_personas has user_id column');
SELECT has_column('agent_personas', 'is_active', 'agent_personas has is_active column');
SELECT has_column('agent_personas', 'created_at', 'agent_personas has created_at column');

-- =============================================================================
-- TEST GROUP 2: Seed data — 6 personas exist with correct names
-- =============================================================================

SELECT is(
    (SELECT count(*)::int FROM agent_personas),
    6,
    '6 agent personas are seeded'
);

SELECT ok(
    EXISTS (SELECT 1 FROM agent_personas WHERE name = 'the_executor'),
    'the_executor persona exists'
);
SELECT ok(
    EXISTS (SELECT 1 FROM agent_personas WHERE name = 'the_demand_detector'),
    'the_demand_detector persona exists'
);
SELECT ok(
    EXISTS (SELECT 1 FROM agent_personas WHERE name = 'the_clock'),
    'the_clock persona exists'
);
SELECT ok(
    EXISTS (SELECT 1 FROM agent_personas WHERE name = 'the_compounder'),
    'the_compounder persona exists'
);
SELECT ok(
    EXISTS (SELECT 1 FROM agent_personas WHERE name = 'the_breaker'),
    'the_breaker persona exists'
);
SELECT ok(
    EXISTS (SELECT 1 FROM agent_personas WHERE name = 'the_advocate'),
    'the_advocate persona exists'
);

-- =============================================================================
-- TEST GROUP 3: Pseudo-users exist in auth.users with correct metadata
-- =============================================================================

SELECT is(
    (SELECT count(*)::int FROM auth.users
     WHERE raw_user_meta_data->>'is_agent' = 'true'),
    6,
    '6 agent pseudo-users exist in auth.users'
);

SELECT ok(
    (SELECT raw_user_meta_data->>'persona_name' FROM auth.users
     WHERE id = (SELECT user_id FROM agent_personas WHERE name = 'the_executor'))
    = 'the_executor',
    'Executor pseudo-user has matching persona_name in metadata'
);

-- All personas link to valid auth.users
SELECT is(
    (SELECT count(*)::int FROM agent_personas ap
     JOIN auth.users u ON u.id = ap.user_id),
    6,
    'All 6 personas link to valid auth.users entries'
);

-- =============================================================================
-- TEST GROUP 4: join_personas_to_chat() function
-- =============================================================================

SELECT has_function(
    'public',
    'join_personas_to_chat',
    ARRAY['bigint', 'integer'],
    'join_personas_to_chat(bigint, integer) function exists'
);

-- Create a test chat and join personas
INSERT INTO chats (name, access_method, start_mode, enable_ai_participant, proposing_duration_seconds, rating_duration_seconds, proposing_minimum)
VALUES ('Agent Persona Test Chat', 'code', 'manual', FALSE, 3600, 3600, 10)
RETURNING id AS test_chat_id \gset

-- Join personas
SELECT count(*)::int AS joined_count
FROM join_personas_to_chat(:test_chat_id)
WHERE status = 'joined' \gset

SELECT is(
    :joined_count,
    6,
    'join_personas_to_chat() joins 6 personas to the chat'
);

-- Verify participants were created correctly
SELECT is(
    (SELECT count(*)::int FROM participants
     WHERE chat_id = :test_chat_id
       AND user_id IN (SELECT user_id FROM agent_personas)),
    6,
    '6 participant rows created for agent personas'
);

-- Verify display names match (now generic after genericize migration)
SELECT ok(
    EXISTS (SELECT 1 FROM participants p
            JOIN agent_personas ap ON ap.user_id = p.user_id
            WHERE p.chat_id = :test_chat_id
              AND p.display_name = ap.display_name
              AND ap.name = 'the_executor'),
    'Executor participant has matching display_name from agent_personas'
);

-- Test idempotency — joining again should skip
SELECT count(*)::int AS already_count
FROM join_personas_to_chat(:test_chat_id)
WHERE status = 'already_joined' \gset

SELECT is(
    :already_count,
    6,
    'join_personas_to_chat() is idempotent — returns already_joined on second call'
);

-- Verify no duplicates
SELECT is(
    (SELECT count(*)::int FROM participants
     WHERE chat_id = :test_chat_id
       AND user_id IN (SELECT user_id FROM agent_personas)),
    6,
    'No duplicate participants after second join call'
);

-- =============================================================================
-- TEST GROUP 5: Orchestrator trigger function and trigger exist
-- =============================================================================

SELECT has_function(
    'public',
    'trigger_agent_orchestrator',
    'trigger_agent_orchestrator() function exists'
);

SELECT has_trigger(
    'rounds',
    'agent_orchestrator_on_phase_change',
    'agent_orchestrator_on_phase_change trigger exists on rounds table'
);

-- =============================================================================
-- TEST GROUP 6: Trigger function source introspection
-- =============================================================================

SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_agent_orchestrator')
    LIKE '%get_edge_function_url%',
    'trigger_agent_orchestrator() uses get_edge_function_url()'
);

SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_agent_orchestrator')
    LIKE '%agent-orchestrator%',
    'trigger_agent_orchestrator() references agent-orchestrator edge function'
);

SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_agent_orchestrator')
    LIKE '%agent_personas%',
    'trigger_agent_orchestrator() checks agent_personas table'
);

SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_agent_orchestrator')
    LIKE '%proposing%' AND
    (SELECT prosrc FROM pg_proc WHERE proname = 'trigger_agent_orchestrator')
    LIKE '%rating%',
    'trigger_agent_orchestrator() handles both proposing and rating phases'
);

-- =============================================================================
-- TEST GROUP 7: Security — REVOKE checks
-- =============================================================================

-- agent_personas table should NOT be accessible by anon or authenticated
SELECT is(
    (SELECT count(*)::int FROM information_schema.role_table_grants
     WHERE table_name = 'agent_personas'
       AND grantee IN ('anon', 'authenticated')),
    0,
    'agent_personas table has no grants to anon or authenticated'
);

-- join_personas_to_chat should not be executable by anon or authenticated
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
        WHERE routine_name = 'join_personas_to_chat'
          AND grantee IN ('anon', 'authenticated', 'public')
          AND privilege_type = 'EXECUTE'
    ),
    'join_personas_to_chat() is not executable by anon/authenticated/public'
);

-- trigger_agent_orchestrator should not be executable by anon or authenticated
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM information_schema.routine_privileges
        WHERE routine_name = 'trigger_agent_orchestrator'
          AND grantee IN ('anon', 'authenticated', 'public')
          AND privilege_type = 'EXECUTE'
    ),
    'trigger_agent_orchestrator() is not executable by anon/authenticated/public'
);

-- =============================================================================
-- TEST GROUP 8: Generic display names and empty system_prompts
-- =============================================================================

-- Display names should be generic placeholders (not startup-specific)
SELECT is(
    (SELECT display_name FROM agent_personas WHERE name = 'the_executor'),
    'Agent 1',
    'the_executor has generic display_name "Agent 1"'
);

SELECT is(
    (SELECT display_name FROM agent_personas WHERE name = 'the_advocate'),
    'Agent 6',
    'the_advocate has generic display_name "Agent 6"'
);

-- All system_prompts should be empty (forces dynamic generation / DEFAULT_ARCHETYPES)
SELECT is(
    (SELECT count(*)::int FROM agent_personas WHERE system_prompt = '' AND is_active = true),
    6,
    'All 6 active personas have empty system_prompt'
);

-- =============================================================================
-- TEST GROUP 9: Trigger fires correctly on phase transitions
-- =============================================================================

-- Create a cycle and round for the test chat (which has personas joined)
INSERT INTO cycles (chat_id)
VALUES (:test_chat_id)
RETURNING id AS test_cycle_id \gset

-- Test: round can be created in proposing phase (trigger runs, checks for agents, tries pg_net)
-- The trigger has EXCEPTION WHEN OTHERS handler so it won't block the insert
-- even if pg_net fails in test environment
INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
VALUES (:test_cycle_id, 1, 'proposing', NOW())
RETURNING id AS test_round_id \gset

SELECT ok(
    (SELECT id FROM rounds WHERE id = :test_round_id) IS NOT NULL,
    'Round created in proposing phase with agent personas (trigger does not block)'
);

-- Test: round can transition to rating phase (trigger fires for rating too)
UPDATE rounds
SET phase = 'rating', phase_started_at = NOW()
WHERE id = :test_round_id;

SELECT is(
    (SELECT phase FROM rounds WHERE id = :test_round_id),
    'rating',
    'Round transitions to rating phase with agent personas (trigger does not block)'
);

-- =============================================================================
-- DONE
-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
