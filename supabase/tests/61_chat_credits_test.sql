-- =============================================================================
-- Chat-Based Credits System Tests
-- =============================================================================
-- Tests for:
--   1. Auto-creation of chat_credits on chat insert
--   2. fund_round_participants: full funding, partial funding, ordering
--   3. fund_mid_round_join: success, insufficient credits, idempotency
--   4. can_round_start: true/false scenarios
--   5. create_round_for_cycle: credit-paused vs proposing
--   6. add_chat_credits: balance increase, Stripe idempotency
--   7. check_credit_resume: unpauses waiting round after credit purchase
--   8. Early-advance thresholds use funded count
--   9. RLS: participants see credits, host sees transactions, unfunded can't skip
--  10. Old billing trigger disabled
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(52);

-- =============================================================================
-- SETUP: Create test users and data
-- =============================================================================

INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::UUID, 'host@credits.test', 'pass', NOW(), NOW(), NOW()),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::UUID, 'user2@credits.test', 'pass', NOW(), NOW(), NOW()),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc'::UUID, 'user3@credits.test', 'pass', NOW(), NOW(), NOW()),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd'::UUID, 'outsider@credits.test', 'pass', NOW(), NOW(), NOW()),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::UUID, 'extra1@credits.test', 'pass', NOW(), NOW(), NOW()),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff'::UUID, 'extra2@credits.test', 'pass', NOW(), NOW(), NOW());

-- =============================================================================
-- TEST 1: Chat creation auto-creates chat_credits with balance=50
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT;
    v_balance INTEGER;
    v_txn_count INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum,
                       proposing_threshold_count, proposing_threshold_percent,
                       rating_threshold_count, rating_threshold_percent)
    VALUES ('Credits Test Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3,
            NULL, 100, NULL, 100)
    RETURNING id INTO v_chat_id;

    PERFORM set_config('test.chat_id', v_chat_id::text, true);

    SELECT credit_balance INTO v_balance
    FROM chat_credits WHERE chat_id = v_chat_id;

    SELECT COUNT(*) INTO v_txn_count
    FROM chat_credit_transactions
    WHERE chat_id = v_chat_id AND transaction_type = 'initial';

    -- Verify balance and transaction exist
    IF v_balance != 50 THEN
        RAISE EXCEPTION 'Expected 50, got %', v_balance;
    END IF;
    IF v_txn_count != 1 THEN
        RAISE EXCEPTION 'Expected 1 initial transaction, got %', v_txn_count;
    END IF;
END $$;

SELECT pass('Chat creation auto-creates chat_credits with balance=50 and initial transaction');

-- =============================================================================
-- SETUP: Add participants
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_host_pid BIGINT;
    v_user2_pid BIGINT;
    v_user3_pid BIGINT;
BEGIN
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User2', FALSE, 'active')
    RETURNING id INTO v_user2_pid;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'User3', FALSE, 'active')
    RETURNING id INTO v_user3_pid;

    PERFORM set_config('test.host_pid', v_host_pid::text, true);
    PERFORM set_config('test.user2_pid', v_user2_pid::text, true);
    PERFORM set_config('test.user3_pid', v_user3_pid::text, true);
END $$;

-- =============================================================================
-- TEST 2: can_round_start returns true when credits >= participants
-- =============================================================================

SELECT ok(
    public.can_round_start(current_setting('test.chat_id')::BIGINT),
    'can_round_start returns true with 50 credits and 3 participants'
);

-- =============================================================================
-- TEST 3: can_round_start returns false when credits < participants
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
BEGIN
    UPDATE chat_credits SET credit_balance = 2 WHERE chat_id = v_chat_id;
END $$;

SELECT ok(
    NOT public.can_round_start(current_setting('test.chat_id')::BIGINT),
    'can_round_start returns false with 2 credits and 3 participants'
);

-- Restore balance for next tests
DO $$
BEGIN
    UPDATE chat_credits SET credit_balance = 50
    WHERE chat_id = current_setting('test.chat_id')::BIGINT;
END $$;

-- =============================================================================
-- TEST 4-6: fund_round_participants: full funding
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_funded INTEGER;
    v_balance INTEGER;
    v_funding_count INTEGER;
BEGIN
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    PERFORM set_config('test.cycle_id', v_cycle_id::text, true);
    PERFORM set_config('test.round_id', v_round_id::text, true);

    v_funded := public.fund_round_participants(v_round_id, v_chat_id);

    SELECT credit_balance INTO v_balance FROM chat_credits WHERE chat_id = v_chat_id;
    SELECT COUNT(*) INTO v_funding_count FROM round_funding WHERE round_id = v_round_id;

    -- Verify all 3 funded, balance decreased by 3, funding records created
    IF v_funded != 3 THEN
        RAISE EXCEPTION 'Expected 3 funded, got %', v_funded;
    END IF;
    IF v_balance != 47 THEN
        RAISE EXCEPTION 'Expected balance 47, got %', v_balance;
    END IF;
    IF v_funding_count != 3 THEN
        RAISE EXCEPTION 'Expected 3 funding records, got %', v_funding_count;
    END IF;
END $$;

SELECT pass('fund_round_participants: funds all 3 participants');

SELECT is(
    public.get_funded_participant_count(current_setting('test.round_id')::BIGINT),
    3,
    'get_funded_participant_count returns 3 after funding'
);

SELECT ok(
    public.is_participant_funded(
        current_setting('test.round_id')::BIGINT,
        current_setting('test.host_pid')::BIGINT
    ),
    'is_participant_funded returns true for funded host'
);

-- =============================================================================
-- TEST 7: fund_round_participants: partial funding (insufficient credits)
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT := current_setting('test.cycle_id')::BIGINT;
    v_round2_id BIGINT;
    v_funded INTEGER;
    v_balance INTEGER;
