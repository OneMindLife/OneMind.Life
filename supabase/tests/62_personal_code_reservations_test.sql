-- Tests for personal code reservation system
BEGIN;
SELECT plan(13);

-- ============================================================================
-- TEST DATA SETUP
-- ============================================================================

DO $$
DECLARE
    v_host_id UUID;
    v_joiner1_id UUID;
    v_joiner2_id UUID;
    v_chat_id INT;
    v_code TEXT;
BEGIN
    -- Create users
    v_host_id := extensions.uuid_generate_v4();
    v_joiner1_id := extensions.uuid_generate_v4();
    v_joiner2_id := extensions.uuid_generate_v4();
    INSERT INTO auth.users (id, role) VALUES (v_host_id, 'authenticated');
    INSERT INTO auth.users (id, role) VALUES (v_joiner1_id, 'authenticated');
    INSERT INTO auth.users (id, role) VALUES (v_joiner2_id, 'authenticated');

    -- Create personal_code chat
    INSERT INTO public.chats (name, initial_message, creator_id, start_mode, access_method)
    VALUES ('Reservation Test', 'Test?', v_host_id, 'auto', 'personal_code')
    RETURNING id INTO v_chat_id;

    INSERT INTO public.participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_host_id, 'Host', true, 'active');

    -- Generate a code as host
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_host_id)::text, true);
    SELECT code INTO v_code FROM generate_personal_code(v_chat_id);
    RESET ROLE;

    PERFORM set_config('test.chat_id', v_chat_id::TEXT, true);
    PERFORM set_config('test.code', v_code, true);
    PERFORM set_config('test.host_id', v_host_id::TEXT, true);
    PERFORM set_config('test.joiner1_id', v_joiner1_id::TEXT, true);
    PERFORM set_config('test.joiner2_id', v_joiner2_id::TEXT, true);
END $$;

-- ============================================================================
-- SCHEMA TESTS
-- ============================================================================

SELECT has_column('personal_codes', 'reserved_by',
    'personal_codes should have reserved_by column');

SELECT has_column('personal_codes', 'reserved_at',
    'personal_codes should have reserved_at column');

-- ============================================================================
-- RESERVE: sets reserved_by and reserved_at
-- ============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner1_id'))::text, true);

SELECT lives_ok(
    format('SELECT reserve_personal_code(%L)', current_setting('test.code')),
    'Joiner1 can reserve the code'
);

RESET ROLE;

SELECT is(
    (SELECT reserved_by::TEXT FROM personal_codes WHERE code = current_setting('test.code')::CHAR(6)),
    current_setting('test.joiner1_id'),
    'reserved_by should be joiner1'
);

SELECT isnt(
    (SELECT reserved_at FROM personal_codes WHERE code = current_setting('test.code')::CHAR(6)),
    NULL::TIMESTAMPTZ,
    'reserved_at should be set'
);

-- ============================================================================
-- RESERVE: idempotent for same user
-- ============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner1_id'))::text, true);

SELECT lives_ok(
    format('SELECT reserve_personal_code(%L)', current_setting('test.code')),
    'Joiner1 can re-reserve (idempotent)'
);

RESET ROLE;

-- ============================================================================
-- RESERVE: blocked for different user (not expired)
-- ============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner2_id'))::text, true);

-- reserve_personal_code silently returns if code not available
SELECT lives_ok(
    format('SELECT reserve_personal_code(%L)', current_setting('test.code')),
    'Joiner2 reserve does not error (silently fails)'
);

RESET ROLE;

-- Verify still reserved by joiner1
SELECT is(
    (SELECT reserved_by::TEXT FROM personal_codes WHERE code = current_setting('test.code')::CHAR(6)),
    current_setting('test.joiner1_id'),
    'Code still reserved by joiner1 (not stolen by joiner2)'
);

-- ============================================================================
-- GET_CHAT_BY_CODE: hides reserved code from other users
-- ============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner2_id'))::text, true);

SELECT is(
    (SELECT count(*)::INT FROM get_chat_by_code(current_setting('test.code'))),
    0,
    'Joiner2 cannot see chat via reserved code'
);

-- But joiner1 can still see it
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner1_id'))::text, true);

SELECT is(
    (SELECT count(*)::INT FROM get_chat_by_code(current_setting('test.code'))),
    1,
    'Joiner1 can still see chat via their reserved code'
);

RESET ROLE;

-- ============================================================================
-- REDEEM: works for the user who reserved
-- ============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims',
    json_build_object('sub', current_setting('test.joiner1_id'))::text, true);

SELECT lives_ok(
    format('SELECT * FROM redeem_personal_code(%L, %L)',
        current_setting('test.code'), 'Joiner 1'),
    'Joiner1 can redeem their reserved code'
);

RESET ROLE;

-- Verify used and reservation cleared
SELECT isnt(
    (SELECT used_at FROM personal_codes WHERE code = current_setting('test.code')::CHAR(6)),
    NULL::TIMESTAMPTZ,
    'Code should be marked as used after redeem'
);

SELECT is(
    (SELECT reserved_by FROM personal_codes WHERE code = current_setting('test.code')::CHAR(6)),
    NULL::UUID,
    'Reservation cleared after redeem'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

DELETE FROM participants WHERE chat_id = current_setting('test.chat_id')::INT;
DELETE FROM personal_codes WHERE chat_id = current_setting('test.chat_id')::INT;
DELETE FROM chats WHERE id = current_setting('test.chat_id')::INT;

SELECT * FROM finish();
ROLLBACK;
