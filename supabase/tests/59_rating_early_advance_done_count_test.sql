-- Test: Rating early advance uses per-proposition model
-- Verifies that trigger functions use the per-proposition approach:
--   threshold = min(10, max(active_raters - 1, 1))
--   advance when min(ratings per proposition) >= threshold

BEGIN;
SELECT plan(6);

-- ============================================================
-- Test 1: Function exists
-- ============================================================
SELECT has_function('check_early_advance_on_rating');

-- ============================================================
-- Test 2: Function source contains per-proposition min check
-- ============================================================
SELECT matches(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating'),
    'v_min_ratings',
    'check_early_advance_on_rating uses per-proposition min_ratings approach'
);

-- ============================================================
-- Test 3: Function source does NOT contain old avg_raters_per_prop
-- ============================================================
SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating')
    NOT LIKE '%avg_raters_per_prop%',
    'check_early_advance_on_rating does not use avg_raters_per_prop'
);

-- ============================================================
-- Test 4: Function source does NOT contain old done_count user model
-- ============================================================
SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating')
    NOT LIKE '%v_done_count%',
    'check_early_advance_on_rating does not use done_count user model'
);

-- ============================================================
-- Test 5: Skip trigger also uses per-proposition min check
-- ============================================================
SELECT matches(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating_skip'),
    'v_min_ratings',
    'check_early_advance_on_rating_skip uses per-proposition min_ratings approach'
);

-- ============================================================
-- Test 6: Skip trigger does NOT use old avg_raters_per_prop
-- ============================================================
SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating_skip')
    NOT LIKE '%avg_raters_per_prop%',
    'check_early_advance_on_rating_skip does not use avg_raters_per_prop'
);

SELECT * FROM finish();
ROLLBACK;
