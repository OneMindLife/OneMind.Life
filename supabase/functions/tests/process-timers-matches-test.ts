// Edge Function Test: process-timers matches-mode advance logic
//
// Run with: deno test --allow-all supabase/functions/tests/process-timers-matches-test.ts
//
// Covers the PURE decision helpers used by process-timers for matches (pairwise)
// rating rounds (extracted to ../_shared/matches-advance.ts so they're testable
// without importing index.ts, which calls Deno.serve at load). The DB-backed
// counting (get_matches_rating_progress RPC) is covered by pgtap test 111.

import {
  assertEquals,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";
import {
  autoAdvanceGateOpen,
  distinctRaterCount,
  matchesTimerMinimumMet,
  shouldEarlyAdvanceMatches,
} from "../_shared/matches-advance.ts";

// ---------------------------------------------------------------------------
// distinctRaterCount — done = unique participants across completions/grid/skips
// ---------------------------------------------------------------------------
Deno.test("distinctRaterCount: unions across the three sources", () => {
  const completions = [{ participant_id: 1 }];
  const grid = [{ participant_id: 2 }];
  const skips = [{ participant_id: 3 }];
  assertEquals(distinctRaterCount(completions, grid, skips), 3);
});

Deno.test("distinctRaterCount: a participant in two sources counts once", () => {
  const completions = [{ participant_id: 1 }];
  const grid = [{ participant_id: 1 }]; // same rater, also has grid coverage
  const skips: { participant_id: number | null }[] = [];
  assertEquals(distinctRaterCount(completions, grid, skips), 1);
});

Deno.test("distinctRaterCount: ignores null participant_ids", () => {
  const completions = [{ participant_id: null }, { participant_id: 5 }];
  assertEquals(distinctRaterCount(completions, [], []), 1);
});

Deno.test("distinctRaterCount: empty -> 0", () => {
  assertEquals(distinctRaterCount([], [], []), 0);
});

// ---------------------------------------------------------------------------
// shouldEarlyAdvanceMatches — advance once every eligible rater is done
// ---------------------------------------------------------------------------
Deno.test("shouldEarlyAdvanceMatches: all done -> true", () => {
  assertEquals(shouldEarlyAdvanceMatches(3, 3), true);
});

Deno.test("shouldEarlyAdvanceMatches: not everyone done -> false", () => {
  assertEquals(shouldEarlyAdvanceMatches(2, 3), false);
});

Deno.test("shouldEarlyAdvanceMatches: zero eligible -> false (no advance)", () => {
  assertEquals(shouldEarlyAdvanceMatches(0, 0), false);
});

// ---------------------------------------------------------------------------
// matchesTimerMinimumMet — at timer expiry, advance if anyone finished
// ---------------------------------------------------------------------------
Deno.test("matchesTimerMinimumMet: at least one done -> true", () => {
  assertEquals(matchesTimerMinimumMet(1), true);
});

Deno.test("matchesTimerMinimumMet: nobody done -> false (extend)", () => {
  assertEquals(matchesTimerMinimumMet(0), false);
});

// ---------------------------------------------------------------------------
// autoAdvanceGateOpen — matches rating HONORS the auto-advance toggle (same as
// grid). Toggle OFF (no thresholds) => gate closed => timer-paced. This is the
// "make the toggle real" behavior; previously matches bypassed the skip.
// ---------------------------------------------------------------------------
Deno.test("autoAdvanceGateOpen: matches rating with no thresholds is skipped (toggle honored)", () => {
  assertEquals(
    autoAdvanceGateOpen({
      isProposing: false,
      ratingMode: "matches",
      thresholdPercent: null,
      thresholdCount: null,
    }),
    false,
  );
});

Deno.test("autoAdvanceGateOpen: matches rating WITH thresholds opens the gate", () => {
  assertEquals(
    autoAdvanceGateOpen({
      isProposing: false,
      ratingMode: "matches",
      thresholdPercent: 100,
      thresholdCount: 2,
    }),
    true,
  );
});

Deno.test("autoAdvanceGateOpen: grid rating with no thresholds is skipped", () => {
  assertEquals(
    autoAdvanceGateOpen({
      isProposing: false,
      ratingMode: "grid",
      thresholdPercent: null,
      thresholdCount: null,
    }),
    false,
  );
});

Deno.test("autoAdvanceGateOpen: proposing (matches chat) with no thresholds is skipped", () => {
  // The matches exception is rating-only; proposing follows the normal rule.
  assertEquals(
    autoAdvanceGateOpen({
      isProposing: true,
      ratingMode: "matches",
      thresholdPercent: null,
      thresholdCount: null,
    }),
    false,
  );
});

Deno.test("autoAdvanceGateOpen: configured thresholds open the gate (any mode)", () => {
  assertEquals(
    autoAdvanceGateOpen({
      isProposing: false,
      ratingMode: "grid",
      thresholdPercent: 100,
      thresholdCount: null,
    }),
    true,
  );
});
