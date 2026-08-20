-- =============================================================================
-- Test: per-thread SEO pages RPCs (Joel, 2026-07-16).
-- Migration: 20260716010000_seo_node_thread_pages.sql
--   get_seo_node_index: sub-threads with a HUMAN parent + >=2 HUMAN replies in
--     eligible official public chats. Returns (code, node=parentPropId, parent
--     text, replies). Excludes AI/bot replies, carried-forward dupes, threads
--     with <2 human replies, and threads whose PARENT is AI/bot-authored.
--   get_seo_node: the parent opinion + its HUMAN replies ranked best-first by
--     global_score (unscored last), AI/bot/carried excluded.
-- Runs inside BEGIN/ROLLBACK; prod data untouched.
-- =============================================================================
BEGIN;
SET search_path TO public, extensions;
SELECT plan(11);

SELECT has_function('get_seo_node_index', 'get_seo_node_index exists');
SELECT has_function('get_seo_node', ARRAY['text','bigint'], 'get_seo_node(text,bigint) exists');

-- Only one chat may be is_official at a time (idx_chats_single_official).
UPDATE chats SET is_official = false WHERE is_official = true;

INSERT INTO chats (name, initial_message, creator_session_token, rating_mode,
                   is_official, access_method, invite_code)
VALUES ('SEO Node Test', '', gen_random_uuid(), 'matches', true, 'public', 'SEOND');

DO $$
DECLARE
  ch INT; root_cyc INT; root_r INT;
  cycA INT; rA INT; cycB INT; rB INT; cycC INT; rC INT;
  h1 INT; h2 INT; h3 INT; h4 INT; h5 INT; ai INT; bot INT;
  pParent INT; pThin INT; pAIparent INT;
  rHi INT; rMid INT; rUn INT; rAiChild INT; rBotChild INT;
BEGIN
  SELECT id INTO ch FROM chats WHERE invite_code = 'SEOND';

  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H1', 'active') RETURNING id INTO h1;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H2', 'active') RETURNING id INTO h2;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H3', 'active') RETURNING id INTO h3;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H4', 'active') RETURNING id INTO h4;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'H5', 'active') RETURNING id INTO h5;
  INSERT INTO participants (chat_id, session_token, display_name, status) VALUES (ch, gen_random_uuid(), 'AI', 'active') RETURNING id INTO ai;
  INSERT INTO participants (chat_id, session_token, display_name, status, agent_role) VALUES (ch, gen_random_uuid(), 'Seat 1', 'active', 'proposer') RETURNING id INTO bot;

  -- Root floor: three parent opinions (one new prop per participant per round).
  INSERT INTO cycles (chat_id) VALUES (ch) RETURNING id INTO root_cyc;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (root_cyc, 1, 'rating') RETURNING id INTO root_r;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h1, 'parent take')  RETURNING id INTO pParent;    -- human parent, rich thread
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, h2, 'thin parent')  RETURNING id INTO pThin;      -- human parent, only 1 reply
  INSERT INTO propositions (round_id, participant_id, content) VALUES (root_r, ai, 'ai parent')    RETURNING id INTO pAIparent;  -- AI parent, 2 replies (must NOT index)

  -- Thread A under the human parent: 3 human replies (+ AI, bot, carried noise).
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (ch, pParent) RETURNING id INTO cycA;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cycA, 1, 'rating') RETURNING id INTO rA;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rA, h3, 'reply hi')       RETURNING id INTO rHi;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rA, h4, 'reply mid')      RETURNING id INTO rMid;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rA, h5, 'reply unscored') RETURNING id INTO rUn;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rA, ai,  'reply ai')      RETURNING id INTO rAiChild;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rA, bot, 'reply bot')     RETURNING id INTO rBotChild;
  INSERT INTO propositions (round_id, participant_id, content, carried_from_id) VALUES (rA, h3, 'reply hi (carried)', rHi);

  -- Thread B under the thin human parent: only 1 human reply → not eligible.
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (ch, pThin) RETURNING id INTO cycB;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cycB, 1, 'rating') RETURNING id INTO rB;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rB, h3, 'lone reply');

  -- Thread C under the AI parent: 2 human replies, but parent is AI → not eligible.
  INSERT INTO cycles (chat_id, parent_proposition_id) VALUES (ch, pAIparent) RETURNING id INTO cycC;
  INSERT INTO rounds (cycle_id, custom_id, phase) VALUES (cycC, 1, 'rating') RETURNING id INTO rC;
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rC, h3, 'ai-parent reply 1');
  INSERT INTO propositions (round_id, participant_id, content) VALUES (rC, h4, 'ai-parent reply 2');

  -- Scores: AI/bot replies score HIGHEST — must still be excluded/outranked.
  INSERT INTO proposition_global_scores (proposition_id, round_id, global_score) VALUES
    (rHi, rA, 90), (rMid, rA, 50), (rAiChild, rA, 99), (rBotChild, rA, 95);
