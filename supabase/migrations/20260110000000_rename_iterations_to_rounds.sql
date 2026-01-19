-- =============================================================================
-- MIGRATION: Rename iterations -> rounds + Add configurable consensus settings
-- =============================================================================
-- This migration:
-- 1. Adds confirmation_rounds_required and show_previous_results to chats
-- 2. Renames iterations table to rounds
-- 3. Renames iteration_id column to round_id in propositions
-- 4. Updates all constraints, indexes, policies, functions, and triggers
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Add new columns to chats table
-- =============================================================================

-- confirmation_rounds_required: How many consecutive wins needed for consensus
-- Default 2 maintains current behavior
ALTER TABLE "public"."chats"
ADD COLUMN "confirmation_rounds_required" INTEGER NOT NULL DEFAULT 2;

-- Add constraint to ensure minimum of 1
ALTER TABLE "public"."chats"
ADD CONSTRAINT "chats_confirmation_rounds_required_check"
CHECK ("confirmation_rounds_required" >= 1);

-- show_previous_results: FALSE = show winner only, TRUE = show all propositions with ratings
ALTER TABLE "public"."chats"
ADD COLUMN "show_previous_results" BOOLEAN NOT NULL DEFAULT FALSE;

-- =============================================================================
-- STEP 2: Drop existing trigger (must be done before renaming table)
-- =============================================================================

DROP TRIGGER IF EXISTS "trg_iteration_winner_set" ON "public"."iterations";

-- =============================================================================
-- STEP 3: Rename iterations table to rounds
-- This automatically updates the primary key constraint name
-- =============================================================================

ALTER TABLE "public"."iterations" RENAME TO "rounds";

-- =============================================================================
-- STEP 4: Rename iteration_id column in propositions to round_id
-- =============================================================================

ALTER TABLE "public"."propositions"
RENAME COLUMN "iteration_id" TO "round_id";

-- =============================================================================
-- STEP 5: Rename constraints
-- =============================================================================

-- Note: unique_custom_id_per_cycle keeps same name as it's still descriptive

-- Rename foreign key from iterations to cycles
ALTER TABLE "public"."rounds"
RENAME CONSTRAINT "iterations_cycle_id_fkey" TO "rounds_cycle_id_fkey";

-- Rename foreign key for winning_proposition_id
ALTER TABLE "public"."rounds"
RENAME CONSTRAINT "fk_iteration_winning_proposition" TO "fk_round_winning_proposition";

-- Rename foreign key in propositions
ALTER TABLE "public"."propositions"
RENAME CONSTRAINT "propositions_iteration_id_fkey" TO "propositions_round_id_fkey";

-- Rename phase check constraint
ALTER TABLE "public"."rounds"
RENAME CONSTRAINT "iterations_phase_check" TO "rounds_phase_check";

-- Rename primary key constraint
ALTER TABLE "public"."rounds"
RENAME CONSTRAINT "iterations_pkey" TO "rounds_pkey";

-- =============================================================================
-- STEP 6: Rename indexes
-- =============================================================================

ALTER INDEX "idx_iterations_cycle" RENAME TO "idx_rounds_cycle";
ALTER INDEX "idx_propositions_iteration" RENAME TO "idx_propositions_round";

-- =============================================================================
-- STEP 7: Drop and recreate RLS policies with new names
-- =============================================================================

DROP POLICY IF EXISTS "Anyone can view iterations" ON "public"."rounds";
DROP POLICY IF EXISTS "Service role can manage iterations" ON "public"."rounds";

CREATE POLICY "Anyone can view rounds" ON "public"."rounds"
FOR SELECT USING (true);

CREATE POLICY "Service role can manage rounds" ON "public"."rounds"
USING (true);

-- =============================================================================
-- STEP 8: Update get_next_custom_id function to query rounds table
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."get_next_custom_id"("p_cycle_id" bigint)
RETURNS integer
LANGUAGE "plpgsql"
AS $$
DECLARE
    max_id INT;
BEGIN
    SELECT COALESCE(MAX(custom_id), 0) INTO max_id
    FROM rounds
    WHERE cycle_id = p_cycle_id;
    RETURN max_id + 1;
END;
$$;

-- =============================================================================
-- STEP 9: Drop old function and create new on_round_winner_set function
-- Uses confirmation_rounds_required instead of hardcoded 2
-- =============================================================================

DROP FUNCTION IF EXISTS "public"."on_iteration_winner_set"() CASCADE;

