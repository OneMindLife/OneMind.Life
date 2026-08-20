// Edge Function Test: C15 tree-node window-flip decisions
//
// Run with: deno test --allow-all supabase/functions/tests/tree-advance-test.ts
//
// Pure decision helpers for tree-node (child cycle) rounds — see
// docs/ONEMIND_CONCEPT.md C15 and _shared/tree-advance.ts. The DB wiring
// (spawn, gating) is covered by pgtap test 109.

import { assertEquals } from "https://deno.land/std@0.192.0/testing/asserts.ts";
import {
  treeIdleSeconds,
  treeProposingAction,
  treeRatingAction,
} from "../_shared/tree-advance.ts";

// ---------------------------------------------------------------------------
// treeProposingAction — >= 2 props opens the vote; the AI's lone prop idles
// ---------------------------------------------------------------------------
Deno.test("proposing: 0 props idles a full cycle", () => {
  assertEquals(treeProposingAction(0), "idle_full_cycle");
});

Deno.test("proposing: 1 prop (the AI's alone) idles — AI cannot propagate the tree", () => {
  assertEquals(treeProposingAction(1), "idle_full_cycle");
});

Deno.test("proposing: 2 props (one human + AI) opens the vote", () => {
  assertEquals(treeProposingAction(2), "open_vote");
});

Deno.test("proposing: many props opens the vote", () => {
  assertEquals(treeProposingAction(7), "open_vote");
});

// ---------------------------------------------------------------------------
// treeRatingAction — >= 1 real vote seals; zero attention idles
// ---------------------------------------------------------------------------
Deno.test("rating: 0 real votes idles a full cycle", () => {
  assertEquals(treeRatingAction(0), "idle_full_cycle");
});

Deno.test("rating: 1 real vote seals the node", () => {
  assertEquals(treeRatingAction(1), "seal");
});

// ---------------------------------------------------------------------------
// treeIdleSeconds — idle spans the opposite window: one full cycle
// ---------------------------------------------------------------------------
Deno.test("idle spans proposing + rating durations (12h/12h -> 24h)", () => {
  assertEquals(treeIdleSeconds(43200, 43200), 86400);
});
