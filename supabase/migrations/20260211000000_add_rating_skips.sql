-- =============================================================================
-- MIGRATION: Add rating_skips table for Skip Rating Feature
-- =============================================================================
-- Allows users to skip rating during the rating phase.
-- Skippers count toward participation for early advance calculations,
-- allowing rounds to complete earlier when enough people rate + skip.
--
-- Key constraints:
-- - Only one skip per participant per round (unique constraint)
-- - Skip quota: current_skips < total_participants - rating_minimum
-- - Once rated (grid_rankings), cannot skip (enforced by RLS)
-- =============================================================================

-- Table to track users who skip rating
CREATE TABLE "public"."rating_skips" (
    "id" BIGSERIAL PRIMARY KEY,
    "round_id" BIGINT NOT NULL REFERENCES "public"."rounds"("id") ON DELETE CASCADE,
    "participant_id" BIGINT NOT NULL REFERENCES "public"."participants"("id") ON DELETE CASCADE,
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT "unique_round_participant_rating_skip" UNIQUE ("round_id", "participant_id")
);

-- Index for faster lookups by round
CREATE INDEX "idx_rating_skips_round_id" ON "public"."rating_skips"("round_id");

-- Enable Row Level Security
ALTER TABLE "public"."rating_skips" ENABLE ROW LEVEL SECURITY;

-- Helper function to count rating skips for a round (bypasses RLS to avoid recursion)
CREATE OR REPLACE FUNCTION public.count_rating_skips(p_round_id BIGINT)
RETURNS INTEGER
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
    SELECT COUNT(*)::INTEGER FROM public.rating_skips WHERE round_id = p_round_id;
$$;

COMMENT ON FUNCTION public.count_rating_skips IS
'Helper function to count rating skips for a round. Uses SECURITY DEFINER to bypass RLS and avoid infinite recursion in the rating_skips INSERT policy.';

-- RLS Policy: Users can skip rating in rounds they participate in
-- Validates:
-- 1. User is a participant (via participant_id -> user_id check)
-- 2. Round is in rating phase
-- 3. User hasn't already rated (no grid_rankings for this round)
-- 4. Skip quota not exceeded (skips < participants - rating_minimum)
CREATE POLICY "Users can skip rating in rounds they participate in" ON "public"."rating_skips"
    FOR INSERT WITH CHECK (
        -- Verify participant belongs to current user
        participant_id IN (
            SELECT id FROM participants WHERE user_id = auth.uid()
        )
        -- Verify round is in rating phase
        AND EXISTS (
            SELECT 1 FROM rounds WHERE id = round_id AND phase = 'rating'
        )
        -- Verify user hasn't already submitted any ratings for this round
        AND NOT EXISTS (
            SELECT 1 FROM grid_rankings gr
            JOIN propositions p ON p.id = gr.proposition_id
            WHERE p.round_id = rating_skips.round_id
            AND gr.participant_id = rating_skips.participant_id
        )
        -- Verify skip quota not exceeded (skips < participants - rating_minimum)
        -- Uses helper function to avoid infinite recursion
        AND count_rating_skips(round_id) < (
            SELECT COUNT(*)::INTEGER FROM participants p
            JOIN cycles c ON p.chat_id = c.chat_id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = rating_skips.round_id AND p.status = 'active'
        ) - COALESCE((
            SELECT ch.rating_minimum FROM chats ch
            JOIN cycles c ON c.chat_id = ch.id
            JOIN rounds r ON r.cycle_id = c.id
            WHERE r.id = rating_skips.round_id
        ), 2)
    );

-- RLS Policy: Users can read rating skips in rounds of chats they participate in
CREATE POLICY "Users can read rating skips in their chats" ON "public"."rating_skips"
    FOR SELECT USING (
        round_id IN (
            SELECT r.id FROM rounds r
            JOIN cycles c ON r.cycle_id = c.id
            JOIN participants p ON c.chat_id = p.chat_id
            WHERE p.user_id = auth.uid()
        )
    );

