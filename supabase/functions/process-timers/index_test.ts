// Edge Function Tests: process-timers
// Run with: deno test --allow-env supabase/functions/process-timers/index_test.ts

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

// =============================================================================
// MOCK SUPABASE CLIENT
// =============================================================================

interface MockQueryResult {
  data: any;
  error: any;
  count?: number;
}

class MockSupabaseQueryBuilder {
  private result: MockQueryResult;

  constructor(result: MockQueryResult) {
    this.result = result;
  }

  select(_columns?: string, _options?: any): MockSupabaseQueryBuilder {
    return this;
  }

  insert(data: any): MockSupabaseQueryBuilder {
    // Store for verification
    (this as any)._insertedData = data;
    return this;
  }

  update(data: any): MockSupabaseQueryBuilder {
    (this as any)._updatedData = data;
    return this;
  }

  eq(_column: string, _value: any): MockSupabaseQueryBuilder {
    return this;
  }

  in(_column: string, _values: any[]): MockSupabaseQueryBuilder {
    return this;
  }

  not(_column: string, _operator: string, _value: any): MockSupabaseQueryBuilder {
    return this;
  }

  lt(_column: string, _value: any): MockSupabaseQueryBuilder {
    return this;
  }

  gt(_column: string, _value: any): MockSupabaseQueryBuilder {
    return this;
  }

  is(_column: string, _value: any): MockSupabaseQueryBuilder {
    return this;
  }

  order(_column: string, _options?: any): MockSupabaseQueryBuilder {
    return this;
  }

  then(resolve: (value: MockQueryResult) => void) {
    resolve(this.result);
  }
}

function createMockSupabase(responses: Record<string, MockQueryResult>) {
  return {
    from: (table: string) => new MockSupabaseQueryBuilder(
      responses[table] || { data: [], error: null }
    ),
    rpc: (_fn: string, _params: any) => Promise.resolve(
      responses['rpc'] || { data: null, error: null }
    ),
  };
}

// =============================================================================
// TEST: TIED WINNERS DETECTION LOGIC
// =============================================================================

