-- =============================================================================
-- Fund Unfunded Spectators Tests
-- =============================================================================
-- Tests for:
--   1. fund_unfunded_spectators funds spectators in active proposing round
--   2. fund_unfunded_spectators funds spectators in active rating round
--   3. fund_unfunded_spectators returns 0 when no active round
--   4. fund_unfunded_spectators returns 0 when no unfunded participants
--   5. fund_unfunded_spectators respects credit balance limit
--   6. fund_unfunded_spectators is idempotent
--   7. add_chat_credits triggers fund_unfunded_spectators automatically
--   8. Thresholds update after mid-round funding
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(10);

-- =============================================================================
-- SETUP
-- =============================================================================

INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
    ('a1111111-1111-1111-1111-111111111111'::UUID, 'host@spectator.test', 'pass', NOW(), NOW(), NOW()),
    ('b1111111-1111-1111-1111-111111111111'::UUID, 'funded@spectator.test', 'pass', NOW(), NOW(), NOW()),
    ('c1111111-1111-1111-1111-111111111111'::UUID, 'spectator1@spectator.test', 'pass', NOW(), NOW(), NOW()),
    ('d1111111-1111-1111-1111-111111111111'::UUID, 'spectator2@spectator.test', 'pass', NOW(), NOW(), NOW());

-- =============================================================================
-- TEST 1: fund_unfunded_spectators funds spectators in active proposing round
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_funded_pid BIGINT;
    v_spectator1_pid BIGINT;
    v_spectator2_pid BIGINT;
    v_result INTEGER;
    v_balance INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Spectator Test Chat', 'a1111111-1111-1111-1111-111111111111', FALSE, 3)
    RETURNING id INTO v_chat_id;

    PERFORM set_config('test.chat_id', v_chat_id::text, true);

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, 'b1111111-1111-1111-1111-111111111111', 'Funded', FALSE, 'active')
    RETURNING id INTO v_funded_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, 'c1111111-1111-1111-1111-111111111111', 'Spectator1', FALSE, 'active')
    RETURNING id INTO v_spectator1_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat_id, 'd1111111-1111-1111-1111-111111111111', 'Spectator2', FALSE, 'active')
    RETURNING id INTO v_spectator2_pid;

    PERFORM set_config('test.host_pid', v_host_pid::text, true);
    PERFORM set_config('test.funded_pid', v_funded_pid::text, true);
    PERFORM set_config('test.spectator1_pid', v_spectator1_pid::text, true);
    PERFORM set_config('test.spectator2_pid', v_spectator2_pid::text, true);

    INSERT INTO cycles (chat_id) VALUES (v_chat_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    PERFORM set_config('test.round_id', v_round_id::text, true);

    -- Fund only host and funded user (spectators are unfunded)
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_host_pid),
        (v_round_id, v_funded_pid);

    -- Set credits to 10 (enough for 2 spectators)
    UPDATE chat_credits SET credit_balance = 10 WHERE chat_id = v_chat_id;

    -- Fund unfunded spectators
    v_result := public.fund_unfunded_spectators(v_chat_id);

    IF v_result != 2 THEN
        RAISE EXCEPTION 'Expected 2 spectators funded, got %', v_result;
    END IF;

    -- Verify all 4 are now funded
    IF public.get_funded_participant_count(v_round_id) != 4 THEN
        RAISE EXCEPTION 'Expected 4 funded total, got %',
            public.get_funded_participant_count(v_round_id);
    END IF;

    -- Verify balance decreased by 2
    SELECT credit_balance INTO v_balance FROM chat_credits WHERE chat_id = v_chat_id;
    IF v_balance != 8 THEN
        RAISE EXCEPTION 'Expected balance 8, got %', v_balance;
    END IF;
END $$;

SELECT pass('fund_unfunded_spectators funds 2 spectators in active proposing round');

-- =============================================================================
-- TEST 2: fund_unfunded_spectators returns 0 when no unfunded participants
-- =============================================================================

DO $$
DECLARE
    v_chat_id BIGINT := current_setting('test.chat_id')::BIGINT;
    v_result INTEGER;
BEGIN
    -- All are already funded from test 1
    v_result := public.fund_unfunded_spectators(v_chat_id);

    IF v_result != 0 THEN
        RAISE EXCEPTION 'Expected 0 (all already funded), got %', v_result;
    END IF;