-- Enable realtime for rating_skips table
ALTER PUBLICATION supabase_realtime ADD TABLE "public"."rating_skips";

-- Set replica identity to FULL for realtime subscriptions
ALTER TABLE "public"."rating_skips" REPLICA IDENTITY FULL;

COMMENT ON TABLE "public"."rating_skips" IS
'Tracks participants who skip rating during the rating phase.
Skippers count toward participation for early advance threshold calculations.
Skip quota: total_skips < total_participants - rating_minimum';

COMMENT ON COLUMN "public"."rating_skips"."round_id" IS 'The round being skipped';
COMMENT ON COLUMN "public"."rating_skips"."participant_id" IS 'The participant who is skipping rating';

-- =============================================================================
-- UPDATE: check_early_advance_on_rating() to account for rating skippers
-- =============================================================================
-- Subtract rating skippers from the total participants when calculating
-- the required cap (since skippers can't rate, the max raters per prop
-- is total_participants - 1 - rating_skippers).

CREATE OR REPLACE FUNCTION check_early_advance_on_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_proposition RECORD;
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_total_propositions INTEGER;
    v_total_ratings INTEGER;
    v_avg_raters_per_prop NUMERIC;
    v_required INTEGER;
    v_rating_skip_count INTEGER;
BEGIN
    -- Get proposition and round info
    SELECT p.*, r.id as round_id, r.phase, r.cycle_id, c.chat_id
    INTO v_proposition
    FROM propositions p
    JOIN rounds r ON r.id = p.round_id
    JOIN cycles c ON c.id = r.cycle_id
    WHERE p.id = NEW.proposition_id;

    -- Only check during rating phase
    IF v_proposition.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM chats
    WHERE id = v_proposition.chat_id;

    -- Skip if no thresholds configured
    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip manual mode (manual facilitation doesn't use auto-advance)
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- Count active participants
    SELECT COUNT(*) INTO v_total_participants
    FROM participants
    WHERE chat_id = v_proposition.chat_id AND status = 'active';

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count rating skips for this round
    SELECT COUNT(*) INTO v_rating_skip_count
    FROM rating_skips
    WHERE round_id = v_proposition.round_id;

    -- Count total propositions in this round
    SELECT COUNT(*) INTO v_total_propositions
    FROM propositions
    WHERE round_id = v_proposition.round_id;

    IF v_total_propositions = 0 THEN
        RETURN NEW;
    END IF;

    -- Count total ratings in this round (from grid_rankings)
    SELECT COUNT(*) INTO v_total_ratings
    FROM grid_rankings gr
    JOIN propositions p ON p.id = gr.proposition_id
    WHERE p.round_id = v_proposition.round_id;

    -- Calculate average raters per proposition
    v_avg_raters_per_prop := v_total_ratings::NUMERIC / v_total_propositions::NUMERIC;

    -- Calculate required threshold
    v_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    -- Cap at participants - 1 - rating_skippers:
    -- Each participant skips their own proposition (so -1),
    -- and rating skippers won't rate at all (so -skip_count)
    IF v_required IS NOT NULL AND v_total_participants > 1 THEN
        v_required := LEAST(v_required, v_total_participants - 1 - v_rating_skip_count);
        -- Ensure required doesn't go below 1
        IF v_required < 1 THEN
            v_required := 1;
        END IF;
    END IF;

    -- Check if average raters per proposition meets threshold
    IF v_required IS NOT NULL AND v_avg_raters_per_prop >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating threshold met (avg %.2f raters/prop >= %, % total ratings on % props, % skips). Completing round %.',
            v_avg_raters_per_prop, v_required, v_total_ratings, v_total_propositions, v_rating_skip_count, v_proposition.round_id;

        -- Complete the round with winner calculation
        PERFORM complete_round_with_winner(v_proposition.round_id);

        -- Apply adaptive duration for next round (if enabled)
        PERFORM apply_adaptive_duration(v_proposition.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- NEW: check_early_advance_on_rating_skip() trigger function
-- =============================================================================
-- A rating skip can push participation over the threshold, triggering advance.
-- Uses same logic as check_early_advance_on_rating but triggered on rating_skips INSERT.

CREATE OR REPLACE FUNCTION check_early_advance_on_rating_skip()
RETURNS TRIGGER AS $$
DECLARE
    v_round RECORD;
    v_chat RECORD;
    v_total_participants INTEGER;
    v_total_propositions INTEGER;
    v_total_ratings INTEGER;
    v_avg_raters_per_prop NUMERIC;
    v_required INTEGER;
    v_rating_skip_count INTEGER;
BEGIN
    -- Get round info
    SELECT r.*, c.chat_id
    INTO v_round
    FROM rounds r
    JOIN cycles c ON c.id = r.cycle_id
    WHERE r.id = NEW.round_id;

    -- Only check during rating phase
    IF v_round.phase != 'rating' THEN
        RETURN NEW;
    END IF;

    -- Get chat settings
    SELECT * INTO v_chat
    FROM chats
    WHERE id = v_round.chat_id;

    -- Skip if no thresholds configured
    IF v_chat.rating_threshold_percent IS NULL AND v_chat.rating_threshold_count IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip manual mode
    IF v_chat.start_mode = 'manual' THEN
        RETURN NEW;
    END IF;

    -- Count active participants
    SELECT COUNT(*) INTO v_total_participants
    FROM participants
    WHERE chat_id = v_round.chat_id AND status = 'active';

    IF v_total_participants = 0 THEN
        RETURN NEW;
    END IF;

    -- Count rating skips for this round (including the one just inserted)
    SELECT COUNT(*) INTO v_rating_skip_count
    FROM rating_skips
    WHERE round_id = NEW.round_id;

    -- Count total propositions in this round
    SELECT COUNT(*) INTO v_total_propositions
    FROM propositions
    WHERE round_id = NEW.round_id;

    IF v_total_propositions = 0 THEN
        RETURN NEW;
    END IF;

    -- Count total ratings in this round
    SELECT COUNT(*) INTO v_total_ratings
    FROM grid_rankings gr
    JOIN propositions p ON p.id = gr.proposition_id
    WHERE p.round_id = NEW.round_id;

    -- Calculate average raters per proposition
    v_avg_raters_per_prop := v_total_ratings::NUMERIC / v_total_propositions::NUMERIC;

    -- Calculate required threshold
    v_required := calculate_early_advance_required(
        v_chat.rating_threshold_percent,
        v_chat.rating_threshold_count,
        v_total_participants
    );

    -- Cap at participants - 1 - rating_skippers
    IF v_required IS NOT NULL AND v_total_participants > 1 THEN
        v_required := LEAST(v_required, v_total_participants - 1 - v_rating_skip_count);
        IF v_required < 1 THEN
            v_required := 1;
        END IF;
    END IF;

    -- Check if average raters per proposition meets threshold
    IF v_required IS NOT NULL AND v_avg_raters_per_prop >= v_required THEN
        RAISE NOTICE '[EARLY ADVANCE] Rating skip triggered advance (avg %.2f raters/prop >= %, % skips). Completing round %.',
            v_avg_raters_per_prop, v_required, v_rating_skip_count, NEW.round_id;

        -- Complete the round with winner calculation
        PERFORM complete_round_with_winner(NEW.round_id);

        -- Apply adaptive duration for next round (if enabled)
        PERFORM apply_adaptive_duration(NEW.round_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for rating skip early advance
CREATE TRIGGER check_early_advance_on_rating_skip_trigger
    AFTER INSERT ON rating_skips
    FOR EACH ROW
    EXECUTE FUNCTION check_early_advance_on_rating_skip();
