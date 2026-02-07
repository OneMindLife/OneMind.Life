-- Add cleanup-inactive-chats cron job and helper function
-- This runs weekly to delete chats with no activity for 7+ days

-- =============================================================================
-- FIND INACTIVE CHATS FUNCTION
-- =============================================================================
-- Returns chats that have had no activity for the specified number of days.
-- Activity is defined as: propositions, ratings, or participant joins.
-- Chats younger than the threshold are never returned.

CREATE OR REPLACE FUNCTION find_inactive_chats(p_inactive_days INT DEFAULT 7)
RETURNS TABLE (
  id BIGINT,
  name TEXT,
  created_at TIMESTAMPTZ,
  last_activity TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  cutoff_date TIMESTAMPTZ := NOW() - (p_inactive_days || ' days')::INTERVAL;
BEGIN
  RETURN QUERY
  WITH chat_proposition_activity AS (
    -- Most recent proposition per chat
    SELECT DISTINCT ON (cy.chat_id)
      cy.chat_id,
      p.created_at AS last_proposition
    FROM propositions p
    JOIN rounds r ON r.id = p.round_id
    JOIN cycles cy ON cy.id = r.cycle_id
    ORDER BY cy.chat_id, p.created_at DESC
  ),
  chat_rating_activity AS (
    -- Most recent rating per chat
    SELECT DISTINCT ON (cy.chat_id)
      cy.chat_id,
      rt.created_at AS last_rating
    FROM ratings rt
    JOIN propositions p ON p.id = rt.proposition_id
    JOIN rounds r ON r.id = p.round_id
    JOIN cycles cy ON cy.id = r.cycle_id
    ORDER BY cy.chat_id, rt.created_at DESC
  ),
  chat_participant_activity AS (
    -- Most recent participant join per chat
    SELECT DISTINCT ON (pt.chat_id)
      pt.chat_id,
      pt.created_at AS last_participant
    FROM participants pt
    ORDER BY pt.chat_id, pt.created_at DESC
  ),
  chat_activity AS (
    -- Combine all activity types, take the most recent
    SELECT
      c.id AS chat_id,
      c.name,
      c.created_at,
      GREATEST(
        COALESCE(cpa.last_proposition, '1970-01-01'::TIMESTAMPTZ),
        COALESCE(cra.last_rating, '1970-01-01'::TIMESTAMPTZ),
        COALESCE(cpra.last_participant, '1970-01-01'::TIMESTAMPTZ)
      ) AS last_activity
    FROM chats c
    LEFT JOIN chat_proposition_activity cpa ON cpa.chat_id = c.id
    LEFT JOIN chat_rating_activity cra ON cra.chat_id = c.id
    LEFT JOIN chat_participant_activity cpra ON cpra.chat_id = c.id
    WHERE c.created_at < cutoff_date  -- Only consider chats older than threshold
  )
  SELECT
    ca.chat_id,
    ca.name,
    ca.created_at,
    CASE
      WHEN ca.last_activity = '1970-01-01'::TIMESTAMPTZ THEN NULL
      ELSE ca.last_activity
    END
  FROM chat_activity ca
  WHERE ca.last_activity < cutoff_date  -- No activity within threshold
  ORDER BY ca.last_activity ASC NULLS FIRST;
END;
$$;

-- Grant execute to service role (Edge Functions use service role)
GRANT EXECUTE ON FUNCTION find_inactive_chats(INT) TO service_role;

-- =============================================================================
-- CRON JOB: Weekly cleanup
-- =============================================================================
-- Runs every Sunday at 3:00 AM UTC
-- Uses dry_run: false to actually delete (change to true for testing)

SELECT cron.schedule(
    'cleanup-inactive-chats',
    '0 3 * * 0',  -- Every Sunday at 3:00 AM UTC
    $$
    SELECT extensions.http_post(
        'https://ccyuxrtrklgpkzcryzpj.supabase.co/functions/v1/cleanup-inactive-chats',
        '{"dry_run": false}',
        'application/json'
    );
    $$
);

-- Add comment for documentation
COMMENT ON FUNCTION find_inactive_chats(INT) IS
'Finds chats with no activity (propositions, ratings, participant joins) for the specified number of days.
Used by cleanup-inactive-chats Edge Function to identify chats for deletion.';
