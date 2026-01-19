import {
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  calculateRequiredCount,
  shouldAutoAdvance,
  explainThreshold,
  ThresholdConfig,
  ParticipationData,
} from "./auto-advance.ts";

// =============================================================================
// calculateRequiredCount Tests
// =============================================================================

Deno.test("calculateRequiredCount - both null returns null (disabled)", () => {
  const config: ThresholdConfig = {
    thresholdPercent: null,
    thresholdCount: null,
  };
  const result = calculateRequiredCount(config, 10);
  assertStrictEquals(result, null);
});

Deno.test("calculateRequiredCount - only percent set", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: null,
  };
  // 80% of 10 = 8
  assertEquals(calculateRequiredCount(config, 10), 8);
});

Deno.test("calculateRequiredCount - only count set", () => {
  const config: ThresholdConfig = {
    thresholdPercent: null,
    thresholdCount: 5,
  };
  assertEquals(calculateRequiredCount(config, 10), 5);
});

Deno.test("calculateRequiredCount - MAX: percent wins when higher", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };
  // 80% of 10 = 8, count = 5, MAX = 8
  assertEquals(calculateRequiredCount(config, 10), 8);
});

Deno.test("calculateRequiredCount - MAX: count wins when higher", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };
  // 80% of 4 = 3.2 -> ceil = 4, count = 5, MAX = 5
  assertEquals(calculateRequiredCount(config, 4), 5);
});

Deno.test("calculateRequiredCount - percent rounds up", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: null,
  };
  // 80% of 3 = 2.4 -> ceil = 3
  assertEquals(calculateRequiredCount(config, 3), 3);
});

Deno.test("calculateRequiredCount - 100% requires everyone", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 100,
    thresholdCount: null,
  };
  assertEquals(calculateRequiredCount(config, 10), 10);
});

Deno.test("calculateRequiredCount - 0 participants", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };
  // 80% of 0 = 0, count = 5, MAX = 5
  assertEquals(calculateRequiredCount(config, 0), 5);
});

Deno.test("calculateRequiredCount - count higher than participants (impossible threshold)", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 20,
  };
  // 80% of 10 = 8, count = 20, MAX = 20 (impossible to meet!)
  assertEquals(calculateRequiredCount(config, 10), 20);
});

// =============================================================================
// shouldAutoAdvance Tests
// =============================================================================

Deno.test("shouldAutoAdvance - disabled when both null", () => {
  const config: ThresholdConfig = {
    thresholdPercent: null,
    thresholdCount: null,
  };
  const data: ParticipationData = {
    totalParticipants: 10,
    participatedCount: 10,
  };
  // Even with 100% participation, should not advance if disabled
  assertStrictEquals(shouldAutoAdvance(config, data), false);
});

Deno.test("shouldAutoAdvance - true when threshold met", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };
  const data: ParticipationData = {
    totalParticipants: 10,
    participatedCount: 8, // 80% of 10, meets MAX(8, 5)
  };
  assertStrictEquals(shouldAutoAdvance(config, data), true);
});

Deno.test("shouldAutoAdvance - false when threshold not met", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };
  const data: ParticipationData = {
    totalParticipants: 10,
    participatedCount: 7, // Below MAX(8, 5) = 8
  };
  assertStrictEquals(shouldAutoAdvance(config, data), false);
});

Deno.test("shouldAutoAdvance - exactly at threshold", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 50,
    thresholdCount: null,
  };
  const data: ParticipationData = {
    totalParticipants: 10,
    participatedCount: 5, // Exactly 50%
  };
  assertStrictEquals(shouldAutoAdvance(config, data), true);
});

Deno.test("shouldAutoAdvance - over threshold", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 50,
    thresholdCount: null,
  };
  const data: ParticipationData = {
    totalParticipants: 10,
    participatedCount: 8, // 80% > 50%
  };
  assertStrictEquals(shouldAutoAdvance(config, data), true);
});

Deno.test("shouldAutoAdvance - impossible threshold never met", () => {
  const config: ThresholdConfig = {
    thresholdPercent: null,
    thresholdCount: 100, // More than total participants
  };
  const data: ParticipationData = {
    totalParticipants: 10,
    participatedCount: 10, // Everyone participated
  };
  // Required = 100, but only 10 people exist
  assertStrictEquals(shouldAutoAdvance(config, data), false);
});

