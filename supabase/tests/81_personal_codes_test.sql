-- Tests for personal codes feature
-- Tests for migration 20260307100000_add_personal_codes.sql
--
-- Covers:
-- A. generate_personal_code() - host can generate, non-host cannot
-- B. list_personal_codes() - host can list, non-host cannot
-- C. redeem_personal_code() - valid redemption, participant creation, already-used rejection
-- D. revoke_personal_code() - host can revoke unused, cannot revoke used, non-host blocked
-- E. get_chat_by_code() integration with personal codes
-- F. CHECK constraint: cannot have both used_at and revoked_at

BEGIN;
SELECT plan(13);

-- =============================================================================
-- SETUP: Create auth users and a personal_code chat
-- =============================================================================

DO $$
DECLARE
    v_host_id UUID := 'aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_joiner_id UUID := 'bbbb2222-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    v_chat_id BIGINT;
    v_host_participant_id BIGINT;
BEGIN
    -- Create auth users
    INSERT INTO auth.users (id) VALUES (v_host_id);
    INSERT INTO auth.users (id) VALUES (v_joiner_id);

    -- Create personal_code chat
    INSERT INTO public.chats (
        name, initial_message, creator_id,
        access_method, start_mode,
        proposing_duration_seconds, rating_duration_seconds,
        enable_ai_participant, proposing_minimum,
        proposing_threshold_count, proposing_threshold_percent
    ) VALUES (
        'Personal Code Chat', 'Test question', v_host_id,
        'personal_code', 'manual',
        300, 300,
        FALSE, 10,
        NULL, NULL
    ) RETURNING id INTO v_chat_id;

    -- Host is an active participant
    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_host_id, 'Host', TRUE, 'active')
    RETURNING id INTO v_host_participant_id;

    -- Store IDs for later tests
    PERFORM set_config('test.host_id', v_host_id::TEXT, TRUE);
    PERFORM set_config('test.joiner_id', v_joiner_id::TEXT, TRUE);
    PERFORM set_config('test.chat_id', v_chat_id::TEXT, TRUE);
    PERFORM set_config('test.host_participant_id', v_host_participant_id::TEXT, TRUE);
END $$;

-- =============================================================================
-- TEST 1: generate_personal_code - host can generate a code
-- =============================================================================

DO $$
DECLARE
    v_code TEXT;
    v_code_id BIGINT;
BEGIN
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', current_setting('test.host_id'))::TEXT, TRUE);

    SELECT pc.code, pc.id INTO v_code, v_code_id
    FROM generate_personal_code(current_setting('test.chat_id')::BIGINT) pc;

    RESET ROLE;

    -- Store for later tests
    PERFORM set_config('test.code1', v_code, TRUE);
    PERFORM set_config('test.code1_id', v_code_id::TEXT, TRUE);
END $$;

SELECT ok(
    length(current_setting('test.code1')) = 6,
    'Test 1: Host can generate a 6-character personal code'
);

-- =============================================================================
-- TEST 2: generate_personal_code - non-host cannot generate
-- =============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner_id'))::TEXT, TRUE);

SELECT throws_ok(
    'SELECT * FROM generate_personal_code(' || current_setting('test.chat_id') || ')',
    NULL,
    'Test 2: Non-host cannot generate personal code'
);

RESET ROLE;

-- =============================================================================
-- TEST 3: list_personal_codes - host can list codes
-- =============================================================================

DO $$
DECLARE
    v_count INT;
BEGIN
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', current_setting('test.host_id'))::TEXT, TRUE);

    SELECT COUNT(*) INTO v_count
    FROM list_personal_codes(current_setting('test.chat_id')::BIGINT);

    RESET ROLE;

    PERFORM set_config('test.code_count', v_count::TEXT, TRUE);
END $$;

SELECT is(
    current_setting('test.code_count')::INT,
    1,
    'Test 3: Host can list personal codes (1 code exists)'
);

-- =============================================================================
-- TEST 4: list_personal_codes - non-host cannot list
-- =============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner_id'))::TEXT, TRUE);

SELECT throws_ok(
    'SELECT * FROM list_personal_codes(' || current_setting('test.chat_id') || ')',
    NULL,
    'Test 4: Non-host cannot list personal codes'
);

RESET ROLE;

-- =============================================================================
-- TEST 5: redeem_personal_code - joiner can redeem a valid code
-- =============================================================================

DO $$
DECLARE
    v_result RECORD;
BEGIN
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', current_setting('test.joiner_id'))::TEXT, TRUE);

    SELECT * INTO v_result
    FROM redeem_personal_code(current_setting('test.code1'), 'Joiner');

    RESET ROLE;

    PERFORM set_config('test.joiner_participant_id', v_result.participant_id::TEXT, TRUE);
    PERFORM set_config('test.redeemed_chat_id', v_result.chat_id::TEXT, TRUE);
END $$;

