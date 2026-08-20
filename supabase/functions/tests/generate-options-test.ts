// Edge Function Test: generate-options pure parse/validation helper
//
// Run with: deno test --allow-all supabase/functions/tests/generate-options-test.ts
//
// Covers the PURE cleanOptions() helper used by generate-options (extracted to
// ../generate-options/options-clean.ts so it's testable without importing
// index.ts, which calls Deno.serve at load). The LLM call + auth + handler
// wiring are integration concerns and are not exercised here.

import {
  assertEquals,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";
import {
  cleanOptions,
  MAX_OPTION_LENGTH,
} from "../generate-options/options-clean.ts";

// ---------------------------------------------------------------------------
// Fenced JSON — strips ```json ... ``` and parses
// ---------------------------------------------------------------------------
Deno.test("cleanOptions: parses fenced ```json array", () => {
  const raw = '```json\n["Pizza night", "Movie night", "Game night"]\n```';
  assertEquals(cleanOptions(raw, 5), ["Pizza night", "Movie night", "Game night"]);
});

Deno.test("cleanOptions: parses bare ``` fenced array", () => {
  const raw = '```\n["Alpha", "Beta"]\n```';
  assertEquals(cleanOptions(raw, 5), ["Alpha", "Beta"]);
});

// ---------------------------------------------------------------------------
// Plain JSON array — no fences
// ---------------------------------------------------------------------------
Deno.test("cleanOptions: parses a plain JSON array", () => {
  const raw = '["One", "Two", "Three"]';
  assertEquals(cleanOptions(raw, 5), ["One", "Two", "Three"]);
});

Deno.test("cleanOptions: trims whitespace and drops empties", () => {
  const raw = '["  spaced  ", "", "   ", "kept"]';
  assertEquals(cleanOptions(raw, 5), ["spaced", "kept"]);
});

// ---------------------------------------------------------------------------
// Dedup — case-insensitive, first occurrence wins
// ---------------------------------------------------------------------------
Deno.test("cleanOptions: dedupes case-insensitively (first wins)", () => {
  const raw = '["Pizza", "pizza", "PIZZA", "Tacos"]';
  assertEquals(cleanOptions(raw, 5), ["Pizza", "Tacos"]);
});

// ---------------------------------------------------------------------------
// Length truncation — over MAX_OPTION_LENGTH gets sliced
// ---------------------------------------------------------------------------
Deno.test("cleanOptions: truncates options over the max length", () => {
  const long = "x".repeat(MAX_OPTION_LENGTH + 50);
  const out = cleanOptions(JSON.stringify([long]), 5);
  assertEquals(out.length, 1);
  assertEquals(out[0].length, MAX_OPTION_LENGTH);
});

Deno.test("cleanOptions: keeps options at exactly the max length", () => {
  const exact = "y".repeat(MAX_OPTION_LENGTH);
  const out = cleanOptions(JSON.stringify([exact]), 5);
  assertEquals(out, [exact]);
});

// ---------------------------------------------------------------------------
// Count clamp — never returns more than the (clamped) requested count
// ---------------------------------------------------------------------------
Deno.test("cleanOptions: caps result at requested count", () => {
  const raw = '["a", "b", "c", "d", "e"]';
  assertEquals(cleanOptions(raw, 3), ["a", "b", "c"]);
});

Deno.test("cleanOptions: count above MAX_COUNT clamps to 6", () => {
  const raw = '["a", "b", "c", "d", "e", "f", "g", "h"]';
  assertEquals(cleanOptions(raw, 99), ["a", "b", "c", "d", "e", "f"]);
});

Deno.test("cleanOptions: count below MIN_COUNT clamps to 2", () => {
  const raw = '["a", "b", "c", "d"]';
  assertEquals(cleanOptions(raw, 1), ["a", "b"]);
});

Deno.test("cleanOptions: zero/NaN count falls back to default cap", () => {
  const raw = '["a", "b", "c", "d", "e", "f", "g"]';
  // 0 -> falsy -> DEFAULT_COUNT (5)
  assertEquals(cleanOptions(raw, 0), ["a", "b", "c", "d", "e"]);
});

// ---------------------------------------------------------------------------
// Garbage -> []
// ---------------------------------------------------------------------------
Deno.test("cleanOptions: non-JSON garbage -> []", () => {
  assertEquals(cleanOptions("not json at all", 5), []);
});

Deno.test("cleanOptions: empty string -> []", () => {
  assertEquals(cleanOptions("", 5), []);
});

Deno.test("cleanOptions: JSON object (not array) -> []", () => {
  assertEquals(cleanOptions('{"options": ["a"]}', 5), []);
});

Deno.test("cleanOptions: array of non-strings -> []", () => {
  assertEquals(cleanOptions("[1, 2, {}, null]", 5), []);
});

Deno.test("cleanOptions: mixed array keeps only valid strings", () => {
  assertEquals(cleanOptions('[1, "keep", null, "also"]', 5), ["keep", "also"]);
});
