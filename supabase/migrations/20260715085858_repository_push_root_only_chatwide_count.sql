-- Repository-mode push-spam fix (Joel, 2026-07-15): never_seals chats oscillate
-- ALL rounds (root + every child thread) proposing<->rating every 12h. The
-- notify_push_round trigger fires per-round, so without this one cycle would
-- fan out one push per child thread — dozens per 12h. For never_seals chats,
-- ONLY the root round pushes; it counts new opinions CHAT-WIDE so the single
-- nudge still reflects the child-thread activity.

CREATE OR REPLACE FUNCTION public.notify_push_round()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chat_id     BIGINT;
  v_event       TEXT;
  v_secret      TEXT;
  v_url         TEXT;
  v_request_id  BIGINT;
BEGIN
  IF NEW.winning_proposition_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.winning_proposition_id IS DISTINCT FROM NEW.winning_proposition_id) THEN
    v_event := 'winner';
  ELSIF NEW.phase = 'rating'
     AND (TG_OP = 'INSERT' OR OLD.phase IS DISTINCT FROM 'rating') THEN
    v_event := 'vote_open';
  ELSIF NEW.phase = 'proposing'
     AND (TG_OP = 'INSERT' OR OLD.phase IS DISTINCT FROM 'proposing') THEN
    v_event := 'round_open';
  ELSE
    RETURN NEW;
  END IF;

  SELECT ch.id INTO v_chat_id
  FROM cycles c JOIN chats ch ON ch.id = c.chat_id
  WHERE c.id = NEW.cycle_id
    AND ch.is_preview = false
    AND ch.is_arena = false
    AND ch.telegram_chat_id IS NULL
    -- Repository (never_seals) chats: only the ROOT round pushes. Every child
    -- thread flips on the 12h clock; pushing per child would fan out dozens of
    -- notifications per cycle.
    AND NOT (ch.never_seals = true AND c.parent_proposition_id IS NOT NULL);

  IF v_chat_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'push_internal_secret';

  IF v_secret IS NULL THEN
    RAISE WARNING 'notify_push_round skipped: push_internal_secret not configured';
    RETURN NEW;
  END IF;

  v_url := get_edge_function_url('push-events');

  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := jsonb_build_object('pushevent', v_event, 'round_id', NEW.id, 'chat_id', v_chat_id)
  ) INTO v_request_id;

  RAISE LOG 'notify_push_round % for round % chat % (request_id %)',
    v_event, NEW.id, v_chat_id, v_request_id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_push_round error for round %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

-- Chat-wide "new opinions in the last window" count for the repository push.
CREATE OR REPLACE FUNCTION public.get_chat_new_opinion_count(
  p_chat_id bigint,
  p_since timestamptz DEFAULT (now() - interval '12 hours')
) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT count(*)::int
  FROM propositions p
  JOIN rounds rd ON rd.id = p.round_id
  JOIN cycles cy ON cy.id = rd.cycle_id
  JOIN participants pt ON pt.id = p.participant_id
  WHERE cy.chat_id = p_chat_id
    AND p.carried_from_id IS NULL
    AND pt.display_name <> 'AI'
    AND p.created_at >= p_since;
$$;

GRANT EXECUTE ON FUNCTION public.get_chat_new_opinion_count(bigint, timestamptz)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_chat_new_opinion_count(bigint, timestamptz) IS
  'Repository push: count of human, non-carried opinions added chat-wide since p_since (default 12h). One number for the root-round re-engagement nudge.';
