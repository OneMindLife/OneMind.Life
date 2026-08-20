-- =============================================================================
-- Test: SEO content RPCs (Joel, 2026-07-15).
-- Migrations: 20260714162005_seo_content_rpcs.sql
--             20260715140124_seo_chat_answer_first_ranked.sql
--             20260715140734_seo_human_only.sql
--   get_seo_chat: MAIN-FLOOR (root cycle) opinions, ranked best-first by
--     global_score, carrying the score. Excludes AI (display_name='AI') and
--     seat-fill bots (agent_role<>'off'), carried-forward dupes, sub-thread
--     (child-cycle) opinions, and unscored takes sort last.
--   get_seo_index: official public chats with >=5 HUMAN opinions.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(7);

SELECT has_function('get_seo_chat', 'get_seo_chat exists');
SELECT has_function('get_seo_index', 'get_seo_index exists');

-- Only one chat may be is_official at a time (idx_chats_single_official). Clear
-- any existing official flag inside this rolled-back tx so the fixture can own it.
UPDATE chats SET is_official = false WHERE is_official = true;

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode,
                   is_official, access_method, invite_code)
VALUES ('SEO Rank Test', '', gen_random_uuid(), 'matches', true, 'public', 'SEOTST');

DO $$
DECLARE
  ch INT; root_cyc INT; child_cyc INT; root_r INT; child_r INT;
  h1 INT; h2 INT; h3 INT; h4 INT; ai INT; bot INT;
  pHi INT; pMid INT; pLo INT; pUnscored INT; pAI INT; pBot INT; pChild INT;
BEGIN
  SELECT id INTO ch FROM chats WHERE invite_code = 'SEOTST';

  INSERT INTO cycles (chat_id) VALUES (ch) RETURNING id INTO root_cyc;  -- parent_proposition_id NULL = main floor
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (root_cyc, 1, 'rating') RETURNING id INTO root_r;

  -- One new proposition per participant per round (idx_propositions_unique_new_per_round),
  -- so each main-floor take gets its own human author.
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H1', 'active') RETURNING id INTO h1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H2', 'active') RETURNING id INTO h2;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H3', 'active') RETURNING id INTO h3;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H4', 'active') RETURNING id INTO h4;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'AI', 'active') RETURNING id INTO ai;
  INSERT INTO participants (chat_id, session_token, display_name, status, agent_role) VALUES (ch, gen_random_uuid(), 'Seat 1', 'active', 'proposer') RETURNING id INTO bot;

  -- Main-floor human opinions (ranked by score) + one unscored.
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h1, 'best take') RETURNING id INTO pHi;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h2, 'mid take')  RETURNING id INTO pMid;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h3, 'low take')  RETURNING id INTO pLo;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h4, 'unscored take') RETURNING id INTO pUnscored;
  -- AI + bot takes with the HIGHEST scores — must still be excluded.
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, ai,  'ai take')  RETURNING id INTO pAI;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, bot, 'bot take') RETURNING id INTO pBot;
  -- Carried-forward human dupe (exempt from the unique-new index) — excluded from SEO.
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id) VALUES (root_r, h1, 'best take (carried)', pHi);

  -- A sub-thread (child cycle) human opinion — excluded (not the main floor).
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (ch, pHi) RETURNING id INTO child_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (child_cyc, 1, 'rating') RETURNING id INTO child_r;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (child_r, h1, 'sub-thread take') RETURNING id INTO pChild;

  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score) VALUES
    (pHi, root_r, 90), (pMid, root_r, 50), (pLo, root_r, 10),
    (pAI, root_r, 99), (pBot, root_r, 95), (pChild, child_r, 80);
END $$;

-- get_seo_index: 5 distinct human non-carried opinions (4 root + 1 child) → eligible.
SELECT ok(
  EXISTS (SELECT 1 FROM get_seo_index() WHERE code = 'SEOTST'),
  'chat with >=5 human opinions is SEO-eligible'
);

-- get_seo_chat: only the 4 main-floor HUMAN takes (AI/bot/carried/sub-thread excluded).
SELECT is(
  jsonb_array_length(get_seo_chat('SEOTST') -> 'opinions'),
  4,
  'only main-floor human opinions returned (AI, bot, carried, sub-thread excluded)'
);

-- Answer-first: #1 is the highest-scored HUMAN take, NOT the AI's higher score.
SELECT is(
  get_seo_chat('SEOTST') -> 'opinions' -> 0 ->> 'content',
  'best take',
  'top take is the highest-scored human opinion, not the AI take (score 99)'
);

-- Ranked best-first by score.
SELECT is(
  ARRAY(
    SELECT (o ->> 'content')
    FROM jsonb_array_elements(get_seo_chat('SEOTST') -> 'opinions') AS o
  ),
  ARRAY['best take','mid take','low take','unscored take'],
  'opinions ranked by score desc, unscored last'
);

-- The AI take never appears in the payload.
SELECT ok(
  NOT (get_seo_chat('SEOTST') #>> '{}' LIKE '%ai take%'),
  'AI-authored take is absent from the SEO content'
);

SELECT * FROM finish();
ROLLBACK;
