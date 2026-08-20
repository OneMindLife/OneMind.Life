-- =============================================================================
-- Fix: on_proposition_update_activity + on_rating_update_activity were
-- silently no-oping for non-host inserts.
-- =============================================================================
-- Same shape as the L1 RLS bug fixed in 20260502150000:
--
--   Both triggers fire from user-initiated INSERTs (a participant submits
--   a proposition / rating). The trigger function ran as the calling role
--   (authenticated). Both functions UPDATE chats SET last_activity_at = NOW(),
--   expires_at = ... — but the chats UPDATE policy is host-only:
--
--     "Host can update own chat" USING (
--       service_role OR EXISTS (SELECT 1 FROM participants p
--         WHERE p.chat_id = chats.id AND p.user_id = auth.uid()
--           AND p.is_host AND p.status = 'active'))
--
--   So when a non-host participant submitted a prop/rating, the trigger's
--   UPDATE chats was silently filtered to zero rows by RLS. No error, no
--   warning. Confirmed live by checking chat 353 after a 50-bot stress
--   run: last_activity_at only advanced at round-complete time (when the
--   carried-forward proposition was inserted by a SECURITY DEFINER trigger
--   chain), not from any of the 20 non-host bot proposition inserts.
--
-- Effects:
--   - chats.last_activity_at stale for non-host activity
--   - get_my_chats_dashboard ranking uses stale activity time
--   - Anonymous chats with active non-host participants could expire
--     prematurely, since expires_at is also set inside this trigger
--   - cleanup-inactive-chats cron sees stale activity → false positives
--
-- Fix: SECURITY DEFINER on both functions. The trigger only ever does a
-- single indexed UPDATE on chats by id; no user-controlled SQL in the
-- function body, so DEFINER is safe.
--
-- See feedback_trigger_security_definer.md for the general rule.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.on_proposition_update_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE chats
  SET last_activity_at = NOW(),
      expires_at = CASE
        WHEN creator_session_token IS NOT NULL AND creator_id IS NULL
          THEN NOW() + INTERVAL '7 days'
        ELSE expires_at
      END
  WHERE id = (
    SELECT c.chat_id FROM cycles c
    JOIN rounds r ON r.cycle_id = c.id
    WHERE r.id = NEW.round_id
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_rating_update_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE chats
  SET last_activity_at = NOW(),
      expires_at = CASE
        WHEN creator_session_token IS NOT NULL AND creator_id IS NULL
          THEN NOW() + INTERVAL '7 days'
        ELSE expires_at
      END
  WHERE id = (
    SELECT c.chat_id FROM cycles c
    JOIN rounds r ON r.cycle_id = c.id
    JOIN propositions p ON p.round_id = r.id
    WHERE p.id = NEW.proposition_id
  );
  RETURN NEW;
END;
$$;
