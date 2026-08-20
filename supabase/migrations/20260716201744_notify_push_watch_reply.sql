-- Push-on-reply — the retention loop's return leg. When a new opinion lands in
-- a watched thread, ping that thread's watchers (except the reply's author) via
-- FCM so an away user is pulled back to read it. The DB-trigger twin of
-- notify_push_round: same vault bearer (push_internal_secret), same
-- push-events edge fn, new 'watch_reply' event.
--
-- Recipient selection lives in the edge fn (it must join fcm_tokens); the
-- trigger only decides WHETHER to fire — cheap existence check for at least one
-- watcher other than the author — and hands the edge fn the parent thread, the
-- reply, the chat, and the author to exclude. Fires independently of
-- sync_watch_on_opinion (which maintains new_count); order between them is
-- irrelevant since this reads watcher existence, not the count.

CREATE OR REPLACE FUNCTION public.notify_push_watch_reply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_parent      BIGINT;
  v_chat_id     BIGINT;
  v_secret      TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  -- Carried winners aren't new discussion; anonymous rows have no author to
  -- exclude and never originate from a person watching.
  IF NEW.carried_from_id IS NOT NULL OR NEW.participant_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- The thread this opinion replies to = its cycle's parent proposition. Root
  -- rounds have no parent → nothing watches them as a thread.
  SELECT cc.parent_proposition_id INTO v_parent
  FROM rounds cr JOIN cycles cc ON cc.id = cr.cycle_id
  WHERE cr.id = NEW.round_id;
  IF v_parent IS NULL THEN
    RETURN NEW;
  END IF;

  -- No watcher other than the author → nobody to notify, skip the HTTP round-trip.
  IF NOT EXISTS (
    SELECT 1 FROM opinion_watches ow
    WHERE ow.proposition_id = v_parent
      AND ow.participant_id IS DISTINCT FROM NEW.participant_id
  ) THEN
    RETURN NEW;
  END IF;

  -- Chat for tap-routing; skip preview junk (arena/telegram chats still get
  -- reply pings — the edge fn filters to users who actually hold FCM tokens).
  SELECT ch.id INTO v_chat_id
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = (SELECT cycle_id FROM rounds WHERE id = NEW.round_id)
    AND ch.is_preview = false;
  IF v_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'push_internal_secret';
  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_push_watch_reply skipped: push_internal_secret not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('push-events');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object(
      'pushevent', 'watch_reply',
      'proposition_id', v_parent,
      'reply_id', NEW.id,
      'chat_id', v_chat_id,
      'author_participant_id', NEW.participant_id
    )
  ) INTO v_request_id;

  RAISE LOG 'notify_push_watch_reply parent % reply % chat % (request_id %)',
    v_parent, NEW.id, v_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_push_watch_reply error for reply %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_push_watch_reply_trg ON public.propositions;
CREATE TRIGGER notify_push_watch_reply_trg
  AFTER INSERT ON public.propositions
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_watch_reply();

COMMENT ON FUNCTION public.notify_push_watch_reply() IS
  'Posts a watch_reply event to the push-events edge fn when a new (non-carried) opinion lands in a watched thread, so the thread''s watchers (except the author) get an FCM ping. Retention return-leg; twin of notify_push_round.';
