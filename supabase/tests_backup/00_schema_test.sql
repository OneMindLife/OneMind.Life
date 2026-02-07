-- Schema tests for OneMind database
BEGIN;
SET search_path TO public, extensions;
SELECT extensions.plan(85);

-- =============================================================================
-- TABLE EXISTENCE TESTS
-- =============================================================================

SELECT extensions.has_table('public', 'users', 'users table exists');
SELECT extensions.has_table('public', 'chats', 'chats table exists');
SELECT extensions.has_table('public', 'cycles', 'cycles table exists');
SELECT extensions.has_table('public', 'iterations', 'iterations table exists');
SELECT extensions.has_table('public', 'propositions', 'propositions table exists');
SELECT extensions.has_table('public', 'ratings', 'ratings table exists');
SELECT extensions.has_table('public', 'proposition_ratings', 'proposition_ratings table exists');
SELECT extensions.has_table('public', 'participants', 'participants table exists');
SELECT extensions.has_table('public', 'join_requests', 'join_requests table exists');
SELECT extensions.has_table('public', 'invites', 'invites table exists');

-- =============================================================================
-- USERS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'users', 'id', 'users.id exists');
SELECT extensions.has_column('public', 'users', 'email', 'users.email exists');
SELECT extensions.has_column('public', 'users', 'display_name', 'users.display_name exists');
SELECT extensions.has_column('public', 'users', 'avatar_url', 'users.avatar_url exists');
SELECT extensions.has_column('public', 'users', 'created_at', 'users.created_at exists');
SELECT extensions.has_column('public', 'users', 'last_seen_at', 'users.last_seen_at exists');

-- =============================================================================
-- CHATS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'chats', 'id', 'chats.id exists');
SELECT extensions.has_column('public', 'chats', 'name', 'chats.name exists');
SELECT extensions.has_column('public', 'chats', 'initial_message', 'chats.initial_message exists');
SELECT extensions.has_column('public', 'chats', 'description', 'chats.description exists');
SELECT extensions.has_column('public', 'chats', 'invite_code', 'chats.invite_code exists');
SELECT extensions.has_column('public', 'chats', 'creator_id', 'chats.creator_id exists');
SELECT extensions.has_column('public', 'chats', 'creator_session_token', 'chats.creator_session_token exists');
SELECT extensions.has_column('public', 'chats', 'access_method', 'chats.access_method exists');
SELECT extensions.has_column('public', 'chats', 'require_auth', 'chats.require_auth exists');
SELECT extensions.has_column('public', 'chats', 'require_approval', 'chats.require_approval exists');
SELECT extensions.has_column('public', 'chats', 'is_active', 'chats.is_active exists');
SELECT extensions.has_column('public', 'chats', 'is_official', 'chats.is_official exists');
SELECT extensions.has_column('public', 'chats', 'expires_at', 'chats.expires_at exists');
SELECT extensions.has_column('public', 'chats', 'last_activity_at', 'chats.last_activity_at exists');
SELECT extensions.has_column('public', 'chats', 'created_at', 'chats.created_at exists');

-- Timer columns
SELECT extensions.has_column('public', 'chats', 'proposing_duration_seconds', 'chats.proposing_duration_seconds exists');
SELECT extensions.has_column('public', 'chats', 'rating_duration_seconds', 'chats.rating_duration_seconds exists');

-- Minimum columns
SELECT extensions.has_column('public', 'chats', 'proposing_minimum', 'chats.proposing_minimum exists');
SELECT extensions.has_column('public', 'chats', 'rating_minimum', 'chats.rating_minimum exists');

-- Threshold columns
SELECT extensions.has_column('public', 'chats', 'proposing_threshold_percent', 'chats.proposing_threshold_percent exists');
SELECT extensions.has_column('public', 'chats', 'proposing_threshold_count', 'chats.proposing_threshold_count exists');
SELECT extensions.has_column('public', 'chats', 'rating_threshold_percent', 'chats.rating_threshold_percent exists');
SELECT extensions.has_column('public', 'chats', 'rating_threshold_count', 'chats.rating_threshold_count exists');

-- Start mode columns
SELECT extensions.has_column('public', 'chats', 'start_mode', 'chats.start_mode exists');
SELECT extensions.has_column('public', 'chats', 'auto_start_participant_count', 'chats.auto_start_participant_count exists');

-- AI columns
SELECT extensions.has_column('public', 'chats', 'enable_ai_participant', 'chats.enable_ai_participant exists');
SELECT extensions.has_column('public', 'chats', 'ai_propositions_count', 'chats.ai_propositions_count exists');

