-- =============================================================================
-- MIGRATION: Denormalize chat_id onto the remaining realtime round-child tables
-- =============================================================================
-- Same root cause + fix as 20260602140000 (propositions): Supabase Realtime
-- can't authorize a multi-table-join SELECT policy, so it silently drops every
-- postgres_changes event. These 4 tables (all realtime-published, all only
-- have round_id) have the identical deep-join policy → identical dead realtime:
--   - rating_completions  (drives the live matches-progress bar — most impactful)
--   - rating_skips, round_skips, affirmations
--
-- Fix (mirrors propositions): denormalize chat_id + a single-table
-- is_chat_participant(chat_id) policy realtime CAN evaluate. chat_id is derived
-- server-side from round_id by a shared SECURITY DEFINER trigger (ENABLE ALWAYS
-- so it fires under session_replication_role=replica bulk loads / trigger-off
-- test setups too). See memory realtime_rls_deep_join_breaks_delivery.
-- =============================================================================

-- Shared trigger: derive chat_id from round_id (works for any round-child table).
CREATE OR REPLACE FUNCTION public.set_round_child_chat_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT c.chat_id
    INTO NEW.chat_id
  FROM public.rounds r
  JOIN public.cycles c ON c.id = r.cycle_id
  WHERE r.id = NEW.round_id;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('rating_completions', 'Chat participants can view rating_completions'),
      ('rating_skips',       'Users can read rating skips in their chats'),
      ('round_skips',        'Users can read skips in their chats'),
      ('affirmations',       'affirmations_select_chat_participants')
    ) AS x(tbl, oldpol)
  LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS chat_id BIGINT '
      'REFERENCES public.chats(id) ON DELETE CASCADE', t.tbl);

    EXECUTE format(
      'UPDATE public.%I tt SET chat_id = c.chat_id '
      'FROM public.rounds r JOIN public.cycles c ON c.id = r.cycle_id '
      'WHERE r.id = tt.round_id AND tt.chat_id IS NULL', t.tbl);

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN chat_id SET NOT NULL', t.tbl);

    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_chat_id ON public.%I(chat_id)',
                   t.tbl, t.tbl);

    EXECUTE format('DROP TRIGGER IF EXISTS set_%s_chat_id_trg ON public.%I', t.tbl, t.tbl);
    EXECUTE format(
      'CREATE TRIGGER set_%s_chat_id_trg BEFORE INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.set_round_child_chat_id()', t.tbl, t.tbl);
    EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER set_%s_chat_id_trg',
                   t.tbl, t.tbl);

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t.oldpol, t.tbl);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT USING ('
      '(current_setting(''role'', true) = ''service_role'') '
      'OR public.is_chat_participant(chat_id))', t.oldpol, t.tbl);

    EXECUTE format(
      'COMMENT ON COLUMN public.%I.chat_id IS %L', t.tbl,
      'Denormalized parent chat (derived from round->cycle by '
      'set_round_child_chat_id trigger) so the SELECT RLS policy is a single-table '
      'is_chat_participant() check Supabase Realtime can authorize. Do not set from client.');
  END LOOP;
END $$;
