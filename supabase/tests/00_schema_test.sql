-- Schema tests for OneMind database
BEGIN;
SET search_path TO public, extensions;
SELECT plan(93);

-- =============================================================================
-- TABLE EXISTENCE TESTS
-- =============================================================================

SELECT has_table('public', 'users', 'users table exists');
SELECT has_table('public', 'chats', 'chats table exists');
SELECT has_table('public', 'cycles', 'cycles table exists');
SELECT has_table('public', 'rounds', 'rounds table exists');
SELECT has_table('public', 'propositions', 'propositions table exists');
SELECT has_table('public', 'ratings', 'ratings table exists');
SELECT has_table('public', 'participants', 'participants table exists');
SELECT has_table('public', 'join_requests', 'join_requests table exists');
SELECT has_table('public', 'invites', 'invites table exists');

-- =============================================================================
-- USERS TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'users', 'id', 'users.id exists');
SELECT has_column('public', 'users', 'email', 'users.email exists');
SELECT has_column('public', 'users', 'display_name', 'users.display_name exists');
SELECT has_column('public', 'users', 'avatar_url', 'users.avatar_url exists');
SELECT has_column('public', 'users', 'created_at', 'users.created_at exists');
SELECT has_column('public', 'users', 'last_seen_at', 'users.last_seen_at exists');

-- =============================================================================
-- CHATS TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'chats', 'id', 'chats.id exists');
SELECT has_column('public', 'chats', 'name', 'chats.name exists');
SELECT has_column('public', 'chats', 'initial_message', 'chats.initial_message exists');
SELECT has_column('public', 'chats', 'description', 'chats.description exists');
SELECT has_column('public', 'chats', 'invite_code', 'chats.invite_code exists');
SELECT has_column('public', 'chats', 'creator_id', 'chats.creator_id exists');
SELECT has_column('public', 'chats', 'creator_session_token', 'chats.creator_session_token exists');
SELECT has_column('public', 'chats', 'access_method', 'chats.access_method exists');
SELECT has_column('public', 'chats', 'require_auth', 'chats.require_auth exists');
SELECT has_column('public', 'chats', 'require_approval', 'chats.require_approval exists');
SELECT has_column('public', 'chats', 'is_active', 'chats.is_active exists');
SELECT has_column('public', 'chats', 'is_official', 'chats.is_official exists');
SELECT has_column('public', 'chats', 'expires_at', 'chats.expires_at exists');
SELECT has_column('public', 'chats', 'last_activity_at', 'chats.last_activity_at exists');
SELECT has_column('public', 'chats', 'created_at', 'chats.created_at exists');

-- Timer columns
SELECT has_column('public', 'chats', 'proposing_duration_seconds', 'chats.proposing_duration_seconds exists');
SELECT has_column('public', 'chats', 'rating_duration_seconds', 'chats.rating_duration_seconds exists');

-- Minimum columns
SELECT has_column('public', 'chats', 'proposing_minimum', 'chats.proposing_minimum exists');
SELECT has_column('public', 'chats', 'rating_minimum', 'chats.rating_minimum exists');

-- Threshold columns
SELECT has_column('public', 'chats', 'proposing_threshold_percent', 'chats.proposing_threshold_percent exists');
SELECT has_column('public', 'chats', 'proposing_threshold_count', 'chats.proposing_threshold_count exists');
SELECT has_column('public', 'chats', 'rating_threshold_percent', 'chats.rating_threshold_percent exists');
SELECT has_column('public', 'chats', 'rating_threshold_count', 'chats.rating_threshold_count exists');

-- Start mode columns
SELECT has_column('public', 'chats', 'start_mode', 'chats.start_mode exists');
SELECT has_column('public', 'chats', 'auto_start_participant_count', 'chats.auto_start_participant_count exists');

-- AI columns
SELECT has_column('public', 'chats', 'enable_ai_participant', 'chats.enable_ai_participant exists');
SELECT has_column('public', 'chats', 'ai_propositions_count', 'chats.ai_propositions_count exists');

-- Consensus settings columns
SELECT has_column('public', 'chats', 'confirmation_rounds_required', 'chats.confirmation_rounds_required exists');
SELECT has_column('public', 'chats', 'show_previous_results', 'chats.show_previous_results exists');

-- Proposition limit column
SELECT has_column('public', 'chats', 'propositions_per_user', 'chats.propositions_per_user exists');

