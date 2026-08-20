-- =============================================================================
-- Test: official/arena rooms bypass the auto-start credit funding gate
--       (20260804140000_official_room_no_funding_gate)
-- =============================================================================
-- create_round_for_cycle used to open an auto-mode round only when
-- chat_credits.credit_balance >= the active participant count; otherwise it left
-- the round stuck in 'waiting' (credit-paused). GLOBAL is a free public room
-- whose participant count is inflated by thousands of accumulated drive-by
-- joiners, so that gate froze every new round. Official/arena rooms already
-- bypass the SUBMISSION funding gate; the fix bypasses this ROUND-CREATION gate
-- for them too. Billed private chats keep the credit gate.
--
-- The fix condition is `is_official OR is_arena` -- both flags flow through the
-- identical bypass branch. A partial unique index (idx_chats_single_official)
-- allows only ONE official chat DB-wide, so the bypass branch is exercised with
-- ARENA chats (not singleton), plus one case on the real pre-existing official
-- chat to cover the is_official flag specifically.
--
-- create_round_for_cycle is called directly; chats are seeded 'manual' and
-- flipped to 'auto' so the auto-start trigger doesn't create a round early.
--
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================

BEGIN;
SET search_path TO public, extensions;
SELECT plan(6);

-- Arena (non-official) chat with n active participants and optional credits;
-- returns the phase create_round_for_cycle opens.
CREATE OR REPLACE FUNCTION _arena_round_phase(p_arena bool, p_credits int, p_n int)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_chat int; v_cycle bigint; v_round bigint; i int; v_phase text;
BEGIN
  INSERT INTO chats (name, initial_message, creator_session_token, start_mode,
    auto_start_participant_count, is_official, is_arena, rating_mode, proposing_duration_seconds)
  VALUES ('nofund', 'Q', gen_random_uuid(), 'manual', 1, false, p_arena, 'matches', 60)
  RETURNING id INTO v_chat;
  FOR i IN 1..p_n LOOP
    INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_chat, gen_random_uuid(), 'P'||i, i = 1, 'active');
  END LOOP;
  IF p_credits IS NOT NULL THEN
    -- A chat_credits row is auto-created on chat insert, so upsert the balance.
    INSERT INTO chat_credits (chat_id, credit_balance) VALUES (v_chat, p_credits)
    ON CONFLICT (chat_id) DO UPDATE SET credit_balance = EXCLUDED.credit_balance;
  END IF;
  UPDATE chats SET start_mode = 'auto' WHERE id = v_chat;   -- no trigger: no new participant
  INSERT INTO cycles (chat_id) VALUES (v_chat) RETURNING id INTO v_cycle;
  v_round := create_round_for_cycle(v_cycle, v_chat, 1);
  SELECT phase INTO v_phase FROM rounds WHERE id = v_round;
  PERFORM set_config('t.round', v_round::text, true);
  RETURN v_phase;
END $fn$;

-- ============ Arena bypass ============
SELECT is(
  _arena_round_phase(true, NULL, 3),
  'proposing',
  'arena room with NO credit record -> round opens proposing (gate bypassed)');

SELECT is(
  _arena_round_phase(true, 1, 100),
  'proposing',
  'arena room, 1 credit vs 100 participants -> still opens proposing (the GLOBAL stall case)');

SELECT ok(
  (SELECT phase_ends_at IS NOT NULL FROM rounds WHERE id = current_setting('t.round')::bigint),
  'bypassed round carries a live timer (phase_ends_at set), not a null-timer waiting round');

-- ============ Billed private chats keep the gate ============
SELECT is(
  _arena_round_phase(false, 0, 3),
  'waiting',
  'billed chat with 0 credits vs 3 participants -> stays waiting (credit gate intact)');

SELECT is(
  _arena_round_phase(false, 100, 3),
  'proposing',
  'billed chat with ample credits -> funded round opens proposing (funded path intact)');

-- ============ The real official chat (is_official branch) ============
DO $$
DECLARE v_off int; v_cycle bigint; v_round bigint;
BEGIN
  SELECT id INTO v_off FROM chats WHERE is_official = true LIMIT 1;
  UPDATE chats SET start_mode = 'auto', auto_start_participant_count = 1,
                   proposing_duration_seconds = 60 WHERE id = v_off;
  INSERT INTO participants (chat_id, session_token, display_name, is_host, status)
    VALUES (v_off, gen_random_uuid(), 'OFFTEST', true, 'active');
  UPDATE chat_credits SET credit_balance = 0 WHERE chat_id = v_off;  -- force the gate scenario
  INSERT INTO cycles (chat_id) VALUES (v_off) RETURNING id INTO v_cycle;
  v_round := create_round_for_cycle(v_cycle, v_off, 1);
  PERFORM set_config('t.off_phase', (SELECT phase FROM rounds WHERE id = v_round), true);
END $$;

SELECT is(
  current_setting('t.off_phase'),
  'proposing',
  'the real official chat opens proposing with 0 credits (is_official branch)');

SELECT * FROM finish();
ROLLBACK;