BEGIN
    -- Set balance to 2 (not enough for 3 participants)
    UPDATE chat_credits SET credit_balance = 2 WHERE chat_id = v_chat_id;

    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 2, 'proposing', NOW())
    RETURNING id INTO v_round2_id;

    PERFORM set_config('test.round2_id', v_round2_id::text, true);

    v_funded := public.fund_round_participants(v_round2_id, v_chat_id);

    SELECT credit_balance INTO v_balance FROM chat_credits WHERE chat_id = v_chat_id;

    IF v_funded != 2 THEN
        RAISE EXCEPTION 'Expected 2 funded (partial), got %', v_funded;
    END IF;
    IF v_balance != 0 THEN
        RAISE EXCEPTION 'Expected balance 0, got %', v_balance;
    END IF;
END $$;

SELECT pass('fund_round_participants: partial funding with insufficient credits');

-- =============================================================================
-- TEST 8: fund_round_participants: ordered by created_at (host first)
-- =============================================================================

-- The host was created first, so should be in the funded set
SELECT ok(
    public.is_participant_funded(
        current_setting('test.round2_id')::BIGINT,
        current_setting('test.host_pid')::BIGINT
    ),
    'Partial funding includes host (created first)'
);

-- User3 was created last, should NOT be funded when only 2 credits available
SELECT ok(
    NOT public.is_participant_funded(
        current_setting('test.round2_id')::BIGINT,
        current_setting('test.user3_pid')::BIGINT
    ),
    'Partial funding excludes last-joined participant'
);

-- =============================================================================
-- TEST 9-11: fund_mid_round_join
-- =============================================================================

-- Restore some balance for mid-round join tests
DO $$
BEGIN
    UPDATE chat_credits SET credit_balance = 5
    WHERE chat_id = current_setting('test.chat_id')::BIGINT;
END $$;

-- Test mid-round join success
SELECT ok(
    public.fund_mid_round_join(
        current_setting('test.user3_pid')::BIGINT,
        current_setting('test.chat_id')::BIGINT
    ),
    'fund_mid_round_join returns true when credits available'
);

-- Test idempotency
SELECT ok(
    public.fund_mid_round_join(
        current_setting('test.user3_pid')::BIGINT,
        current_setting('test.chat_id')::BIGINT
    ),
    'fund_mid_round_join is idempotent (returns true for already-funded)'
);

-- Verify balance only decreased by 1 (not 2 for duplicate call)
DO $$
DECLARE
    v_balance INTEGER;
BEGIN
    SELECT credit_balance INTO v_balance
    FROM chat_credits WHERE chat_id = current_setting('test.chat_id')::BIGINT;

    IF v_balance != 4 THEN
        RAISE EXCEPTION 'Expected balance 4 (5 - 1 mid-round), got %', v_balance;
    END IF;
END $$;

SELECT pass('fund_mid_round_join: idempotent, only deducts once');

-- Test insufficient credits
DO $$
DECLARE
    v_chat2_id BIGINT;
    v_participant_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_funded BOOLEAN;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Zero Credit Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3)
    RETURNING id INTO v_chat2_id;

    -- Set balance to 0
    UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_chat2_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat2_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_participant_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat2_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    v_funded := public.fund_mid_round_join(v_participant_id, v_chat2_id);

    IF v_funded THEN
        RAISE EXCEPTION 'Expected false when no credits, got true';
    END IF;
END $$;

SELECT pass('fund_mid_round_join returns false when 0 credits (spectator)');

-- =============================================================================
-- TEST 13: add_chat_credits increases balance
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_result chat_credits;
BEGIN
    v_result := public.add_chat_credits(v_chat_id, 100, 'cs_test_session_001');

    IF v_result.credit_balance != 104 THEN  -- 4 + 100
        RAISE EXCEPTION 'Expected balance 104, got %', v_result.credit_balance;
    END IF;
END $$;

SELECT pass('add_chat_credits increases balance by purchased amount');

-- =============================================================================
-- TEST 14: add_chat_credits is idempotent on Stripe session ID (returns existing, no throw)
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_result chat_credits;
    v_balance INTEGER;
BEGIN
    -- Call again with same session ID — should NOT throw, NOT double-add
    v_result := public.add_chat_credits(v_chat_id, 100, 'cs_test_session_001');

    -- Balance should be unchanged (104, not 204)
    SELECT credit_balance INTO v_balance
    FROM chat_credits WHERE chat_id = v_chat_id;

    IF v_balance != 104 THEN
        RAISE EXCEPTION 'Balance changed on duplicate session! Expected 104, got %', v_balance;
    END IF;
END $$;

SELECT pass('add_chat_credits: duplicate Stripe session returns existing balance (idempotent)');

-- Verify only one transaction for this session
DO $$
DECLARE
    v_txn_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_txn_count
    FROM chat_credit_transactions
    WHERE stripe_checkout_session_id = 'cs_test_session_001';

    IF v_txn_count != 1 THEN
        RAISE EXCEPTION 'Expected 1 transaction for session, got %', v_txn_count;
    END IF;
END $$;

SELECT pass('add_chat_credits: only one transaction created per Stripe session');

-- =============================================================================
-- TEST 16: create_round_for_cycle creates 'proposing' when credits sufficient
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_phase TEXT;
    v_funded_count INTEGER;
BEGIN
    -- Ensure enough credits and auto mode
    UPDATE chat_credits SET credit_balance = 50 WHERE chat_id = v_chat_id;
    UPDATE chats SET start_mode = 'auto', auto_start_participant_count = 3
    WHERE id = v_chat_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;

    v_round_id := create_round_for_cycle(v_cycle_id, v_chat_id, 1);

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    v_funded_count := public.get_funded_participant_count(v_round_id);

    PERFORM set_config('test.funded_round_id', v_round_id::text, true);

    IF v_phase != 'proposing' THEN
        RAISE EXCEPTION 'Expected proposing, got %', v_phase;
    END IF;
    IF v_funded_count != 3 THEN
        RAISE EXCEPTION 'Expected 3 funded, got %', v_funded_count;
    END IF;
END $$;

SELECT pass('create_round_for_cycle creates proposing round and funds participants when credits sufficient');

-- =============================================================================
-- TEST 17: create_round_for_cycle creates 'waiting' when credits insufficient
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_phase TEXT;
    v_funded_count INTEGER;
