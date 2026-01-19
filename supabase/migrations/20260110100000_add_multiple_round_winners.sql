-- =============================================================================
-- MIGRATION: Add Multiple Round Winners Support
-- =============================================================================
-- This migration adds:
-- 1. round_winners junction table - stores all tied winners per round
-- 2. is_sole_winner column on rounds - tracks if win counts toward consensus
-- 3. Updated on_round_winner_set trigger - only counts SOLE wins
-- 4. Backfill existing data
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Create round_winners junction table
-- =============================================================================

CREATE TABLE IF NOT EXISTS "public"."round_winners" (
    "id" BIGSERIAL PRIMARY KEY,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "proposition_id" BIGINT NOT NULL REFERENCES "public"."propositions"("id") ON DELETE CASCADE,
    "rank" INTEGER NOT NULL DEFAULT 1,
    "global_score" REAL,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    CONSTRAINT "unique_round_proposition" UNIQUE ("round_id", "proposition_id"),
    CONSTRAINT "positive_rank" CHECK ("rank" >= 1)
);

ALTER TABLE "public"."round_winners" OWNER TO "postgres";

COMMENT ON TABLE "public"."round_winners" IS
'Stores all winners for each round. Multiple entries indicate a tie.
- rank: 1 = first place (tied winners all have rank 1)
- global_score: MOVDA score at time of win for reference';

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS "idx_round_winners_round" ON "public"."round_winners" ("round_id");
CREATE INDEX IF NOT EXISTS "idx_round_winners_proposition" ON "public"."round_winners" ("proposition_id");
CREATE INDEX IF NOT EXISTS "idx_round_winners_rank" ON "public"."round_winners" ("round_id", "rank");

-- =============================================================================
-- STEP 2: Add is_sole_winner column to rounds
-- =============================================================================

ALTER TABLE "public"."rounds"
ADD COLUMN IF NOT EXISTS "is_sole_winner" BOOLEAN DEFAULT NULL;

COMMENT ON COLUMN "public"."rounds"."is_sole_winner" IS
'TRUE = single winner (counts toward consensus tracking)
FALSE = tied winners (does NOT count toward consensus)
NULL = not yet determined';

-- =============================================================================
-- STEP 3: Backfill existing data
-- =============================================================================

-- Create round_winners entries for all existing completed rounds
-- These were all single winners (before this migration)
INSERT INTO "public"."round_winners" (round_id, proposition_id, rank, created_at)
SELECT id, winning_proposition_id, 1, COALESCE(completed_at, NOW())
FROM "public"."rounds"
WHERE winning_proposition_id IS NOT NULL
ON CONFLICT (round_id, proposition_id) DO NOTHING;

-- Mark all existing completed rounds as sole winners
UPDATE "public"."rounds"
SET is_sole_winner = TRUE
WHERE winning_proposition_id IS NOT NULL
AND is_sole_winner IS NULL;

-- =============================================================================
-- STEP 4: Update on_round_winner_set trigger
-- =============================================================================
-- Key change: Only count consecutive SOLE wins toward consensus