Deno.test("shouldAutoAdvance - small group with high count threshold", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };
  const data: ParticipationData = {
    totalParticipants: 3,
    participatedCount: 3, // 100% of small group
  };
  // 80% of 3 = 2.4 -> 3, count = 5, MAX = 5
  // Only 3 people exist, can't meet 5
  assertStrictEquals(shouldAutoAdvance(config, data), false);
});

Deno.test("shouldAutoAdvance - small group where percent wins", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 2,
  };
  const data: ParticipationData = {
    totalParticipants: 3,
    participatedCount: 3,
  };
  // 80% of 3 = 2.4 -> 3, count = 2, MAX = 3
  // 3 >= 3, should advance
  assertStrictEquals(shouldAutoAdvance(config, data), true);
});

// =============================================================================
// explainThreshold Tests
// =============================================================================

Deno.test("explainThreshold - disabled", () => {
  const config: ThresholdConfig = {
    thresholdPercent: null,
    thresholdCount: null,
  };
  const result = explainThreshold(config, 10);
  assertEquals(result, "Auto-advance disabled (no thresholds set)");
});

Deno.test("explainThreshold - only percent", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: null,
  };
  const result = explainThreshold(config, 10);
  assertEquals(result, "MAX(80% of 10 = 8) = 8 required");
});

Deno.test("explainThreshold - only count", () => {
  const config: ThresholdConfig = {
    thresholdPercent: null,
    thresholdCount: 5,
  };
  const result = explainThreshold(config, 10);
  assertEquals(result, "MAX(count threshold = 5) = 5 required");
});

Deno.test("explainThreshold - both set", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };
  const result = explainThreshold(config, 10);
  assertEquals(result, "MAX(80% of 10 = 8, count threshold = 5) = 8 required");
});

// =============================================================================
// Real-World Scenario Tests
// =============================================================================

Deno.test("Scenario: Team standup (10 people, want 80% or 5 min)", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };

  // Day 1: 6 people present
  assertEquals(
    shouldAutoAdvance(config, { totalParticipants: 6, participatedCount: 5 }),
    true, // MAX(4.8->5, 5) = 5, met
    "6 people, 5 participated"
  );

  // Day 2: 10 people present
  assertEquals(
    shouldAutoAdvance(config, { totalParticipants: 10, participatedCount: 5 }),
    false, // MAX(8, 5) = 8, not met
    "10 people, only 5 participated"
  );

  assertEquals(
    shouldAutoAdvance(config, { totalParticipants: 10, participatedCount: 8 }),
    true, // MAX(8, 5) = 8, met
    "10 people, 8 participated"
  );
});

Deno.test("Scenario: Large public chat (100 people)", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 50,
    thresholdCount: 10,
  };

  // 50% of 100 = 50, count = 10, MAX = 50
  assertEquals(
    shouldAutoAdvance(config, { totalParticipants: 100, participatedCount: 49 }),
    false,
    "100 people, 49 participated (just under 50%)"
  );

  assertEquals(
    shouldAutoAdvance(config, { totalParticipants: 100, participatedCount: 50 }),
    true,
    "100 people, 50 participated (exactly 50%)"
  );
});

Deno.test("Scenario: Small private chat (3 people)", () => {
  const config: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 5,
  };

  // 80% of 3 = 2.4 -> 3, count = 5, MAX = 5
  // Can never meet 5 with only 3 people!
  assertEquals(
    shouldAutoAdvance(config, { totalParticipants: 3, participatedCount: 3 }),
    false,
    "3 people, all participated but count=5 is impossible"
  );

  // With more reasonable count threshold
  const betterConfig: ThresholdConfig = {
    thresholdPercent: 80,
    thresholdCount: 2,
  };
  // 80% of 3 = 2.4 -> 3, count = 2, MAX = 3
  assertEquals(
    shouldAutoAdvance(betterConfig, { totalParticipants: 3, participatedCount: 3 }),
    true,
    "3 people with reasonable count=2, all participated"
  );
});