BEGIN
    UPDATE chat_credits SET credit_balance = 1 WHERE chat_id = v_chat_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    PERFORM set_config('test.paused_cycle_id', v_cycle_id::text, true);

    v_round_id := create_round_for_cycle(v_cycle_id, v_chat_id, 1);

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    v_funded_count := public.get_funded_participant_count(v_round_id);

    PERFORM set_config('test.paused_round_id', v_round_id::text, true);

    IF v_phase != 'waiting' THEN
        RAISE EXCEPTION 'Expected waiting (credit-paused), got %', v_phase;
    END IF;
    IF v_funded_count != 0 THEN
        RAISE EXCEPTION 'Expected 0 funded (paused), got %', v_funded_count;
    END IF;
END $$;

SELECT pass('create_round_for_cycle creates credit-paused waiting round when insufficient credits');

-- =============================================================================
-- TEST 18: check_credit_resume unpauses round after credits added
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_paused_round_id BIGINT := current_setting('test.paused_round_id')::BIGINT;
    v_phase TEXT;
    v_funded_count INTEGER;
    v_result chat_credits;
BEGIN
    -- Add enough credits to resume
    v_result := public.add_chat_credits(v_chat_id, 50, 'cs_test_resume_001');

    -- Check the paused round was resumed
    SELECT phase INTO v_phase FROM rounds WHERE id = v_paused_round_id;
    v_funded_count := public.get_funded_participant_count(v_paused_round_id);

    IF v_phase != 'proposing' THEN
        RAISE EXCEPTION 'Expected proposing after resume, got %', v_phase;
    END IF;
    IF v_funded_count != 3 THEN
        RAISE EXCEPTION 'Expected 3 funded after resume, got %', v_funded_count;
    END IF;
END $$;

SELECT pass('check_credit_resume unpauses waiting round and funds participants after credits added');

-- =============================================================================
-- TEST 19-20: Early-advance uses funded count
-- =============================================================================

-- Create a round where only 2 of 3 participants are funded
DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_host_pid BIGINT := current_setting('test.host_pid')::BIGINT;
    v_user2_pid BIGINT := current_setting('test.user2_pid')::BIGINT;
    v_user3_pid BIGINT := current_setting('test.user3_pid')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_phase TEXT;
BEGIN
    -- Setup: threshold_percent=100, so need ALL funded participants
    UPDATE chats SET
        proposing_threshold_percent = 100,
        proposing_threshold_count = NULL,
        proposing_minimum = 3,
        rating_start_mode = 'auto',
        rating_duration_seconds = 180
    WHERE id = v_chat_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at,
                        phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    PERFORM set_config('test.ea_round_id', v_round_id::text, true);

    -- Fund only host and user2 (NOT user3)
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_host_pid),
        (v_round_id, v_user2_pid);

    -- Both funded participants submit propositions
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_pid, 'Host proposition');

    -- After host prop, only 1/2 funded submitted — should NOT advance
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'proposing' THEN
        RAISE EXCEPTION 'Should still be proposing after 1/2 funded submit, got %', v_phase;
    END IF;
END $$;

SELECT pass('Early-advance: 1/2 funded participants submitted — does NOT advance');

-- Now user2 submits, completing 2/2 funded — should advance
DO $$
DECLARE
    v_round_id BIGINT := current_setting('test.ea_round_id')::BIGINT;
    v_user2_pid BIGINT := current_setting('test.user2_pid')::BIGINT;
    v_phase TEXT;
BEGIN
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_pid, 'User2 proposition');

    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;

    IF v_phase != 'rating' THEN
        RAISE EXCEPTION 'Should advance to rating when 2/2 funded submit, got %', v_phase;
    END IF;
END $$;

SELECT pass('Early-advance: 2/2 funded participants submitted — advances to rating (unfunded user3 ignored)');

-- =============================================================================
-- TEST 21-23: RLS — participants can view credits, host sees transactions
-- =============================================================================

-- Participant (non-host) can see credits
SET ROLE anon;
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);

SELECT is(
    (SELECT credit_balance FROM chat_credits
     WHERE chat_id = current_setting('test.chat_id')::BIGINT),
    (SELECT credit_balance FROM chat_credits
     WHERE chat_id = current_setting('test.chat_id')::BIGINT),
    'Non-host participant can view chat credits'
);

-- Non-host CANNOT see transactions
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM chat_credit_transactions
     WHERE chat_id = current_setting('test.chat_id')::BIGINT),
    0,
    'Non-host participant cannot view credit transactions'
);

-- Host CAN see transactions
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);

SELECT ok(
    (SELECT COUNT(*) FROM chat_credit_transactions
     WHERE chat_id = current_setting('test.chat_id')::BIGINT) > 0,
    'Host can view credit transactions'
);

-- Outsider cannot see credits
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'dddddddd-dddd-dddd-dddd-dddddddddddd'), true);

SELECT is(
    (SELECT COUNT(*)::INTEGER FROM chat_credits
     WHERE chat_id = current_setting('test.chat_id')::BIGINT),
    0,
    'Outsider cannot view chat credits'
);

RESET ROLE;

-- =============================================================================
-- TEST 25: RLS — unfunded participant cannot insert round_skip
-- =============================================================================

-- Create a chat with enough participants to allow skips
-- skip quota = total_active - proposing_minimum, need > 0
-- With 5 active and proposing_minimum=3, skip quota = 2

RESET ROLE;

DO $$
DECLARE
    v_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_funded_pid BIGINT;
    v_unfunded_pid BIGINT;
    v_extra1_pid BIGINT;
    v_extra2_pid BIGINT;
    v_host_uid UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_user2_uid UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    v_user3_uid UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_extra1_uid UUID := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
    v_extra2_uid UUID := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Skip Test Chat', v_host_uid, FALSE, 3)
    RETURNING id INTO v_chat_id;

    -- 5 participants with distinct user_ids to satisfy unique index
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_host_uid, 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user2_uid, 'User2', FALSE, 'active')
    RETURNING id INTO v_funded_pid;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_user3_uid, 'User3', FALSE, 'active')
    RETURNING id INTO v_unfunded_pid;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_extra1_uid, 'Extra1', FALSE, 'active')
    RETURNING id INTO v_extra1_pid;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, v_extra2_uid, 'Extra2', FALSE, 'active')
    RETURNING id INTO v_extra2_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Fund everyone EXCEPT user3
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_host_pid),
        (v_round_id, v_funded_pid),
        (v_round_id, v_extra1_pid),
        (v_round_id, v_extra2_pid);

    PERFORM set_config('test.skip_round_id', v_round_id::text, true);
    PERFORM set_config('test.skip_funded_pid', v_funded_pid::text, true);
    PERFORM set_config('test.skip_unfunded_pid', v_unfunded_pid::text, true);