SELECT is(
    current_setting('test.redeemed_chat_id')::BIGINT,
    current_setting('test.chat_id')::BIGINT,
    'Test 5: Joiner can redeem a valid personal code and gets correct chat_id'
);

-- =============================================================================
-- TEST 6: redeem_personal_code - creates participant with status 'active'
-- =============================================================================

SELECT is(
    (SELECT status FROM public.participants
     WHERE id = current_setting('test.joiner_participant_id')::BIGINT),
    'active',
    'Test 6: Redeemed code creates participant with status active'
);

-- =============================================================================
-- TEST 7: redeem_personal_code - already-used code fails
-- =============================================================================

-- Generate a third user to try redeeming the already-used code
DO $$
DECLARE
    v_third_id UUID := 'cccc3333-cccc-cccc-cccc-cccccccccccc';
BEGIN
    INSERT INTO auth.users (id) VALUES (v_third_id);
    PERFORM set_config('test.third_id', v_third_id::TEXT, TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.third_id'))::TEXT, TRUE);

SELECT throws_ok(
    'SELECT * FROM redeem_personal_code(''' || current_setting('test.code1') || ''', ''Third User'')',
    NULL,
    'Test 7: Already-used personal code cannot be redeemed again'
);

RESET ROLE;

-- =============================================================================
-- TEST 8: revoke_personal_code - host can revoke an unused code
-- =============================================================================

-- First generate a new code to revoke
DO $$
DECLARE
    v_code TEXT;
    v_code_id BIGINT;
BEGIN
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', current_setting('test.host_id'))::TEXT, TRUE);

    SELECT pc.code, pc.id INTO v_code, v_code_id
    FROM generate_personal_code(current_setting('test.chat_id')::BIGINT) pc;

    RESET ROLE;

    PERFORM set_config('test.code2', v_code, TRUE);
    PERFORM set_config('test.code2_id', v_code_id::TEXT, TRUE);
END $$;

-- Now revoke it as host
DO $$
BEGIN
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', current_setting('test.host_id'))::TEXT, TRUE);

    PERFORM revoke_personal_code(current_setting('test.code2_id')::BIGINT);

    RESET ROLE;
END $$;

SELECT ok(
    (SELECT revoked_at IS NOT NULL FROM public.personal_codes
     WHERE id = current_setting('test.code2_id')::BIGINT),
    'Test 8: Host can revoke an unused personal code'
);

-- =============================================================================
-- TEST 9: revoke_personal_code - cannot revoke already-used code
-- =============================================================================

-- code1 was already used by joiner
SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.host_id'))::TEXT, TRUE);

SELECT throws_ok(
    'SELECT revoke_personal_code(' || current_setting('test.code1_id') || ')',
    NULL,
    'Test 9: Cannot revoke an already-used personal code'
);

RESET ROLE;

-- =============================================================================
-- TEST 10: revoke_personal_code - non-host cannot revoke
-- =============================================================================

-- Generate another code first, then try to revoke as non-host
DO $$
DECLARE
    v_code TEXT;
    v_code_id BIGINT;
BEGIN
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', current_setting('test.host_id'))::TEXT, TRUE);

    SELECT pc.code, pc.id INTO v_code, v_code_id
    FROM generate_personal_code(current_setting('test.chat_id')::BIGINT) pc;

    RESET ROLE;

    PERFORM set_config('test.code3', v_code, TRUE);
    PERFORM set_config('test.code3_id', v_code_id::TEXT, TRUE);
END $$;

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner_id'))::TEXT, TRUE);

SELECT throws_ok(
    'SELECT revoke_personal_code(' || current_setting('test.code3_id') || ')',
    NULL,
    'Test 10: Non-host cannot revoke a personal code'
);

RESET ROLE;

-- =============================================================================
-- TEST 11: get_chat_by_code finds chat via personal code
-- =============================================================================

-- code3 is unused and not revoked, so get_chat_by_code should find the chat
SELECT is(
    (SELECT c.id FROM get_chat_by_code(current_setting('test.code3')) c LIMIT 1),
    current_setting('test.chat_id')::BIGINT,
    'Test 11: get_chat_by_code finds chat via an active personal code'
);

-- =============================================================================
-- TEST 12: redeem_personal_code - revoked code fails
-- =============================================================================

-- code2 was revoked in test 8
SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.third_id'))::TEXT, TRUE);

SELECT throws_ok(
    'SELECT * FROM redeem_personal_code(''' || current_setting('test.code2') || ''', ''Third User'')',
    NULL,
    'Test 12: Revoked personal code cannot be redeemed'
);

RESET ROLE;

-- =============================================================================
-- TEST 13: CHECK constraint - cannot have both used_at and revoked_at
-- =============================================================================

SELECT throws_ok(
    'UPDATE public.personal_codes SET used_at = now(), used_by = ''' || current_setting('test.joiner_id') || '''::UUID, revoked_at = now() WHERE id = ' || current_setting('test.code3_id'),
    NULL,
    'Test 13: CHECK constraint prevents both used_at and revoked_at being set'
);

-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