END $$;

SELECT pass('fund_unfunded_spectators is idempotent — returns 0 when all funded');

-- =============================================================================
-- TEST 3: fund_unfunded_spectators returns 0 when no active round
-- =============================================================================

DO $$
DECLARE
    v_no_round_chat_id BIGINT;
    v_result INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('No Round Chat', 'a1111111-1111-1111-1111-111111111111', FALSE, 3)
    RETURNING id INTO v_no_round_chat_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_no_round_chat_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active');

    v_result := public.fund_unfunded_spectators(v_no_round_chat_id);

    IF v_result != 0 THEN
        RAISE EXCEPTION 'Expected 0 (no active round), got %', v_result;
    END IF;
END $$;

SELECT pass('fund_unfunded_spectators returns 0 when no active round');

-- =============================================================================
-- TEST 4: fund_unfunded_spectators respects credit balance limit
-- =============================================================================

DO $$
DECLARE
    v_chat2_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_s1_pid BIGINT;
    v_s2_pid BIGINT;
    v_s3_pid BIGINT;
    v_result INTEGER;
    v_funded_count INTEGER;
    v_balance INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Partial Fund Chat', 'a1111111-1111-1111-1111-111111111111', FALSE, 3)
    RETURNING id INTO v_chat2_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat2_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat2_id, 'b1111111-1111-1111-1111-111111111111', 'S1', FALSE, 'active')
    RETURNING id INTO v_s1_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat2_id, 'c1111111-1111-1111-1111-111111111111', 'S2', FALSE, 'active')
    RETURNING id INTO v_s2_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat2_id, 'd1111111-1111-1111-1111-111111111111', 'S3', FALSE, 'active')
    RETURNING id INTO v_s3_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat2_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Fund only host
    INSERT INTO round_funding (round_id, participant_id) VALUES (v_round_id, v_host_pid);

    -- Only 2 credits available but 3 unfunded
    UPDATE chat_credits SET credit_balance = 2 WHERE chat_id = v_chat2_id;

    v_result := public.fund_unfunded_spectators(v_chat2_id);

    IF v_result != 2 THEN
        RAISE EXCEPTION 'Expected 2 funded (limited by credits), got %', v_result;
    END IF;

    v_funded_count := public.get_funded_participant_count(v_round_id);
    IF v_funded_count != 3 THEN  -- host + 2 newly funded
        RAISE EXCEPTION 'Expected 3 total funded, got %', v_funded_count;
    END IF;

    SELECT credit_balance INTO v_balance FROM chat_credits WHERE chat_id = v_chat2_id;
    IF v_balance != 0 THEN
        RAISE EXCEPTION 'Expected balance 0, got %', v_balance;
    END IF;
END $$;

SELECT pass('fund_unfunded_spectators funds only as many as credits allow');

-- =============================================================================
-- TEST 5: fund_unfunded_spectators works during rating phase
-- =============================================================================

DO $$
DECLARE
    v_chat3_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_spectator_pid BIGINT;
    v_result INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Rating Phase Fund', 'a1111111-1111-1111-1111-111111111111', FALSE, 3)
    RETURNING id INTO v_chat3_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat3_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat3_id, 'b1111111-1111-1111-1111-111111111111', 'Spectator', FALSE, 'active')
    RETURNING id INTO v_spectator_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat3_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'rating', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Fund only host
    INSERT INTO round_funding (round_id, participant_id) VALUES (v_round_id, v_host_pid);

    v_result := public.fund_unfunded_spectators(v_chat3_id);

    IF v_result != 1 THEN
        RAISE EXCEPTION 'Expected 1 spectator funded in rating, got %', v_result;
    END IF;

    IF NOT public.is_participant_funded(v_round_id, v_spectator_pid) THEN
        RAISE EXCEPTION 'Spectator should be funded after fund_unfunded_spectators';
    END IF;
END $$;

SELECT pass('fund_unfunded_spectators funds spectators during rating phase');

-- =============================================================================
-- TEST 6: fund_unfunded_spectators returns 0 when 0 credits
-- =============================================================================