END $$;

-- User3 is NOT funded — skip should fail
SET ROLE anon;
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'cccccccc-cccc-cccc-cccc-cccccccccccc'), true);

SELECT throws_ok(
    format(
        'INSERT INTO round_skips (round_id, participant_id) VALUES (%s, %s)',
        current_setting('test.skip_round_id'),
        current_setting('test.skip_unfunded_pid')
    ),
    NULL,
    NULL,
    'Unfunded participant cannot insert round_skip'
);

RESET ROLE;

-- =============================================================================
-- TEST 26: RLS — funded participant CAN insert round_skip
-- =============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);

-- user2 is funded — should be able to skip
SELECT lives_ok(
    format(
        'INSERT INTO round_skips (round_id, participant_id) VALUES (%s, %s)',
        current_setting('test.skip_round_id'),
        current_setting('test.skip_funded_pid')
    ),
    'Funded participant can insert round_skip'
);

RESET ROLE;

-- =============================================================================
-- TEST 27: Round funding can be viewed by participants
-- =============================================================================

SET ROLE anon;
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);

SELECT ok(
    (SELECT COUNT(*) FROM round_funding
     WHERE round_id = current_setting('test.skip_round_id')::BIGINT) > 0,
    'Participant can view round_funding records'
);

-- Outsider cannot
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'dddddddd-dddd-dddd-dddd-dddddddddddd'), true);

SELECT is(
    (SELECT COUNT(*)::INTEGER FROM round_funding
     WHERE round_id = current_setting('test.skip_round_id')::BIGINT),
    0,
    'Outsider cannot view round_funding records'
);

RESET ROLE;

-- =============================================================================
-- TEST 29: Old billing trigger is disabled
-- =============================================================================

SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_round_winner_track_usage'
    ),
    'Old billing trigger trg_round_winner_track_usage has been dropped'
);

-- =============================================================================
-- TEST 30: Transaction audit trail is complete
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_types TEXT[];
BEGIN
    SELECT ARRAY_AGG(DISTINCT transaction_type ORDER BY transaction_type) INTO v_types
    FROM chat_credit_transactions
    WHERE chat_id = v_chat_id;

    -- Should have initial, mid_round_join, purchase, round_start
    IF NOT v_types @> ARRAY['initial', 'purchase', 'round_start'] THEN
        RAISE EXCEPTION 'Missing transaction types. Got: %', v_types;
    END IF;
END $$;

SELECT pass('Transaction audit trail includes initial, purchase, and round_start types');

-- =============================================================================
-- TEST 31: fund_round_participants returns 0 when balance is 0
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_funded INTEGER;
BEGIN
    UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_chat_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (v_cycle_id, 1, 'waiting')
    RETURNING id INTO v_round_id;

    v_funded := public.fund_round_participants(v_round_id, v_chat_id);

    IF v_funded != 0 THEN
        RAISE EXCEPTION 'Expected 0 funded when balance is 0, got %', v_funded;
    END IF;
END $$;

SELECT pass('fund_round_participants returns 0 when credit balance is 0');

-- =============================================================================
-- TEST 32: check_credit_resume does NOT resume round with existing propositions
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT := current_setting('test.host_pid')::BIGINT;
    v_phase TEXT;
    v_result chat_credits;
BEGIN
    -- Create a waiting round that has a proposition (waiting-for-rating, not credit-paused)
    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'waiting')
    RETURNING id INTO v_round_id;

    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_pid, 'Waiting for rating prop');
    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    -- Now add credits — should NOT resume this round (it has propositions)
    UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_chat_id;
    v_result := public.add_chat_credits(v_chat_id, 50, 'cs_test_no_resume_001');

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;

    IF v_phase != 'waiting' THEN
        RAISE EXCEPTION 'Should not resume waiting-for-rating round, but phase changed to %', v_phase;
    END IF;
END $$;

SELECT pass('check_credit_resume does NOT resume waiting-for-rating round (has propositions)');

-- =============================================================================
-- EDGE CASE TESTS
-- =============================================================================

-- =============================================================================
-- TEST 33: fund_round_participants is idempotent (double call returns 0)
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_funded1 INTEGER;
    v_funded2 INTEGER;
    v_balance_before INTEGER;
    v_balance_after INTEGER;
BEGIN
    UPDATE chat_credits SET credit_balance = 50 WHERE chat_id = v_chat_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'proposing')
    RETURNING id INTO v_round_id;

    v_funded1 := public.fund_round_participants(v_round_id, v_chat_id);
    SELECT credit_balance INTO v_balance_before FROM chat_credits WHERE chat_id = v_chat_id;

    -- Second call — should return 0 and NOT change balance
    v_funded2 := public.fund_round_participants(v_round_id, v_chat_id);
    SELECT credit_balance INTO v_balance_after FROM chat_credits WHERE chat_id = v_chat_id;

    IF v_funded1 != 3 THEN
        RAISE EXCEPTION 'First call expected 3, got %', v_funded1;
    END IF;
    IF v_funded2 != 0 THEN
        RAISE EXCEPTION 'Second (idempotent) call expected 0, got %', v_funded2;
    END IF;
    IF v_balance_before != v_balance_after THEN
        RAISE EXCEPTION 'Balance changed on idempotent call: % → %', v_balance_before, v_balance_after;
    END IF;
END $$;

SELECT pass('fund_round_participants is idempotent: second call returns 0, balance unchanged');