Deno.test("Tied Winners Detection - identifies exact ties", () => {
  const scores = [
    { proposition_id: 1, global_score: 75.0 },
    { proposition_id: 2, global_score: 75.0 },
    { proposition_id: 3, global_score: 50.0 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  assertEquals(tiedWinners.length, 2);
  assertEquals(tiedWinners[0].proposition_id, 1);
  assertEquals(tiedWinners[1].proposition_id, 2);
});

Deno.test("Tied Winners Detection - identifies sole winner", () => {
  const scores = [
    { proposition_id: 1, global_score: 85.0 },
    { proposition_id: 2, global_score: 75.0 },
    { proposition_id: 3, global_score: 50.0 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  assertEquals(tiedWinners.length, 1);
  assertEquals(tiedWinners[0].proposition_id, 1);
});

Deno.test("Tied Winners Detection - three-way tie", () => {
  const scores = [
    { proposition_id: 1, global_score: 50.0 },
    { proposition_id: 2, global_score: 50.0 },
    { proposition_id: 3, global_score: 50.0 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  assertEquals(tiedWinners.length, 3);
});

Deno.test("Tied Winners Detection - near-tie within tolerance", () => {
  const scores = [
    { proposition_id: 1, global_score: 75.0005 },
    { proposition_id: 2, global_score: 75.0 },
    { proposition_id: 3, global_score: 74.9 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  // 75.0005 and 75.0 are within 0.001 tolerance
  assertEquals(tiedWinners.length, 2);
});

Deno.test("Tied Winners Detection - near-tie outside tolerance", () => {
  const scores = [
    { proposition_id: 1, global_score: 75.002 },
    { proposition_id: 2, global_score: 75.0 },
    { proposition_id: 3, global_score: 74.9 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  // 75.002 and 75.0 are NOT within 0.001 tolerance (diff = 0.002)
  assertEquals(tiedWinners.length, 1);
});

// =============================================================================
// TEST: IS_SOLE_WINNER FLAG
// =============================================================================

Deno.test("isSoleWinner - true when single winner", () => {
  const tiedWinners = [{ proposition_id: 1, global_score: 85.0 }];
  const isSoleWinner = tiedWinners.length === 1;

  assertEquals(isSoleWinner, true);
});

Deno.test("isSoleWinner - false when multiple winners", () => {
  const tiedWinners = [
    { proposition_id: 1, global_score: 75.0 },
    { proposition_id: 2, global_score: 75.0 },
  ];
  const isSoleWinner = tiedWinners.length === 1;

  assertEquals(isSoleWinner, false);
});

// =============================================================================
// TEST: PRIMARY WINNER SELECTION (oldest among ties)
// =============================================================================

Deno.test("Primary Winner - selects oldest proposition among ties", () => {
  const propositions = [
    { id: 100, created_at: "2026-01-10T10:00:00Z" },
    { id: 101, created_at: "2026-01-10T10:05:00Z" },
    { id: 102, created_at: "2026-01-10T10:10:00Z" },
  ];

  const tiedWinners = [
    { proposition_id: 101, global_score: 75.0 },
    { proposition_id: 102, global_score: 75.0 },
  ];

  const tiedIds = new Set(tiedWinners.map((w) => w.proposition_id));
  const oldestTied = propositions.find((p) => tiedIds.has(p.id));
  const primaryWinnerId = oldestTied?.id || tiedWinners[0].proposition_id;

  // Should be 101 (oldest among tied: 101 and 102)
  assertEquals(primaryWinnerId, 101);
});

Deno.test("Primary Winner - oldest is first in tie list", () => {
  const propositions = [
    { id: 100, created_at: "2026-01-10T10:00:00Z" },
    { id: 101, created_at: "2026-01-10T10:05:00Z" },
    { id: 102, created_at: "2026-01-10T10:10:00Z" },
  ];

  const tiedWinners = [
    { proposition_id: 100, global_score: 75.0 },
    { proposition_id: 102, global_score: 75.0 },
  ];

  const tiedIds = new Set(tiedWinners.map((w) => w.proposition_id));
  const oldestTied = propositions.find((p) => tiedIds.has(p.id));
  const primaryWinnerId = oldestTied?.id || tiedWinners[0].proposition_id;

  // Should be 100 (oldest among tied: 100 and 102)
  assertEquals(primaryWinnerId, 100);
});

// =============================================================================
// TEST: ROUND_WINNERS INSERT DATA STRUCTURE
// =============================================================================

Deno.test("Round Winners Insert - single winner structure", () => {
  const roundId = 1;
  const tiedWinners = [{ proposition_id: 100, global_score: 85.0 }];

  const insertData = tiedWinners.map((w) => ({
    round_id: roundId,
    proposition_id: w.proposition_id,
    rank: 1,
    global_score: w.global_score,
  }));

  assertEquals(insertData.length, 1);
  assertEquals(insertData[0].round_id, 1);
  assertEquals(insertData[0].proposition_id, 100);
  assertEquals(insertData[0].rank, 1);
  assertEquals(insertData[0].global_score, 85.0);
});

Deno.test("Round Winners Insert - multiple winners structure", () => {
  const roundId = 5;
  const tiedWinners = [
    { proposition_id: 200, global_score: 50.0 },
    { proposition_id: 201, global_score: 50.0 },
    { proposition_id: 202, global_score: 50.0 },
  ];

  const insertData = tiedWinners.map((w) => ({
    round_id: roundId,
    proposition_id: w.proposition_id,
    rank: 1,
    global_score: w.global_score,
  }));

  assertEquals(insertData.length, 3);

  // All should have same round_id and rank
  for (const row of insertData) {
    assertEquals(row.round_id, 5);
    assertEquals(row.rank, 1);
    assertEquals(row.global_score, 50.0);
  }

  // Each should have unique proposition_id
  const propositionIds = insertData.map(r => r.proposition_id);
  assertEquals(new Set(propositionIds).size, 3);
});

// =============================================================================
// TEST: ROUND UPDATE DATA STRUCTURE
// =============================================================================

Deno.test("Round Update - sole winner data structure", () => {
  const primaryWinnerId = 100;
  const isSoleWinner = true;
  const completedAt = new Date().toISOString();

  const updateData = {
    winning_proposition_id: primaryWinnerId,
    is_sole_winner: isSoleWinner,
    completed_at: completedAt,
  };

  assertEquals(updateData.winning_proposition_id, 100);
  assertEquals(updateData.is_sole_winner, true);
  assertExists(updateData.completed_at);
});

Deno.test("Round Update - tied winner data structure", () => {
  const primaryWinnerId = 200; // Oldest among ties
  const isSoleWinner = false;
  const completedAt = new Date().toISOString();

  const updateData = {
    winning_proposition_id: primaryWinnerId,
    is_sole_winner: isSoleWinner,
    completed_at: completedAt,
  };

  assertEquals(updateData.winning_proposition_id, 200);
  assertEquals(updateData.is_sole_winner, false);
  assertExists(updateData.completed_at);
});

// =============================================================================
// TEST: EDGE CASES
// =============================================================================

Deno.test("Edge Case - empty scores list", () => {
  const scores: Array<{ proposition_id: number; global_score: number }> = [];
  const propositions = [
    { id: 1, created_at: "2026-01-10T10:00:00Z" },
  ];

  let primaryWinnerId: number;
  let isSoleWinner: boolean;
  let tiedWinners: Array<{ proposition_id: number; global_score: number }>;

  if (scores.length === 0) {
    // Fallback to oldest proposition
    primaryWinnerId = propositions[0].id;
    isSoleWinner = true;
    tiedWinners = [{ proposition_id: propositions[0].id, global_score: 0 }];
  } else {
    primaryWinnerId = scores[0].proposition_id;
    isSoleWinner = true;
    tiedWinners = [scores[0]];
  }

  assertEquals(primaryWinnerId, 1);
  assertEquals(isSoleWinner, true);
  assertEquals(tiedWinners.length, 1);
  assertEquals(tiedWinners[0].global_score, 0);
});

Deno.test("Edge Case - all propositions tied", () => {
  const scores = [
    { proposition_id: 1, global_score: 50.0 },
    { proposition_id: 2, global_score: 50.0 },
    { proposition_id: 3, global_score: 50.0 },
    { proposition_id: 4, global_score: 50.0 },
    { proposition_id: 5, global_score: 50.0 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  assertEquals(tiedWinners.length, 5);
  assertEquals(tiedWinners.length === 1, false); // isSoleWinner = false
});

Deno.test("Edge Case - negative scores (valid MOVDA output)", () => {
  const scores = [
    { proposition_id: 1, global_score: -10.0 },
    { proposition_id: 2, global_score: -10.0 },
    { proposition_id: 3, global_score: -50.0 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  assertEquals(tiedWinners.length, 2);
});

Deno.test("Edge Case - very close but not tied", () => {
  const scores = [
    { proposition_id: 1, global_score: 75.0 },
    { proposition_id: 2, global_score: 74.998 },  // Diff = 0.002, > 0.001
    { proposition_id: 3, global_score: 74.0 },
  ];

  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  assertEquals(tiedWinners.length, 1);
  assertEquals(tiedWinners[0].proposition_id, 1);
});

// =============================================================================
// TEST: COMPLETE SCENARIO SIMULATION
// =============================================================================

Deno.test("Complete Scenario - sole winner flow", () => {
  // Simulate the full calculateWinnerAndComplete logic
  const round = { id: 10, cycle_id: 5, custom_id: 3, phase: "rating" };

  const propositions = [
    { id: 100, created_at: "2026-01-10T10:00:00Z" },
    { id: 101, created_at: "2026-01-10T10:05:00Z" },
  ];

  const scores = [
    { proposition_id: 100, global_score: 85.0 },
    { proposition_id: 101, global_score: 65.0 },
  ];

  // Detection logic
  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  const isSoleWinner = tiedWinners.length === 1;
  const primaryWinnerId = tiedWinners[0].proposition_id;

  // Prepare insert data
  const insertData = tiedWinners.map((w) => ({
    round_id: round.id,
    proposition_id: w.proposition_id,
    rank: 1,
    global_score: w.global_score,
  }));

  // Prepare update data
  const updateData = {
    winning_proposition_id: primaryWinnerId,
    is_sole_winner: isSoleWinner,
    completed_at: new Date().toISOString(),
  };

  // Verify
  assertEquals(isSoleWinner, true);
  assertEquals(primaryWinnerId, 100);
  assertEquals(insertData.length, 1);
  assertEquals(updateData.is_sole_winner, true);
});

Deno.test("Complete Scenario - tied winner flow", () => {
  // Simulate the full calculateWinnerAndComplete logic with a tie
  const round = { id: 20, cycle_id: 10, custom_id: 5, phase: "rating" };

  const propositions = [
    { id: 200, created_at: "2026-01-10T10:00:00Z" },  // Oldest
    { id: 201, created_at: "2026-01-10T10:05:00Z" },
    { id: 202, created_at: "2026-01-10T10:10:00Z" },
  ];

  const scores = [
    { proposition_id: 201, global_score: 75.0 },
    { proposition_id: 202, global_score: 75.0 },
    { proposition_id: 200, global_score: 50.0 },
  ];

  // Detection logic
  const topScore = scores[0].global_score;
  const SCORE_TOLERANCE = 0.001;
  const tiedWinners = scores.filter(
    (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
  );

  const isSoleWinner = tiedWinners.length === 1;

  // Find oldest among tied
  const tiedIds = new Set(tiedWinners.map((w) => w.proposition_id));
  const oldestTied = propositions.find((p) => tiedIds.has(p.id));
  const primaryWinnerId = oldestTied?.id || tiedWinners[0].proposition_id;

  // Prepare insert data
  const insertData = tiedWinners.map((w) => ({
    round_id: round.id,
    proposition_id: w.proposition_id,
    rank: 1,
    global_score: w.global_score,
  }));

  // Prepare update data
  const updateData = {
    winning_proposition_id: primaryWinnerId,
    is_sole_winner: isSoleWinner,
    completed_at: new Date().toISOString(),
  };

  // Verify
  assertEquals(isSoleWinner, false);
  assertEquals(primaryWinnerId, 201);  // Oldest among 201 and 202 (201 was created first among tied)
  assertEquals(insertData.length, 2);
  assertEquals(updateData.is_sole_winner, false);

  // Verify all tied winners are in insert data
  const insertedIds = insertData.map(d => d.proposition_id);
  assertEquals(insertedIds.includes(201), true);
  assertEquals(insertedIds.includes(202), true);
});

console.log("All Edge Function tests defined. Run with: deno test --allow-env");