-- =============================================================================
-- CYCLES TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'cycles', 'id', 'cycles.id exists');
SELECT has_column('public', 'cycles', 'chat_id', 'cycles.chat_id exists');
SELECT has_column('public', 'cycles', 'winning_proposition_id', 'cycles.winning_proposition_id exists');
SELECT has_column('public', 'cycles', 'completed_at', 'cycles.completed_at exists');
SELECT has_column('public', 'cycles', 'created_at', 'cycles.created_at exists');

-- =============================================================================
-- ROUNDS TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'rounds', 'id', 'rounds.id exists');
SELECT has_column('public', 'rounds', 'cycle_id', 'rounds.cycle_id exists');
SELECT has_column('public', 'rounds', 'custom_id', 'rounds.custom_id exists');
SELECT has_column('public', 'rounds', 'phase', 'rounds.phase exists');
SELECT has_column('public', 'rounds', 'phase_started_at', 'rounds.phase_started_at exists');
SELECT has_column('public', 'rounds', 'phase_ends_at', 'rounds.phase_ends_at exists');
SELECT has_column('public', 'rounds', 'winning_proposition_id', 'rounds.winning_proposition_id exists');
SELECT has_column('public', 'rounds', 'completed_at', 'rounds.completed_at exists');
SELECT has_column('public', 'rounds', 'created_at', 'rounds.created_at exists');

-- =============================================================================
-- PROPOSITIONS TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'propositions', 'id', 'propositions.id exists');
SELECT has_column('public', 'propositions', 'round_id', 'propositions.round_id exists');
SELECT has_column('public', 'propositions', 'participant_id', 'propositions.participant_id exists');
SELECT has_column('public', 'propositions', 'content', 'propositions.content exists');
SELECT has_column('public', 'propositions', 'created_at', 'propositions.created_at exists');

-- =============================================================================
-- RATINGS TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'ratings', 'id', 'ratings.id exists');
SELECT has_column('public', 'ratings', 'proposition_id', 'ratings.proposition_id exists');
SELECT has_column('public', 'ratings', 'participant_id', 'ratings.participant_id exists');
SELECT has_column('public', 'ratings', 'rating', 'ratings.rating exists');
SELECT has_column('public', 'ratings', 'created_at', 'ratings.created_at exists');

-- =============================================================================
-- PARTICIPANTS TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'participants', 'id', 'participants.id exists');
SELECT has_column('public', 'participants', 'chat_id', 'participants.chat_id exists');
SELECT has_column('public', 'participants', 'user_id', 'participants.user_id exists');
SELECT has_column('public', 'participants', 'session_token', 'participants.session_token exists');
SELECT has_column('public', 'participants', 'display_name', 'participants.display_name exists');
SELECT has_column('public', 'participants', 'is_host', 'participants.is_host exists');
SELECT has_column('public', 'participants', 'is_authenticated', 'participants.is_authenticated exists');
SELECT has_column('public', 'participants', 'status', 'participants.status exists');
SELECT has_column('public', 'participants', 'created_at', 'participants.created_at exists');

-- =============================================================================
-- JOIN_REQUESTS TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'join_requests', 'id', 'join_requests.id exists');
SELECT has_column('public', 'join_requests', 'chat_id', 'join_requests.chat_id exists');
SELECT has_column('public', 'join_requests', 'session_token', 'join_requests.session_token exists');
SELECT has_column('public', 'join_requests', 'display_name', 'join_requests.display_name exists');
SELECT has_column('public', 'join_requests', 'status', 'join_requests.status exists');
SELECT has_column('public', 'join_requests', 'created_at', 'join_requests.created_at exists');

-- =============================================================================
-- INVITES TABLE COLUMNS
-- =============================================================================

SELECT has_column('public', 'invites', 'id', 'invites.id exists');
SELECT has_column('public', 'invites', 'chat_id', 'invites.chat_id exists');
SELECT has_column('public', 'invites', 'email', 'invites.email exists');
SELECT has_column('public', 'invites', 'invite_token', 'invites.invite_token exists');
SELECT has_column('public', 'invites', 'invited_by', 'invites.invited_by exists');
SELECT has_column('public', 'invites', 'status', 'invites.status exists');
SELECT has_column('public', 'invites', 'expires_at', 'invites.expires_at exists');
SELECT has_column('public', 'invites', 'created_at', 'invites.created_at exists');

-- =============================================================================
-- RATE_LIMITS TABLE (Security feature)
-- =============================================================================

SELECT has_table('public', 'rate_limits', 'rate_limits table exists');

SELECT * FROM finish();
ROLLBACK;