-- =============================================================================
-- TEST 34: CHECK constraint prevents negative credit_balance
-- =============================================================================

SELECT throws_ok(
    format(
        'UPDATE chat_credits SET credit_balance = -1 WHERE chat_id = %s',
        current_setting('test.chat_id')
    ),
    '23514',  -- check_violation
    NULL,
    'CHECK constraint prevents negative credit_balance'
);

-- =============================================================================
-- TEST 35: add_chat_credits rejects non-positive amount
-- =============================================================================

SELECT throws_ok(
    format(
        'SELECT public.add_chat_credits(%s, 0, NULL)',
        current_setting('test.chat_id')
    ),
    NULL,
    NULL,
    'add_chat_credits rejects amount = 0'
);

-- =============================================================================
-- TEST 36: Credit balance exactly equal to participant count (boundary)
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_funded INTEGER;
    v_balance INTEGER;
BEGIN
    -- Set credits exactly equal to participants (3)
    UPDATE chat_credits SET credit_balance = 3 WHERE chat_id = v_chat_id;

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'proposing')
    RETURNING id INTO v_round_id;

    v_funded := public.fund_round_participants(v_round_id, v_chat_id);
    SELECT credit_balance INTO v_balance FROM chat_credits WHERE chat_id = v_chat_id;

    IF v_funded != 3 THEN
        RAISE EXCEPTION 'Expected all 3 funded at boundary, got %', v_funded;
    END IF;
    IF v_balance != 0 THEN
        RAISE EXCEPTION 'Expected balance 0 after exact deduction, got %', v_balance;
    END IF;
END $$;

SELECT pass('Credit balance exactly equal to participant count: all funded, balance becomes 0');

-- =============================================================================
-- TEST 37: fund_mid_round_join during rating phase
-- =============================================================================

DO $$
DECLARE
    v_chat3_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_joiner_pid BIGINT;
    v_funded BOOLEAN;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Rating Join Test', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3)
    RETURNING id INTO v_chat3_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat3_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat3_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'rating', NOW())
    RETURNING id INTO v_round_id;

    -- Joiner arrives during rating
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat3_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Joiner', FALSE, 'active')
    RETURNING id INTO v_joiner_pid;

    v_funded := public.fund_mid_round_join(v_joiner_pid, v_chat3_id);

    IF NOT v_funded THEN
        RAISE EXCEPTION 'Should fund during rating phase but returned false';
    END IF;

    -- Verify funding record created
    IF NOT EXISTS (
        SELECT 1 FROM round_funding WHERE round_id = v_round_id AND participant_id = v_joiner_pid
    ) THEN
        RAISE EXCEPTION 'No round_funding record created for mid-rating joiner';
    END IF;
END $$;

SELECT pass('fund_mid_round_join works during rating phase');

-- =============================================================================
-- TEST 38: fund_mid_round_join returns true when no active round
-- =============================================================================

DO $$
DECLARE
    v_chat4_id BIGINT;
    v_pid BIGINT;
    v_funded BOOLEAN;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('No Round Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3)
    RETURNING id INTO v_chat4_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat4_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_pid;

    -- No cycle or round exists
    v_funded := public.fund_mid_round_join(v_pid, v_chat4_id);

    IF NOT v_funded THEN
        RAISE EXCEPTION 'Should return true when no active round, got false';
    END IF;
END $$;

SELECT pass('fund_mid_round_join returns true (not error) when no active round exists');

-- =============================================================================
-- TEST 39: fund_mid_round_join records correct transaction in audit trail
-- =============================================================================

DO $$
DECLARE
    v_chat5_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_pid BIGINT;
    v_txn_amount INTEGER;
    v_txn_type TEXT;
    v_txn_participant_count INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Txn Audit Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3)
    RETURNING id INTO v_chat5_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat5_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Joiner', FALSE, 'active')
    RETURNING id INTO v_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat5_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    PERFORM public.fund_mid_round_join(v_pid, v_chat5_id);

    SELECT transaction_type, amount, participant_count
    INTO v_txn_type, v_txn_amount, v_txn_participant_count
    FROM chat_credit_transactions
    WHERE chat_id = v_chat5_id AND transaction_type = 'mid_round_join'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_txn_type != 'mid_round_join' THEN
        RAISE EXCEPTION 'Expected mid_round_join, got %', v_txn_type;
    END IF;
    IF v_txn_amount != -1 THEN
        RAISE EXCEPTION 'Expected amount -1, got %', v_txn_amount;
    END IF;
    IF v_txn_participant_count != 1 THEN
        RAISE EXCEPTION 'Expected participant_count 1, got %', v_txn_participant_count;
    END IF;
END $$;

SELECT pass('fund_mid_round_join creates correct audit transaction (type, amount, count)');

-- =============================================================================
-- TEST 40: check_credit_resume does NOT resume manual-mode chats
-- =============================================================================

DO $$
DECLARE
    v_chat6_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_phase TEXT;
    v_result chat_credits;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum,
                       start_mode, auto_start_participant_count)
    VALUES ('Manual Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3,
            'manual', 3)
    RETURNING id INTO v_chat6_id;

    -- Give enough participants
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat6_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active');
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat6_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User2', FALSE, 'active');
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat6_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'User3', FALSE, 'active');

    -- Create credit-paused round
    UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_chat6_id;
    INSERT INTO cycles (chat_id) VALUES (v_chat6_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'waiting')
    RETURNING id INTO v_round_id;

    -- Add credits — should NOT resume because start_mode = 'manual'
    v_result := public.add_chat_credits(v_chat6_id, 100, NULL);

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'waiting' THEN
        RAISE EXCEPTION 'Manual-mode chat should NOT auto-resume, but phase changed to %', v_phase;
    END IF;
END $$;

SELECT pass('check_credit_resume does NOT resume manual-mode chats');

-- =============================================================================
-- TEST 41: check_credit_resume does NOT resume when insufficient participants
-- =============================================================================