CREATE OR REPLACE FUNCTION "public"."on_round_winner_set"()
RETURNS "trigger"
LANGUAGE "plpgsql"
AS $$
DECLARE
    consecutive_wins INTEGER := 1;
    required_wins INTEGER;
    v_cycle_id BIGINT;
    v_chat_id BIGINT;
    current_custom_id INTEGER;
    check_custom_id INTEGER;
    prev_winner_id BIGINT;
    new_round_id BIGINT;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    v_cycle_id := NEW.cycle_id;

    -- Get chat_id and confirmation_rounds_required from chat settings
    SELECT c.chat_id, ch.confirmation_rounds_required
    INTO v_chat_id, required_wins
    FROM cycles c
    JOIN chats ch ON ch.id = c.chat_id
    WHERE c.id = v_cycle_id;

    -- Mark current round as completed
    NEW.completed_at := NOW();

    -- Count consecutive wins of the current winner (starting at 1 for current round)
    current_custom_id := NEW.custom_id;
    check_custom_id := current_custom_id - 1;

    -- Walk backwards through previous rounds to count consecutive wins
    WHILE check_custom_id >= 1 LOOP
        SELECT winning_proposition_id INTO prev_winner_id
        FROM rounds
        WHERE cycle_id = v_cycle_id
        AND custom_id = check_custom_id;

        -- If previous round had same winner, increment count and continue
        IF prev_winner_id IS NOT NULL AND prev_winner_id = NEW.winning_proposition_id THEN
            consecutive_wins := consecutive_wins + 1;
            check_custom_id := check_custom_id - 1;
        ELSE
            -- Chain broken, stop counting
            EXIT;
        END IF;
    END LOOP;

    -- Check if we've reached the required consecutive wins
    IF consecutive_wins >= required_wins THEN
        -- Consensus reached! Complete the cycle
        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW()
        WHERE id = v_cycle_id;
    ELSE
        -- Need more rounds, create next one
        INSERT INTO rounds (cycle_id, custom_id, phase)
        VALUES (v_cycle_id, get_next_custom_id(v_cycle_id), 'waiting')
        RETURNING id INTO new_round_id;
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."on_round_winner_set"() OWNER TO "postgres";

-- =============================================================================
-- STEP 10: Create new trigger
-- =============================================================================

CREATE TRIGGER "trg_round_winner_set"
BEFORE UPDATE OF "winning_proposition_id" ON "public"."rounds"
FOR EACH ROW
EXECUTE FUNCTION "public"."on_round_winner_set"();

-- =============================================================================
-- STEP 11: Update on_cycle_winner_set to use rounds table name
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."on_cycle_winner_set"()
RETURNS "trigger"
LANGUAGE "plpgsql"
AS $$
DECLARE
    v_chat_id BIGINT;
    new_cycle_id BIGINT;
    new_round_id BIGINT;
BEGIN
    -- Skip if no winner being set or winner unchanged
    IF NEW.winning_proposition_id IS NULL OR
       (OLD.winning_proposition_id IS NOT NULL AND OLD.winning_proposition_id = NEW.winning_proposition_id) THEN
        RETURN NEW;
    END IF;

    -- Get chat_id from this cycle
    SELECT chat_id INTO v_chat_id FROM cycles WHERE id = NEW.id;

    -- Create new cycle for the chat
    INSERT INTO cycles (chat_id)
    VALUES (v_chat_id)
    RETURNING id INTO new_cycle_id;

    -- Create first round of new cycle in waiting phase
    INSERT INTO rounds (cycle_id, custom_id, phase)
    VALUES (new_cycle_id, 1, 'waiting')
    RETURNING id INTO new_round_id;

    RETURN NEW;
END;
$$;

-- =============================================================================
-- STEP 12: Update activity tracking triggers to use rounds table
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."on_proposition_update_activity"()
RETURNS "trigger"
LANGUAGE "plpgsql"
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
        SELECT c.chat_id
        FROM cycles c
        JOIN rounds r ON r.cycle_id = c.id
        WHERE r.id = NEW.round_id
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."on_rating_update_activity"()
RETURNS "trigger"
LANGUAGE "plpgsql"
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
        SELECT c.chat_id
        FROM cycles c
        JOIN rounds r ON r.cycle_id = c.id
        JOIN propositions p ON p.round_id = r.id
        WHERE p.id = NEW.proposition_id
    );
    RETURN NEW;
END;
$$;

-- =============================================================================
-- STEP 13: Grant permissions on new function
-- =============================================================================

GRANT ALL ON FUNCTION "public"."on_round_winner_set"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_round_winner_set"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_round_winner_set"() TO "service_role";

COMMIT;
