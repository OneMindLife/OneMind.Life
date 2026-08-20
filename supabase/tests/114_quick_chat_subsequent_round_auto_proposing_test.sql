-- Tests for: quick chats (max_cycles=1) auto-enter PROPOSING on a subsequent
-- round (custom_id > 1) instead of landing in 'waiting' (the "Start" step).
-- Migration: 20260605181444_quick_chat_subsequent_round_auto_proposing.sql
--
-- Verifies the change is correctly SCOPED:
--   1. quick chat + round 2 -> proposing (the fix)
--   2. quick chat + round 2 -> no timer (phase_ends_at NULL; host-controlled)
--   3. quick chat + round 1 -> still 'waiting' (round 1 unchanged)
--   4. normal chat (max_cycles NULL) + round 2 -> still 'waiting' (unchanged)
BEGIN;
SELECT plan(4);

DO $$
DECLARE
  v_quick_chat INT; v_quick_cycle INT;
  v_normal_chat INT; v_normal_cycle INT;
  v_round BIGINT;
BEGIN
  -- Quick chat: max_cycles = 1, manual start (as quick-create sets it)
  INSERT INTO chats (name, initial_message, creator_session_token, start_mode, max_cycles)
    VALUES ('QC auto-proposing test', 'x', gen_random_uuid(), 'manual', 1)
    RETURNING id INTO v_quick_chat;
  INSERT INTO cycles (chat_id) VALUES (v_quick_chat) RETURNING id INTO v_quick_cycle;

  -- Normal (full-wizard) chat: max_cycles NULL, manual
  INSERT INTO chats (name, initial_message, creator_session_token, start_mode, max_cycles)
    VALUES ('Normal multi-cycle test', 'x', gen_random_uuid(), 'manual', NULL)
    RETURNING id INTO v_normal_chat;
  INSERT INTO cycles (chat_id) VALUES (v_normal_chat) RETURNING id INTO v_normal_cycle;

  -- Quick chat, SUBSEQUENT round (custom_id = 2) -> the fix
  v_round := create_round_for_cycle(v_quick_cycle, v_quick_chat, 2);
  PERFORM set_config('test.qc_r2', v_round::TEXT, TRUE);

  -- Quick chat, FIRST round (custom_id = 1) -> unchanged
  v_round := create_round_for_cycle(v_quick_cycle, v_quick_chat, 1);
  PERFORM set_config('test.qc_r1', v_round::TEXT, TRUE);

  -- Normal chat, subsequent round (custom_id = 2) -> unchanged (manual -> waiting)
  v_round := create_round_for_cycle(v_normal_cycle, v_normal_chat, 2);
  PERFORM set_config('test.nc_r2', v_round::TEXT, TRUE);
END $$;

SELECT is(
  (SELECT phase::TEXT FROM rounds WHERE id = current_setting('test.qc_r2')::BIGINT),
  'proposing',
  'Quick chat subsequent round (custom_id>1) auto-enters PROPOSING'
);

SELECT is(
  (SELECT phase_ends_at IS NULL FROM rounds WHERE id = current_setting('test.qc_r2')::BIGINT),
  TRUE,
  'Quick chat auto-proposing round has NO timer (phase_ends_at NULL, host-controlled)'
);

SELECT is(
  (SELECT phase::TEXT FROM rounds WHERE id = current_setting('test.qc_r1')::BIGINT),
  'waiting',
  'Quick chat FIRST round (custom_id=1) still lands in waiting (round 1 unchanged)'
);

SELECT is(
  (SELECT phase::TEXT FROM rounds WHERE id = current_setting('test.nc_r2')::BIGINT),
  'waiting',
  'Normal chat (max_cycles NULL) subsequent round still lands in waiting (unchanged)'
);

SELECT * FROM finish();
ROLLBACK;
