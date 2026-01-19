-- Fix on_round_winner_track_usage to use participant_id instead of session_token
-- The session_token column was removed during migration to auth.uid()

CREATE OR REPLACE FUNCTION public.on_round_winner_track_usage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_chat RECORD;
    v_participant_count INTEGER;
    v_host_user_id UUID;
BEGIN
    -- Only trigger when winning_proposition_id is set (round completed)
    IF NEW.winning_proposition_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip if already had a winner (update case)
    IF OLD.winning_proposition_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Get the chat for this round
    SELECT c.* INTO v_chat
    FROM public.chats c
    JOIN public.cycles cy ON cy.chat_id = c.id
    WHERE cy.id = NEW.cycle_id;

    IF v_chat.id IS NULL THEN
        RETURN NEW;
    END IF;

    -- If host was anonymous, no usage tracking (already limited by expiry)
    IF v_chat.host_was_anonymous OR v_chat.creator_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_host_user_id := v_chat.creator_id;

    -- Count unique participants who submitted propositions in this round
    SELECT COUNT(DISTINCT p.participant_id) INTO v_participant_count
    FROM public.propositions p
    WHERE p.round_id = NEW.id;

    -- Also count raters who didn't propose (using grid_rankings)
    SELECT v_participant_count + COUNT(DISTINCT gr.participant_id) INTO v_participant_count
    FROM public.grid_rankings gr
    WHERE gr.round_id = NEW.id
      AND gr.participant_id IS NOT NULL
      AND gr.participant_id NOT IN (
          SELECT DISTINCT p2.participant_id
          FROM public.propositions p2
          WHERE p2.round_id = NEW.id
      );

    -- Minimum 1 user-round even if no participants recorded
    IF v_participant_count < 1 THEN
        v_participant_count := 1;
    END IF;

    -- Deduct user-rounds from host's account
    -- Note: This will fail silently if host can't afford it
    -- The actual blocking should happen before allowing new rounds
    PERFORM deduct_user_rounds(
        v_host_user_id,
        v_participant_count,
        v_chat.id,
        NEW.id
    );

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION on_round_winner_track_usage() IS
'Tracks usage when a round completes. Uses participant_id from propositions and grid_rankings tables.';
