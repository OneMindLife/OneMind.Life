-- Test: Rating early advance uses "done participant" count instead of avg raters per prop
-- This ensures the fix for uneven proposition counts works correctly.

BEGIN;
SELECT plan(6);

-- ============================================================
-- Test 1: Function exists with updated logic (uses done_count not avg)
-- ============================================================
SELECT has_function('check_early_advance_on_rating');

-- ============================================================
-- Test 2: Function source contains "done_count" (new approach)
-- ============================================================
SELECT matches(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating'),
    'v_done_count',
    'check_early_advance_on_rating uses done_count approach'
);

-- ============================================================
-- Test 3: Function source does NOT contain avg_raters_per_prop (old approach removed)
-- ============================================================
SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating')
    NOT LIKE '%avg_raters_per_prop%',
    'check_early_advance_on_rating does not use avg_raters_per_prop'
);

-- ============================================================
-- Test 4: Function checks for rating_skips (skip support)
-- ============================================================
SELECT matches(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating'),
    'rating_skips',
    'check_early_advance_on_rating checks rating_skips table'
);

-- ============================================================
-- Test 5: Skip trigger function also uses done_count
-- ============================================================
SELECT matches(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating_skip'),
    'v_done_count',
    'check_early_advance_on_rating_skip uses done_count approach'
);

-- ============================================================
-- Test 6: Skip trigger function does NOT use avg_raters_per_prop
-- ============================================================
SELECT ok(
    (SELECT prosrc FROM pg_proc WHERE proname = 'check_early_advance_on_rating_skip')
    NOT LIKE '%avg_raters_per_prop%',
    'check_early_advance_on_rating_skip does not use avg_raters_per_prop'
);

SELECT * FROM finish();
ROLLBACK;