END $$;

-- Index: the human-parent thread with 3 human replies is listed, replies counted
-- (AI, bot, carried all excluded from the count).
SELECT is(
  (SELECT replies FROM get_seo_node_index()
     WHERE code = 'SEOND'
       AND node = (SELECT id FROM propositions WHERE content = 'parent take')),
  3::bigint,
  'human-parent thread listed with 3 human replies (AI/bot/carried excluded)'
);

-- Index carries the parent opinion text (the page headline / link label).
SELECT is(
  (SELECT parent FROM get_seo_node_index()
     WHERE node = (SELECT id FROM propositions WHERE content = 'parent take')),
  'parent take',
  'index returns the parent opinion text'
);

-- A thread with <2 human replies is excluded.
SELECT ok(
  NOT EXISTS (SELECT 1 FROM get_seo_node_index()
    WHERE node = (SELECT id FROM propositions WHERE content = 'thin parent')),
  'thread with only 1 human reply is excluded'
);

-- A thread whose PARENT is AI-authored is excluded (even with >=2 human replies).
SELECT ok(
  NOT EXISTS (SELECT 1 FROM get_seo_node_index()
    WHERE node = (SELECT id FROM propositions WHERE content = 'ai parent')),
  'thread under an AI-authored parent is excluded'
);

-- get_seo_node: exactly the 3 human replies (AI/bot/carried excluded).
SELECT is(
  jsonb_array_length(
    get_seo_node('SEOND', (SELECT id FROM propositions WHERE content = 'parent take')) -> 'opinions'),
  3,
  'node payload has only the 3 human replies'
);

-- Parent opinion surfaced as the page topic.
SELECT is(
  get_seo_node('SEOND', (SELECT id FROM propositions WHERE content = 'parent take')) ->> 'parent',
  'parent take',
  'node payload carries the parent opinion'
);

-- Answer-first: top reply is the highest-scored HUMAN reply, not the AI (score 99).
SELECT is(
  get_seo_node('SEOND', (SELECT id FROM propositions WHERE content = 'parent take'))
    -> 'opinions' -> 0 ->> 'content',
  'reply hi',
  'top reply is the highest-scored human reply, not the AI reply'
);

-- Ranked best-first by score, unscored last.
SELECT is(
  ARRAY(
    SELECT (o ->> 'content')
    FROM jsonb_array_elements(
      get_seo_node('SEOND', (SELECT id FROM propositions WHERE content = 'parent take')) -> 'opinions') AS o
  ),
  ARRAY['reply hi','reply mid','reply unscored'],
  'replies ranked by score desc, unscored last'
);

-- The AI reply never appears in the node payload.
SELECT ok(
  NOT (get_seo_node('SEOND', (SELECT id FROM propositions WHERE content = 'parent take')) #>> '{}' LIKE '%reply ai%'),
  'AI-authored reply is absent from the node content'
);

SELECT * FROM finish();
ROLLBACK;
