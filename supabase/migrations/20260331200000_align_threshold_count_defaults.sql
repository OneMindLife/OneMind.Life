-- =============================================================================
-- MIGRATION: Align threshold count defaults with app
-- =============================================================================
-- The Flutter app sends proposing_threshold_count=3 and rating_threshold_count=2
-- when creating chats, but the DB defaults were 5. Align DB defaults to match
-- the app so SQL-created chats behave the same.
-- =============================================================================

ALTER TABLE chats ALTER COLUMN proposing_threshold_count SET DEFAULT 3;
ALTER TABLE chats ALTER COLUMN rating_threshold_count SET DEFAULT 2;