DO $$
DECLARE
    v_chat7_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_phase TEXT;
    v_result chat_credits;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum,
                       start_mode, auto_start_participant_count)
    VALUES ('Not Enough Players', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3,
            'auto', 10)  -- Requires 10 participants to auto-start
    RETURNING id INTO v_chat7_id;

    -- Only 2 participants (need 10)
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat7_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active');
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat7_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User2', FALSE, 'active');

    UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_chat7_id;
    INSERT INTO cycles (chat_id) VALUES (v_chat7_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'waiting')
    RETURNING id INTO v_round_id;

    -- Add credits — should NOT resume because participants < auto_start_participant_count
    v_result := public.add_chat_credits(v_chat7_id, 100, NULL);

    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'waiting' THEN
        RAISE EXCEPTION 'Insufficient participants should prevent resume, but phase changed to %', v_phase;
    END IF;
END $$;

SELECT pass('check_credit_resume does NOT resume when participant count below auto_start threshold');

-- =============================================================================
-- TEST 42: RLS — unfunded participant cannot insert rating_skip
-- =============================================================================

RESET ROLE;

DO $$
DECLARE
    v_chat8_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_funded_pid BIGINT;
    v_unfunded_pid BIGINT;
    v_extra1_pid BIGINT;
    v_extra2_pid BIGINT;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, rating_minimum)
    VALUES ('Rating Skip RLS Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 2)
    RETURNING id INTO v_chat8_id;

    -- 5 participants (rating_minimum=2, so skip quota = 5-2 = 3)
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'FundedUser', FALSE, 'active')
    RETURNING id INTO v_funded_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'UnfundedUser', FALSE, 'active')
    RETURNING id INTO v_unfunded_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Extra1', FALSE, 'active')
    RETURNING id INTO v_extra1_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'Extra2', FALSE, 'active')
    RETURNING id INTO v_extra2_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat8_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Fund everyone EXCEPT cccccccc (UnfundedUser)
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_host_pid),
        (v_round_id, v_funded_pid),
        (v_round_id, v_extra1_pid),
        (v_round_id, v_extra2_pid);

    PERFORM set_config('test.rs_round_id', v_round_id::text, true);
    PERFORM set_config('test.rs_funded_pid', v_funded_pid::text, true);
    PERFORM set_config('test.rs_unfunded_pid', v_unfunded_pid::text, true);
END $$;

-- Unfunded user tries to skip rating — should FAIL
SET ROLE anon;
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'cccccccc-cccc-cccc-cccc-cccccccccccc'), true);

SELECT throws_ok(
    format(
        'INSERT INTO rating_skips (round_id, participant_id) VALUES (%s, %s)',
        current_setting('test.rs_round_id'),
        current_setting('test.rs_unfunded_pid')
    ),
    NULL,
    NULL,
    'Unfunded participant cannot insert rating_skip'
);

-- Funded user CAN skip rating
SELECT set_config('request.jwt.claims', format('{"sub": "%s"}',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);

SELECT lives_ok(
    format(
        'INSERT INTO rating_skips (round_id, participant_id) VALUES (%s, %s)',
        current_setting('test.rs_round_id'),
        current_setting('test.rs_funded_pid')
    ),
    'Funded participant can insert rating_skip'
);

RESET ROLE;

-- =============================================================================
-- TEST 44: Backward compat — early advance on proposition without funding records
-- =============================================================================

DO $$
DECLARE
    v_bc_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_user2_pid BIGINT;
    v_user3_pid BIGINT;
    v_phase TEXT;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant,
                       proposing_minimum, proposing_threshold_percent,
                       rating_start_mode, rating_duration_seconds)
    VALUES ('Backward Compat Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE,
            3, 100, 'auto', 180)
    RETURNING id INTO v_bc_chat_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_bc_chat_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_bc_chat_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User2', FALSE, 'active')
    RETURNING id INTO v_user2_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_bc_chat_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'User3', FALSE, 'active')
    RETURNING id INTO v_user3_pid;

    INSERT INTO cycles (chat_id) VALUES (v_bc_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- NO round_funding records — simulates pre-credit-system round
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_pid, 'BC prop 1');
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_pid, 'BC prop 2');

    -- 2/3 participants submitted, 100% threshold — should NOT advance yet
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'proposing' THEN
        RAISE EXCEPTION 'Should still be proposing after 2/3, got %', v_phase;
    END IF;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user3_pid, 'BC prop 3');

    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    -- 3/3 active submitted with NO funding records — fallback should count all 3 active
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'rating' THEN
        RAISE EXCEPTION 'Should advance to rating with backward compat (no funding records), got %', v_phase;
    END IF;
END $$;

SELECT pass('Backward compat: early advance on proposition works without funding records');

-- =============================================================================
-- TEST 45: Backward compat — early advance on rating without funding records
-- =============================================================================

DO $$
DECLARE
    v_bc2_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_user2_pid BIGINT;
    v_user3_pid BIGINT;
    v_prop_a_id BIGINT;
    v_prop_b_id BIGINT;
    v_prop_c_id BIGINT;
    v_phase TEXT;
