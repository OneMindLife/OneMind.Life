-- Root-watch: subscribe to a repository chat's NEW top-level opinions.
--
-- The opinion_watches system watches a specific opinion's reply thread; it can't
-- watch the chat itself (the sync trigger literally bails: "root round, nothing
-- watches it as a thread"). This adds that missing top-level watch so the eye in
-- the appbar means the same thing everywhere: "notify me of new opinions here" —
-- at root = new top-level opinions in the chat; inside an opinion = new replies.
--
-- DEFAULT ON, for everyone. Modeled as absence-or-not-muted = watching, so the
-- default costs zero rows: a row exists only once a user mutes or marks-seen.
-- "watching" = NOT (a row with muted = true). This is the retention default —
-- auto-subscribe every participant to "new opinions dropped" — accepted
-- knowingly (low daily volume; will be watched for fatigue).
--
-- Gated to never_seals (repository) chats — GLOBAL. Round-based chats keep the
-- normal per-round flow and get no root-opinion pings.

CREATE TABLE public.root_watches (
  participant_id bigint PRIMARY KEY REFERENCES participants(id) ON DELETE CASCADE,
  chat_id        bigint NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id        uuid   NOT NULL,   -- denormalized for same-row RLS
  muted          boolean NOT NULL DEFAULT false,  -- default-on: not muted = watching
  last_seen_at   timestamptz,       -- NULL → fall back to participant join time
  updated_at     timestamptz NOT NULL DEFAULT now()
);
-- Push recipient selection only ever needs the MUTED rows for a chat (everyone
-- else is watching by default), so index just those.
CREATE INDEX root_watches_muted_idx ON public.root_watches (chat_id) WHERE muted = true;

ALTER TABLE public.root_watches ENABLE ROW LEVEL SECURITY;
-- Own-row only; all real access is through the SECURITY DEFINER RPCs below, but
-- keep a scoped policy so a direct read can't see other users' rows.
CREATE POLICY root_watches_owner ON public.root_watches
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Count of top-level opinions a participant hasn't seen: new (not carried), not
-- their own, in the chat's ROOT cycle, created after their effective last-seen
-- (their explicit last_seen, else their join time). Shared by the state RPC.
CREATE FUNCTION public._root_unseen_count(p_participant_id bigint, p_chat_id bigint)
RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT count(*)::int
  FROM propositions p
  JOIN rounds r  ON r.id = p.round_id
  JOIN cycles c  ON c.id = r.cycle_id
  WHERE c.chat_id = p_chat_id
    AND c.parent_proposition_id IS NULL          -- root cycle = top level
    AND p.carried_from_id IS NULL
    AND p.participant_id IS DISTINCT FROM p_participant_id
    AND p.created_at > COALESCE(
      (SELECT rw.last_seen_at FROM root_watches rw WHERE rw.participant_id = p_participant_id),
      (SELECT pt.created_at FROM participants pt WHERE pt.id = p_participant_id)
    );
$$;

-- The eye's state + the badge contribution: are you watching root, and how many
-- new top-level opinions since you last looked (0 when muted).
CREATE FUNCTION public.get_root_watch_state(p_participant_id bigint)
RETURNS TABLE(watching boolean, new_count int, chat_id bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_chat bigint; v_muted boolean;
BEGIN
  SELECT pt.chat_id INTO v_chat
  FROM participants pt WHERE pt.id = p_participant_id AND pt.user_id = auth.uid();
  IF v_chat IS NULL THEN RETURN; END IF;   -- not your participant / not found

  SELECT rw.muted INTO v_muted FROM root_watches rw WHERE rw.participant_id = p_participant_id;
  watching := NOT COALESCE(v_muted, false);
  new_count := CASE WHEN watching THEN public._root_unseen_count(p_participant_id, v_chat) ELSE 0 END;
  chat_id := v_chat;
  RETURN NEXT;
END;
$$;

-- Toggle the root watch. p_watch=false mutes; p_watch=true un-mutes (back to the
-- default). last_seen is left NULL/untouched — it's owned by mark_root_seen — so
-- muting then un-muting shows what's new since you last LOOKED, not since you
-- toggled. (An earlier version stamped last_seen=now() here, which let muting
-- silently clear the unseen count.)
CREATE FUNCTION public.set_root_watch(p_participant_id bigint, p_watch boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM participants WHERE id = p_participant_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'not your participant';
  END IF;
  INSERT INTO root_watches (participant_id, chat_id, user_id, muted)
  SELECT p_participant_id, pt.chat_id, auth.uid(), NOT p_watch
  FROM participants pt WHERE pt.id = p_participant_id
  ON CONFLICT (participant_id) DO UPDATE
    SET muted = NOT p_watch, updated_at = now();
END;
$$;

-- Reset the badge: mark root seen now. Creates the row (default watching) if
-- absent, preserves `muted` if present. Called when the user views root.
CREATE FUNCTION public.mark_root_seen(p_participant_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM participants WHERE id = p_participant_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'not your participant';
  END IF;
  INSERT INTO root_watches (participant_id, chat_id, user_id, muted, last_seen_at)
  SELECT p_participant_id, pt.chat_id, auth.uid(), false, now()
  FROM participants pt WHERE pt.id = p_participant_id
  ON CONFLICT (participant_id) DO UPDATE
    SET last_seen_at = now(), updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.get_root_watch_state(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_root_watch(bigint, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_root_seen(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_root_watch_state(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_root_watch(bigint, boolean) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_root_seen(bigint) TO anon, authenticated, service_role;

-- ── Push: ping root-watchers when a new top-level opinion lands ──────────────
-- Twin of notify_push_watch_reply, for the ROOT case it deliberately skips. The
-- parent check is what keeps the two from double-firing: reply-push handles
-- child threads (parent NOT NULL), this handles root (parent NULL). Recipient
-- selection (all non-muted chat participants who hold a token, minus the author)
-- lives in the edge fn; the trigger only decides WHETHER to fire.
CREATE FUNCTION public.notify_push_root_opinion()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_chat_id     bigint;
  v_never_seals boolean;
  v_secret      text;
  v_request_id  bigint;
BEGIN
  IF NEW.carried_from_id IS NOT NULL OR NEW.participant_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Root-cycle opinion in a live, non-preview repository chat only.
  SELECT ch.id, ch.never_seals INTO v_chat_id, v_never_seals
  FROM rounds r JOIN cycles c ON c.id = r.cycle_id JOIN chats ch ON ch.id = c.chat_id
  WHERE r.id = NEW.round_id
    AND c.parent_proposition_id IS NULL
    AND ch.is_preview = false;
  IF v_chat_id IS NULL OR NOT COALESCE(v_never_seals, false) THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'push_internal_secret';
  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_push_root_opinion skipped: push_internal_secret not configured';
    RETURN NEW;
  END IF;

  SELECT net.http_post(
    url := get_edge_function_url('push-events'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object(
      'pushevent', 'root_opinion',
      'opinion_id', NEW.id,
      'chat_id', v_chat_id,
      'author_participant_id', NEW.participant_id
    )
  ) INTO v_request_id;

  RAISE LOG 'notify_push_root_opinion opinion % chat % (request_id %)',
    NEW.id, v_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_push_root_opinion error for opinion %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER notify_push_root_opinion_trg
  AFTER INSERT ON public.propositions
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_root_opinion();

COMMENT ON TABLE public.root_watches IS
  'Per-participant subscription to a repository chat''s new top-level opinions. Default ON (absence or muted=false = watching). Feeds the appbar eye at root + the bell badge + root-opinion push.';