-- =============================================================================
-- CYCLES TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'cycles', 'id', 'cycles.id exists');
SELECT extensions.has_column('public', 'cycles', 'chat_id', 'cycles.chat_id exists');
SELECT extensions.has_column('public', 'cycles', 'custom_id', 'cycles.custom_id exists');
SELECT extensions.has_column('public', 'cycles', 'winner_proposition_id', 'cycles.winner_proposition_id exists');
SELECT extensions.has_column('public', 'cycles', 'created_at', 'cycles.created_at exists');

-- =============================================================================
-- ITERATIONS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'iterations', 'id', 'iterations.id exists');
SELECT extensions.has_column('public', 'iterations', 'cycle_id', 'iterations.cycle_id exists');
SELECT extensions.has_column('public', 'iterations', 'custom_id', 'iterations.custom_id exists');
SELECT extensions.has_column('public', 'iterations', 'phase', 'iterations.phase exists');
SELECT extensions.has_column('public', 'iterations', 'phase_started_at', 'iterations.phase_started_at exists');
SELECT extensions.has_column('public', 'iterations', 'winner_proposition_id', 'iterations.winner_proposition_id exists');
SELECT extensions.has_column('public', 'iterations', 'created_at', 'iterations.created_at exists');

-- =============================================================================
-- PROPOSITIONS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'propositions', 'id', 'propositions.id exists');
SELECT extensions.has_column('public', 'propositions', 'iteration_id', 'propositions.iteration_id exists');
SELECT extensions.has_column('public', 'propositions', 'participant_id', 'propositions.participant_id exists');
SELECT extensions.has_column('public', 'propositions', 'content', 'propositions.content exists');
SELECT extensions.has_column('public', 'propositions', 'created_at', 'propositions.created_at exists');

-- =============================================================================
-- RATINGS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'ratings', 'id', 'ratings.id exists');
SELECT extensions.has_column('public', 'ratings', 'proposition_id', 'ratings.proposition_id exists');
SELECT extensions.has_column('public', 'ratings', 'participant_id', 'ratings.participant_id exists');
SELECT extensions.has_column('public', 'ratings', 'rating', 'ratings.rating exists');
SELECT extensions.has_column('public', 'ratings', 'created_at', 'ratings.created_at exists');

-- =============================================================================
-- PROPOSITION_RATINGS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'proposition_ratings', 'id', 'proposition_ratings.id exists');
SELECT extensions.has_column('public', 'proposition_ratings', 'proposition_id', 'proposition_ratings.proposition_id exists');
SELECT extensions.has_column('public', 'proposition_ratings', 'rating', 'proposition_ratings.rating exists');
SELECT extensions.has_column('public', 'proposition_ratings', 'created_at', 'proposition_ratings.created_at exists');

-- =============================================================================
-- PARTICIPANTS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'participants', 'id', 'participants.id exists');
SELECT extensions.has_column('public', 'participants', 'chat_id', 'participants.chat_id exists');
SELECT extensions.has_column('public', 'participants', 'user_id', 'participants.user_id exists');
SELECT extensions.has_column('public', 'participants', 'session_token', 'participants.session_token exists');
SELECT extensions.has_column('public', 'participants', 'display_name', 'participants.display_name exists');
SELECT extensions.has_column('public', 'participants', 'is_host', 'participants.is_host exists');
SELECT extensions.has_column('public', 'participants', 'is_authenticated', 'participants.is_authenticated exists');
SELECT extensions.has_column('public', 'participants', 'status', 'participants.status exists');
SELECT extensions.has_column('public', 'participants', 'created_at', 'participants.created_at exists');

-- =============================================================================
-- JOIN_REQUESTS TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'join_requests', 'id', 'join_requests.id exists');
SELECT extensions.has_column('public', 'join_requests', 'chat_id', 'join_requests.chat_id exists');
SELECT extensions.has_column('public', 'join_requests', 'session_token', 'join_requests.session_token exists');
SELECT extensions.has_column('public', 'join_requests', 'display_name', 'join_requests.display_name exists');
SELECT extensions.has_column('public', 'join_requests', 'status', 'join_requests.status exists');
SELECT extensions.has_column('public', 'join_requests', 'created_at', 'join_requests.created_at exists');

-- =============================================================================
-- INVITES TABLE COLUMNS
-- =============================================================================

SELECT extensions.has_column('public', 'invites', 'id', 'invites.id exists');
SELECT extensions.has_column('public', 'invites', 'chat_id', 'invites.chat_id exists');
SELECT extensions.has_column('public', 'invites', 'email', 'invites.email exists');
SELECT extensions.has_column('public', 'invites', 'invite_token', 'invites.invite_token exists');
SELECT extensions.has_column('public', 'invites', 'invited_by', 'invites.invited_by exists');
SELECT extensions.has_column('public', 'invites', 'status', 'invites.status exists');
SELECT extensions.has_column('public', 'invites', 'expires_at', 'invites.expires_at exists');
SELECT extensions.has_column('public', 'invites', 'created_at', 'invites.created_at exists');

SELECT * FROM finish();
ROLLBACK;