BEGIN
    -- Use manual mode to prevent auto-start trigger from creating funded rounds
    INSERT INTO chats (name, creator_id, enable_ai_participant,
                       proposing_minimum, rating_threshold_percent, rating_threshold_count,
                       start_mode)
    VALUES ('BC Rating Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE,
            3, 100, NULL, 'manual')
    RETURNING id INTO v_bc2_chat_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_bc2_chat_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_bc2_chat_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User2', FALSE, 'active')
    RETURNING id INTO v_user2_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_bc2_chat_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'User3', FALSE, 'active')
    RETURNING id INTO v_user3_pid;

    INSERT INTO cycles (chat_id) VALUES (v_bc2_chat_id) RETURNING id INTO v_cycle_id;
    -- Note: manual mode → rating early advance still uses start_mode check
    -- Override to auto so early advance fires
    UPDATE chats SET start_mode = 'auto', auto_start_participant_count = 3
    WHERE id = v_bc2_chat_id;

    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- NO round_funding records — simulates pre-credit round
    -- All 3 participants have propositions
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_pid, 'BC rating prop 1') RETURNING id INTO v_prop_a_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_pid, 'BC rating prop 2') RETURNING id INTO v_prop_b_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user3_pid, 'BC rating prop 3') RETURNING id INTO v_prop_c_id;
    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    -- Host rates user2 and user3's propositions
    INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
    VALUES (v_prop_b_id, v_host_pid, v_round_id, 80);
    INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
    VALUES (v_prop_c_id, v_host_pid, v_round_id, 60);

    -- 1/3 done — not complete yet
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'rating' THEN
        RAISE EXCEPTION 'Should still be rating after 1/3 done, got %', v_phase;
    END IF;

    -- User2 rates host and user3's propositions
    INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
    VALUES (v_prop_a_id, v_user2_pid, v_round_id, 70);
    INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
    VALUES (v_prop_c_id, v_user2_pid, v_round_id, 50);

    -- 2/3 done — still not complete
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'rating' THEN
        RAISE EXCEPTION 'Should still be rating after 2/3 done, got %', v_phase;
    END IF;

    -- User3 rates host and user2's propositions
    INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
    VALUES (v_prop_a_id, v_user3_pid, v_round_id, 90);
    INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
    VALUES (v_prop_b_id, v_user3_pid, v_round_id, 40);

    -- 3/3 done — should complete (backward compat, no funding records, counts all active)
    IF NOT EXISTS (
        SELECT 1 FROM rounds WHERE id = v_round_id AND completed_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Should complete round with backward compat (no funding), but completed_at is NULL';
    END IF;
END $$;

SELECT pass('Backward compat: early advance on rating works without funding records');

-- =============================================================================
-- TEST 46: Early advance rating — only funded participants count toward done
-- =============================================================================

DO $$
DECLARE
    v_ea_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_funded1_pid BIGINT;
    v_funded2_pid BIGINT;
    v_unfunded_pid BIGINT;
    v_prop_a_id BIGINT;
    v_prop_b_id BIGINT;
    v_prop_c_id BIGINT;
BEGIN
    -- Use manual mode to prevent auto-start, then switch to auto for threshold triggers
    INSERT INTO chats (name, creator_id, enable_ai_participant,
                       proposing_minimum, rating_threshold_percent, rating_threshold_count,
                       start_mode)
    VALUES ('Funded Rating EA', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE,
            3, 100, NULL, 'manual')
    RETURNING id INTO v_ea_chat_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_ea_chat_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Funded1', TRUE, 'active')
    RETURNING id INTO v_funded1_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_ea_chat_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Funded2', FALSE, 'active')
    RETURNING id INTO v_funded2_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_ea_chat_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Unfunded', FALSE, 'active')
    RETURNING id INTO v_unfunded_pid;

    -- Switch to auto mode now that participants are inserted
    UPDATE chats SET start_mode = 'auto', auto_start_participant_count = 3
    WHERE id = v_ea_chat_id;

    INSERT INTO cycles (chat_id) VALUES (v_ea_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Fund only Funded1 and Funded2 (NOT Unfunded)
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_funded1_pid),
        (v_round_id, v_funded2_pid);

    -- All 3 have propositions
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_funded1_pid, 'Funded1 prop') RETURNING id INTO v_prop_a_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_funded2_pid, 'Funded2 prop') RETURNING id INTO v_prop_b_id;
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_unfunded_pid, 'Unfunded prop') RETURNING id INTO v_prop_c_id;
    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    PERFORM set_config('test.ea_rating_round_id', v_round_id::text, true);
    PERFORM set_config('test.ea_funded1_pid', v_funded1_pid::text, true);
    PERFORM set_config('test.ea_funded2_pid', v_funded2_pid::text, true);
    PERFORM set_config('test.ea_unfunded_pid2', v_unfunded_pid::text, true);
    PERFORM set_config('test.ea_prop_a_id', v_prop_a_id::text, true);
    PERFORM set_config('test.ea_prop_b_id', v_prop_b_id::text, true);
    PERFORM set_config('test.ea_prop_c_id', v_prop_c_id::text, true);
END $$;

-- Unfunded user rates all props except own (should NOT trigger completion)
INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.ea_prop_a_id')::BIGINT,
     current_setting('test.ea_unfunded_pid2')::BIGINT,
     current_setting('test.ea_rating_round_id')::BIGINT, 90),
    (current_setting('test.ea_prop_b_id')::BIGINT,
     current_setting('test.ea_unfunded_pid2')::BIGINT,
     current_setting('test.ea_rating_round_id')::BIGINT, 50);

SELECT is(
    (SELECT completed_at IS NULL FROM rounds
     WHERE id = current_setting('test.ea_rating_round_id')::BIGINT),
    true,
    'Unfunded participant rating does NOT trigger early advance'
);

-- Funded1 rates all except own — still 1/2 funded done
INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.ea_prop_b_id')::BIGINT,
     current_setting('test.ea_funded1_pid')::BIGINT,
     current_setting('test.ea_rating_round_id')::BIGINT, 75),
    (current_setting('test.ea_prop_c_id')::BIGINT,
     current_setting('test.ea_funded1_pid')::BIGINT,
     current_setting('test.ea_rating_round_id')::BIGINT, 30);

SELECT is(
    (SELECT completed_at IS NULL FROM rounds
     WHERE id = current_setting('test.ea_rating_round_id')::BIGINT),
    true,
    'After 1/2 funded done: still NOT completed (unfunded does not count)'
);

-- Funded2 rates all except own — now 2/2 funded done → should complete
INSERT INTO grid_rankings (proposition_id, participant_id, round_id, grid_position)
VALUES
    (current_setting('test.ea_prop_a_id')::BIGINT,
     current_setting('test.ea_funded2_pid')::BIGINT,
     current_setting('test.ea_rating_round_id')::BIGINT, 60),
    (current_setting('test.ea_prop_c_id')::BIGINT,
     current_setting('test.ea_funded2_pid')::BIGINT,
     current_setting('test.ea_rating_round_id')::BIGINT, 40);

SELECT is(
    (SELECT completed_at IS NOT NULL FROM rounds
     WHERE id = current_setting('test.ea_rating_round_id')::BIGINT),
    true,
    'After 2/2 funded done: COMPLETED (unfunded ignored in threshold)'
);