DO $$
DECLARE
    v_chat4_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_spectator_pid BIGINT;
    v_result INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Zero Credit Fund', 'a1111111-1111-1111-1111-111111111111', FALSE, 3)
    RETURNING id INTO v_chat4_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat4_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat4_id, 'b1111111-1111-1111-1111-111111111111', 'Spectator', FALSE, 'active')
    RETURNING id INTO v_spectator_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat4_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    INSERT INTO round_funding (round_id, participant_id) VALUES (v_round_id, v_host_pid);

    UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_chat4_id;

    v_result := public.fund_unfunded_spectators(v_chat4_id);

    IF v_result != 0 THEN
        RAISE EXCEPTION 'Expected 0 when no credits, got %', v_result;
    END IF;
END $$;

SELECT pass('fund_unfunded_spectators returns 0 when 0 credits');

-- =============================================================================
-- TEST 7: add_chat_credits automatically funds spectators in active round
-- =============================================================================

DO $$
DECLARE
    v_chat5_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_spectator_pid BIGINT;
    v_result chat_credits;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Auto Fund On Purchase', 'a1111111-1111-1111-1111-111111111111', FALSE, 3)
    RETURNING id INTO v_chat5_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat5_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat5_id, 'b1111111-1111-1111-1111-111111111111', 'Spectator', FALSE, 'active')
    RETURNING id INTO v_spectator_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat5_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    -- Fund only host
    INSERT INTO round_funding (round_id, participant_id) VALUES (v_round_id, v_host_pid);

    -- Set credits to 0 (spectator joined with no credits)
    UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_chat5_id;

    -- Host buys credits
    v_result := public.add_chat_credits(v_chat5_id, 50, 'cs_auto_fund_001');

    -- Spectator should now be funded automatically
    IF NOT public.is_participant_funded(v_round_id, v_spectator_pid) THEN
        RAISE EXCEPTION 'Spectator should be auto-funded after credit purchase';
    END IF;

    -- Balance should be 50 - 1 (purchase minus spectator funding) = 49
    IF v_result.credit_balance != 49 THEN
        RAISE EXCEPTION 'Expected balance 49 (50 purchased - 1 spectator), got %',
            v_result.credit_balance;
    END IF;
END $$;

SELECT pass('add_chat_credits automatically funds spectators in active round');

-- =============================================================================
-- TEST 8: Funded spectator counts toward early advance thresholds
-- =============================================================================

DO $$
DECLARE
    v_chat6_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_user2_pid BIGINT;
    v_spectator_pid BIGINT;
    v_phase TEXT;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant,
                       proposing_minimum, proposing_threshold_percent,
                       rating_start_mode, rating_duration_seconds)
    VALUES ('Threshold Update Test', 'a1111111-1111-1111-1111-111111111111', FALSE,
            3, 100, 'auto', 180)
    RETURNING id INTO v_chat6_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat6_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat6_id, 'b1111111-1111-1111-1111-111111111111', 'User2', FALSE, 'active')
    RETURNING id INTO v_user2_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat6_id, 'c1111111-1111-1111-1111-111111111111', 'Spectator', FALSE, 'active')
    RETURNING id INTO v_spectator_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat6_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Fund host and user2 only (spectator unfunded)
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_host_pid),
        (v_round_id, v_user2_pid);

    -- Both funded submit propositions
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_pid, 'Host prop');
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_pid, 'User2 prop');

    -- 2/2 funded submitted at 100% threshold — should advance to rating
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'rating' THEN
        RAISE EXCEPTION 'Should advance to rating with 2/2 funded (spectator ignored), got %', v_phase;
    END IF;

    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;
END $$;

SELECT pass('Early advance respects funded count (2/2 funded = advance, spectator ignored)');

-- =============================================================================
-- TEST 9: After funding spectator, threshold denominator increases
-- =============================================================================

