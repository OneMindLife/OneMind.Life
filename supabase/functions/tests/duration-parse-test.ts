// Edge Function Test: /window duration parsing
//
// Run with: deno test --allow-all supabase/functions/tests/duration-parse-test.ts

import { assertEquals } from "https://deno.land/std@0.192.0/testing/asserts.ts";
import {
  formatWindow,
  parseWindowSeconds,
  WINDOW_MAX_SECONDS,
  WINDOW_MIN_SECONDS,
} from "../_shared/duration-parse.ts";

Deno.test("parses hours", () => {
  assertEquals(parseWindowSeconds("2h"), 7200);
});

Deno.test("parses minutes", () => {
  assertEquals(parseWindowSeconds("30m"), 1800);
});

Deno.test("parses combined", () => {
  assertEquals(parseWindowSeconds("1h30m"), 5400);
});

Deno.test("case/space tolerant", () => {
  assertEquals(parseWindowSeconds(" 2H "), 7200);
});

Deno.test("clamps below the floor", () => {
  assertEquals(parseWindowSeconds("1m"), WINDOW_MIN_SECONDS);
});

Deno.test("clamps above the ceiling", () => {
  assertEquals(parseWindowSeconds("48h"), WINDOW_MAX_SECONDS);
});

Deno.test("rejects junk", () => {
  assertEquals(parseWindowSeconds("soon"), null);
  assertEquals(parseWindowSeconds(""), null);
  assertEquals(parseWindowSeconds("h"), null);
  assertEquals(parseWindowSeconds("0m"), null);
});

Deno.test("formats round-trip", () => {
  assertEquals(formatWindow(7200), "2h");
  assertEquals(formatWindow(1800), "30m");
  assertEquals(formatWindow(5400), "1h30m");
});