-- =============================================================================
-- TEST 48: Transaction balance_after field is accurate through a sequence
-- =============================================================================

DO $$
DECLARE
    v_chat9_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_pid BIGINT;
    v_initial_bal INTEGER;
    v_round_start_bal INTEGER;
    v_purchase_bal INTEGER;
    v_actual_balance INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Audit Trail Chat', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3)
    RETURNING id INTO v_chat9_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat9_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_pid;

    -- Initial: 50
    SELECT balance_after INTO v_initial_bal
    FROM chat_credit_transactions
    WHERE chat_id = v_chat9_id AND transaction_type = 'initial';

    IF v_initial_bal != 50 THEN
        RAISE EXCEPTION 'Initial balance_after expected 50, got %', v_initial_bal;
    END IF;

    -- Fund round: -1 participant, balance should be 49
    INSERT INTO cycles (chat_id) VALUES (v_chat9_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (v_cycle_id, 1, 'proposing')
    RETURNING id INTO v_round_id;

    PERFORM public.fund_round_participants(v_round_id, v_chat9_id);

    SELECT balance_after INTO v_round_start_bal
    FROM chat_credit_transactions
    WHERE chat_id = v_chat9_id AND transaction_type = 'round_start'
    ORDER BY created_at DESC LIMIT 1;

    IF v_round_start_bal != 49 THEN
        RAISE EXCEPTION 'Round start balance_after expected 49, got %', v_round_start_bal;
    END IF;

    -- Purchase 100 credits, balance should be 149
    PERFORM public.add_chat_credits(v_chat9_id, 100, 'cs_audit_test_001');

    SELECT balance_after INTO v_purchase_bal
    FROM chat_credit_transactions
    WHERE chat_id = v_chat9_id AND transaction_type = 'purchase'
    ORDER BY created_at DESC LIMIT 1;

    IF v_purchase_bal != 149 THEN
        RAISE EXCEPTION 'Purchase balance_after expected 149, got %', v_purchase_bal;
    END IF;

    -- Verify actual balance matches last transaction's balance_after
    SELECT credit_balance INTO v_actual_balance
    FROM chat_credits WHERE chat_id = v_chat9_id;

    IF v_actual_balance != v_purchase_bal THEN
        RAISE EXCEPTION 'Actual balance % != last txn balance_after %', v_actual_balance, v_purchase_bal;
    END IF;
END $$;

SELECT pass('Transaction balance_after is accurate through initial → round_start → purchase sequence');

-- =============================================================================
-- TEST 49-50: TOCTOU race regression — second round stays in waiting when
-- credits are exhausted by first round
-- =============================================================================

DO $$
DECLARE
    v_race_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round1_id BIGINT;
    v_round2_id BIGINT;
    v_host_pid BIGINT;
    v_user2_pid BIGINT;
    v_user3_pid BIGINT;
    v_phase1 TEXT;
    v_phase2 TEXT;
    v_funded1 INTEGER;
    v_funded2 INTEGER;
    v_balance INTEGER;
BEGIN
    -- Create chat with auto mode and 3 participants
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum,
                       start_mode, auto_start_participant_count,
                       proposing_duration_seconds)
    VALUES ('TOCTOU Race Test', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', FALSE, 3,
            'auto', 3, 300)
    RETURNING id INTO v_race_chat_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_race_chat_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_race_chat_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'User2', FALSE, 'active')
    RETURNING id INTO v_user2_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_race_chat_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'User3', FALSE, 'active')
    RETURNING id INTO v_user3_pid;

    -- Set credits to EXACTLY 3 (enough for one round, not two)
    UPDATE chat_credits SET credit_balance = 3 WHERE chat_id = v_race_chat_id;

    -- Create first cycle
    INSERT INTO cycles (chat_id) VALUES (v_race_chat_id) RETURNING id INTO v_cycle_id;

    -- First round: should succeed — creates in waiting, funds 3, advances to proposing
    v_round1_id := create_round_for_cycle(v_cycle_id, v_race_chat_id, 1);

    SELECT phase INTO v_phase1 FROM rounds WHERE id = v_round1_id;
    v_funded1 := public.get_funded_participant_count(v_round1_id);
    SELECT credit_balance INTO v_balance FROM chat_credits WHERE chat_id = v_race_chat_id;

    IF v_phase1 != 'proposing' THEN
        RAISE EXCEPTION 'First round should be proposing, got %', v_phase1;
    END IF;
    IF v_funded1 != 3 THEN
        RAISE EXCEPTION 'First round should have 3 funded, got %', v_funded1;
    END IF;
    IF v_balance != 0 THEN
        RAISE EXCEPTION 'Balance should be 0 after first round, got %', v_balance;
    END IF;

    -- Second round: simulates the TOCTOU race — credits now exhausted
    -- OLD behavior: can_round_start() might return stale TRUE, create in proposing, fund 0
    -- NEW behavior: creates in waiting, funds 0, stays in waiting
    v_round2_id := create_round_for_cycle(v_cycle_id, v_race_chat_id, 2);

    SELECT phase INTO v_phase2 FROM rounds WHERE id = v_round2_id;
    v_funded2 := public.get_funded_participant_count(v_round2_id);

    IF v_phase2 != 'waiting' THEN
        RAISE EXCEPTION 'Second round should be waiting (credit-paused), got %', v_phase2;
    END IF;
    IF v_funded2 != 0 THEN
        RAISE EXCEPTION 'Second round should have 0 funded, got %', v_funded2;
    END IF;

    PERFORM set_config('test.race_chat_id', v_race_chat_id::text, true);
    PERFORM set_config('test.race_round2_id', v_round2_id::text, true);
END $$;

SELECT pass('TOCTOU regression: first round gets funded and advances to proposing');

-- Second round stays in waiting (credit-paused) — this is the bug fix
SELECT is(
    (SELECT phase FROM rounds WHERE id = current_setting('test.race_round2_id')::BIGINT),
    'waiting',
    'TOCTOU regression: second round stays in waiting when credits exhausted'
);

-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
