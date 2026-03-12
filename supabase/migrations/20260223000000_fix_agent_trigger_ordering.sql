-- Fix: Rename trg_auto_join_agents so it fires AFTER trg_chat_insert_create_credits
--
-- Root cause: PostgreSQL fires AFTER triggers in alphabetical order by name.
-- trg_auto_join_agents < trg_chat_insert_create_credits alphabetically, so agents
-- join BEFORE the credit row exists. When the auto-start trigger then calls
-- create_round_for_cycle(), it finds NULL credits and creates the round in "waiting"
-- instead of "proposing".
--
-- Fix: Rename to trg_chat_insert_join_agents (sorts after trg_chat_insert_create_credits).

DROP TRIGGER IF EXISTS trg_auto_join_agents ON chats;

CREATE TRIGGER trg_chat_insert_join_agents
  AFTER INSERT ON chats
  FOR EACH ROW
  EXECUTE FUNCTION auto_join_agents_on_chat_create();
