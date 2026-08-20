-- When a user changes their profile display_name (auth.users metadata),
-- propagate it to all their participant rows so existing chat memberships
-- update automatically (previously the participant name was a frozen snapshot
-- taken at join time). Exception-safe: never blocks an auth update.
CREATE OR REPLACE FUNCTION public.sync_display_name_to_participants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_new TEXT := NEW.raw_user_meta_data->>'display_name';
  v_old TEXT := OLD.raw_user_meta_data->>'display_name';
BEGIN
  IF v_new IS DISTINCT FROM v_old
     AND v_new IS NOT NULL
     AND length(btrim(v_new)) > 0 THEN
    UPDATE public.participants
    SET display_name = v_new
    WHERE user_id = NEW.id
      AND display_name IS DISTINCT FROM v_new
      AND is_agent = false;  -- never rename AI participants
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never let a name-sync failure block the auth update.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_display_name_to_participants_trg ON auth.users;
CREATE TRIGGER sync_display_name_to_participants_trg
AFTER UPDATE OF raw_user_meta_data ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.sync_display_name_to_participants();

COMMENT ON FUNCTION public.sync_display_name_to_participants() IS
'Propagates auth display_name changes to participants.display_name (all the user''s non-agent memberships). Exception-safe so it never blocks an auth update.';
