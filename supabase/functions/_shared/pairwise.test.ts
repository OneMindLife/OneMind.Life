import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { scoresToPairwiseRows } from "./pairwise.ts";

Deno.test("two props — single pair, higher score wins", () => {
  const rows = scoresToPairwiseRows(
    [
      { propositionId: 1, score: 40 },
      { propositionId: 2, score: 80 },
    ],
    99,
    7
  );
  assertEquals(rows.length, 1);
  assertEquals(rows[0].winner_proposition_id, 2);
  assertEquals(rows[0].loser_proposition_id, 1);
  assertEquals(rows[0].is_tie, false);
  assertEquals(rows[0].round_id, 99);
  assertEquals(rows[0].participant_id, 7);
});

Deno.test("equal scores — tie with distinct winner/loser", () => {
  const rows = scoresToPairwiseRows(
    [
      { propositionId: 1, score: 50 },
      { propositionId: 2, score: 50 },
    ],
    1,
    1
  );
  assertEquals(rows.length, 1);
  assertEquals(rows[0].is_tie, true);
  // Deterministic order; schema forbids winner === loser even for ties.
  assertEquals(rows[0].winner_proposition_id !== rows[0].loser_proposition_id, true);
});

Deno.test("n props — C(n,2) rows, transitively consistent", () => {
  const rows = scoresToPairwiseRows(
    [
      { propositionId: 1, score: 10 },
      { propositionId: 2, score: 20 },
      { propositionId: 3, score: 30 },
      { propositionId: 4, score: 40 },
    ],
    1,
    1
  );
  assertEquals(rows.length, 6); // C(4,2)
  // Every pair's winner is the higher-scored prop → prop 4 wins all 3 of its
  // pairs, prop 1 loses all 3.
  const wins = (id: number) =>
    rows.filter((r) => r.winner_proposition_id === id && !r.is_tie).length;
  assertEquals(wins(4), 3);
  assertEquals(wins(1), 0);
});

Deno.test("fewer than 2 props — no pairs", () => {
  assertEquals(scoresToPairwiseRows([{ propositionId: 1, score: 50 }], 1, 1), []);
  assertEquals(scoresToPairwiseRows([], 1, 1), []);
});
