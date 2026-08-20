-- =============================================================================
-- MIGRATION: Denormalize chat_id onto propositions so Realtime can authorize it
-- =============================================================================
-- ROOT CAUSE (confirmed via live instrumentation 2026-06-02):
--   Supabase Realtime authorizes each postgres_changes row by evaluating the
--   table's SELECT RLS policy against that row, with the subscriber's identity.
--   The propositions SELECT policy was a 4-table hop
--     EXISTS (participants p JOIN rounds r ON r.id = propositions.round_id
--                            JOIN cycles  c ON c.id = r.cycle_id
--             WHERE p.chat_id = c.chat_id AND p.user_id = auth.uid())
--   Realtime cannot evaluate that multi-hop join per row, so it SILENTLY DROPS
--   every proposition INSERT/UPDATE/DELETE from every subscriber — proposition
--   realtime has been quietly dead app-wide. (Participants realtime works because
--   its policy is the single-table helper is_chat_participant(chat_id).)
--
-- FIX (Supabase-documented best practice for Realtime + RLS): denormalize the
--   parent key onto the child table and authorize with a single-table check, so
--   the policy is realtime-evaluable AND a cheap indexed lookup at scale.
--   We mirror the participants policy exactly: is_chat_participant(chat_id).
--
-- SAFETY: chat_id is derived server-side from round_id by a BEFORE INSERT
--   trigger (SECURITY DEFINER), so a client cannot set/spoof it to widen its own
--   visibility. Access granted by the new policy is identical to the old one
--   (participant of the proposition's chat) — just authorizable by realtime.
-- =============================================================================

-- 1. Column + FK + index ------------------------------------------------------
ALTER TABLE public.propositions
  ADD COLUMN IF NOT EXISTS chat_id BIGINT REFERENCES public.chats(id) ON DELETE CASCADE;

-- 2. Backfill existing rows from round -> cycle -> chat -----------------------
UPDATE public.propositions p
SET chat_id = c.chat_id
FROM public.rounds r
JOIN public.cycles c ON c.id = r.cycle_id
WHERE r.id = p.round_id
  AND p.chat_id IS NULL;

-- Every proposition resolves to a chat (round_id, cycle_id, chat_id are all
-- NOT NULL FKs), so the backfill is total — enforce it.
ALTER TABLE public.propositions
  ALTER COLUMN chat_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_propositions_chat_id
  ON public.propositions(chat_id);

-- 3. Server-derive chat_id on insert (unspoofable) ----------------------------
-- SECURITY DEFINER so the round->cycle lookup isn't itself RLS-filtered. Only
-- modifies NEW (no cross-table DML), so it's an allowlist-eligible BEFORE-row
-- trigger under the 107 trigger-security audit.
CREATE OR REPLACE FUNCTION public.set_proposition_chat_id()
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

DROP TRIGGER IF EXISTS set_proposition_chat_id_trg ON public.propositions;
CREATE TRIGGER set_proposition_chat_id_trg
  BEFORE INSERT ON public.propositions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_proposition_chat_id();

-- This is a data-integrity trigger (chat_id must always be derived), so it must
-- fire even when session_replication_role = 'replica' disables ordinary triggers
-- (e.g. bulk loads, or test setups that populate denormalized data directly).
-- Without ENABLE ALWAYS, such inserts would leave chat_id NULL and trip NOT NULL.
ALTER TABLE public.propositions
  ENABLE ALWAYS TRIGGER set_proposition_chat_id_trg;

-- 4. Swap the SELECT policy to the realtime-authorizable, single-table form ----
DROP POLICY IF EXISTS "Chat participants can view propositions" ON public.propositions;
CREATE POLICY "Chat participants can view propositions" ON public.propositions
  FOR SELECT
  USING (
    (current_setting('role', true) = 'service_role')
    OR public.is_chat_participant(chat_id)
  );

COMMENT ON COLUMN public.propositions.chat_id IS
  'Denormalized parent chat (derived from round->cycle by set_proposition_chat_id '
  'trigger). Exists so the SELECT RLS policy is a single-table is_chat_participant() '
  'check that Supabase Realtime can authorize — a multi-hop join could not be, and '
  'silently dropped all proposition realtime events. Do not set from the client.';