DO $$
DECLARE
    v_chat7_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_user2_pid BIGINT;
    v_spectator_pid BIGINT;
    v_phase TEXT;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant,
                       proposing_minimum, proposing_threshold_percent,
                       rating_start_mode, rating_duration_seconds)
    VALUES ('Threshold Increase Test', 'a1111111-1111-1111-1111-111111111111', FALSE,
            3, 100, 'auto', 180)
    RETURNING id INTO v_chat7_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat7_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat7_id, 'b1111111-1111-1111-1111-111111111111', 'User2', FALSE, 'active')
    RETURNING id INTO v_user2_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat7_id, 'c1111111-1111-1111-1111-111111111111', 'Spectator', FALSE, 'active')
    RETURNING id INTO v_spectator_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat7_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at, phase_ends_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW(), NOW() + INTERVAL '5 minutes')
    RETURNING id INTO v_round_id;

    -- Initially fund only host and user2
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_host_pid),
        (v_round_id, v_user2_pid);

    -- Now fund the spectator (simulates credit purchase)
    INSERT INTO round_funding (round_id, participant_id) VALUES
        (v_round_id, v_spectator_pid);

    -- Now funded count is 3. Both host and user2 submit — 2/3 at 100% threshold
    ALTER TABLE propositions DISABLE TRIGGER trg_proposition_limit;

    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_host_pid, 'Host prop');
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_user2_pid, 'User2 prop');

    -- 2/3 funded at 100% threshold — should NOT advance
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'proposing' THEN
        RAISE EXCEPTION 'Should NOT advance with 2/3 funded at 100%%, got %', v_phase;
    END IF;

    -- Now spectator also submits — 3/3 funded
    INSERT INTO propositions (round_id, participant_id, content)
    VALUES (v_round_id, v_spectator_pid, 'Spectator prop');

    ALTER TABLE propositions ENABLE TRIGGER trg_proposition_limit;

    -- 3/3 funded at 100% threshold — should advance now
    SELECT phase INTO v_phase FROM rounds WHERE id = v_round_id;
    IF v_phase != 'rating' THEN
        RAISE EXCEPTION 'Should advance with 3/3 funded at 100%%, got %', v_phase;
    END IF;
END $$;

SELECT pass('After funding spectator, threshold denominator increases (3/3 needed, not 2/2)');

-- =============================================================================
-- TEST 10: Transaction audit trail for fund_unfunded_spectators
-- =============================================================================

DO $$
DECLARE
    v_chat8_id BIGINT;
    v_cycle_id BIGINT;
    v_round_id BIGINT;
    v_host_pid BIGINT;
    v_s1_pid BIGINT;
    v_s2_pid BIGINT;
    v_txn_amount INTEGER;
    v_txn_count INTEGER;
BEGIN
    INSERT INTO chats (name, creator_id, enable_ai_participant, proposing_minimum)
    VALUES ('Audit Spectator Fund', 'a1111111-1111-1111-1111-111111111111', FALSE, 3)
    RETURNING id INTO v_chat8_id;

    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'a1111111-1111-1111-1111-111111111111', 'Host', TRUE, 'active')
    RETURNING id INTO v_host_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'b1111111-1111-1111-1111-111111111111', 'S1', FALSE, 'active')
    RETURNING id INTO v_s1_pid;
    INSERT INTO participants (chat_id, user_id, display_name, is_host, status)
    VALUES (v_chat8_id, 'c1111111-1111-1111-1111-111111111111', 'S2', FALSE, 'active')
    RETURNING id INTO v_s2_pid;

    INSERT INTO cycles (chat_id) VALUES (v_chat8_id) RETURNING id INTO v_cycle_id;
    INSERT INTO rounds (cycle_id, custom_id, phase, phase_started_at)
    VALUES (v_cycle_id, 1, 'proposing', NOW())
    RETURNING id INTO v_round_id;

    INSERT INTO round_funding (round_id, participant_id) VALUES (v_round_id, v_host_pid);
    UPDATE chat_credits SET credit_balance = 10 WHERE chat_id = v_chat8_id;

    PERFORM public.fund_unfunded_spectators(v_chat8_id);

    -- Check transaction was recorded
    SELECT amount, participant_count INTO v_txn_amount, v_txn_count
    FROM chat_credit_transactions
    WHERE chat_id = v_chat8_id AND transaction_type = 'mid_round_join'
    ORDER BY created_at DESC LIMIT 1;

    IF v_txn_amount != -2 THEN
        RAISE EXCEPTION 'Expected transaction amount -2, got %', v_txn_amount;
    END IF;
    IF v_txn_count != 2 THEN
        RAISE EXCEPTION 'Expected participant_count 2, got %', v_txn_count;
    END IF;
END $$;

SELECT pass('fund_unfunded_spectators creates correct audit transaction');

-- =============================================================================

SELECT * FROM finish();
ROLLBACK;