CREATE OR REPLACE FUNCTION "public"."on_round_winner_set"()
RETURNS "trigger"
LANGUAGE "plpgsql"
AS $$
DECLARE
    consecutive_sole_wins INTEGER := 0;
    required_wins INTEGER;
    v_cycle_id BIGINT;
    v_chat_id BIGINT;
    current_custom_id INTEGER;
    check_custom_id INTEGER;
    prev_winner_id BIGINT;
    prev_is_sole BOOLEAN;
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

    -- Default to 2 if not set
    IF required_wins IS NULL THEN
        required_wins := 2;
    END IF;

    -- Mark current round as completed
    NEW.completed_at := NOW();

    -- CRITICAL: Only count this win toward consensus if it's a SOLE win (no ties)
    IF NEW.is_sole_winner = TRUE THEN
        consecutive_sole_wins := 1;

        -- Walk backwards through previous rounds to count consecutive SOLE wins
        current_custom_id := NEW.custom_id;
        check_custom_id := current_custom_id - 1;

        WHILE check_custom_id >= 1 LOOP
            SELECT winning_proposition_id, is_sole_winner
            INTO prev_winner_id, prev_is_sole
            FROM rounds
            WHERE cycle_id = v_cycle_id
            AND custom_id = check_custom_id;

            -- Count only if: same winner AND was a sole win (not tied)
            IF prev_winner_id IS NOT NULL
               AND prev_winner_id = NEW.winning_proposition_id
               AND prev_is_sole = TRUE THEN
                consecutive_sole_wins := consecutive_sole_wins + 1;
                check_custom_id := check_custom_id - 1;
            ELSE
                -- Chain broken (different winner OR was a tie)
                EXIT;
            END IF;
        END LOOP;

        RAISE NOTICE '[ROUND WINNER] Proposition % has % consecutive sole win(s), need %',
            NEW.winning_proposition_id, consecutive_sole_wins, required_wins;
    ELSE
        -- Tied win - does not count toward consensus
        RAISE NOTICE '[ROUND WINNER] Round % ended in tie (is_sole_winner=FALSE), does not count toward consensus',
            NEW.id;
    END IF;

    -- Check if we've reached the required consecutive SOLE wins
    IF consecutive_sole_wins >= required_wins THEN
        -- Consensus reached! Complete the cycle
        RAISE NOTICE '[ROUND WINNER] CONSENSUS REACHED! Completing cycle % with winner %',
            v_cycle_id, NEW.winning_proposition_id;

        UPDATE cycles
        SET winning_proposition_id = NEW.winning_proposition_id,
            completed_at = NOW()
        WHERE id = v_cycle_id;
    ELSE
        -- Need more rounds, create next one
        INSERT INTO rounds (cycle_id, custom_id, phase)
        VALUES (v_cycle_id, get_next_custom_id(v_cycle_id), 'waiting')
        RETURNING id INTO new_round_id;

        RAISE NOTICE '[ROUND WINNER] Created next round % for cycle %', new_round_id, v_cycle_id;
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."on_round_winner_set"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."on_round_winner_set"() IS
'Trigger function that handles round winner logic.
- Only SOLE wins (is_sole_winner=TRUE) count toward consecutive win tracking
- Tied wins (is_sole_winner=FALSE) do NOT count - they break the chain
- Creates next round or completes cycle based on consecutive sole wins';

-- =============================================================================
-- STEP 5: Enable RLS and create policies
-- =============================================================================

ALTER TABLE "public"."round_winners" ENABLE ROW LEVEL SECURITY;

-- Anyone can view round winners
CREATE POLICY "Anyone can view round_winners" ON "public"."round_winners"
FOR SELECT USING (TRUE);

-- Service role can manage (for process-timers Edge Function)
CREATE POLICY "Service role can manage round_winners" ON "public"."round_winners"
FOR ALL USING (TRUE);

-- =============================================================================
-- STEP 6: Grant permissions
-- =============================================================================

GRANT SELECT ON "public"."round_winners" TO anon, authenticated;
GRANT ALL ON "public"."round_winners" TO service_role;
GRANT USAGE, SELECT ON SEQUENCE "public"."round_winners_id_seq" TO anon, authenticated, service_role;

-- =============================================================================
-- STEP 7: Create helper function to get round winners with propositions
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."get_round_winners"(
    "p_round_id" BIGINT
)
RETURNS TABLE (
    winner_id BIGINT,
    round_id BIGINT,
    proposition_id BIGINT,
    rank INTEGER,
    global_score REAL,
    content TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE "plpgsql" SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        rw.id as winner_id,
        rw.round_id,
        rw.proposition_id,
        rw.rank,
        rw.global_score,
        p.content,
        rw.created_at
    FROM round_winners rw
    JOIN propositions p ON p.id = rw.proposition_id
    WHERE rw.round_id = p_round_id
    ORDER BY rw.rank ASC, rw.global_score DESC NULLS LAST;
END;
$$;

ALTER FUNCTION "public"."get_round_winners"(BIGINT) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."get_round_winners" IS
'Returns all winners for a round with their proposition content.
Multiple rows indicate a tie. Ordered by rank then score.';

GRANT EXECUTE ON FUNCTION "public"."get_round_winners"(BIGINT) TO anon, authenticated, service_role;

COMMIT;
