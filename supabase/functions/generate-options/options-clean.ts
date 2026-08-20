// Pure parse / validation helper for generate-options.
//
// Extracted to its own module (mirroring _shared/matches-advance.ts) so it can
// be unit-tested without importing index.ts, which calls Deno.serve at load.

// Each option must fit a short, scannable preview card.
export const MAX_OPTION_LENGTH = 100;
// count bounds
export const MIN_COUNT = 2;
export const MAX_COUNT = 6;
export const DEFAULT_COUNT = 5;

/**
 * Parse and clean an LLM response into a validated list of option strings.
 *
 * Pure function — no I/O, no Deno globals.
 *
 * Steps:
 * - strip ``` / ```json code fences
 * - JSON.parse into a string array (anything else -> [])
 * - trim each, drop empties / non-strings
 * - enforce MAX_OPTION_LENGTH (truncate if over)
 * - dedupe case-insensitively (first occurrence wins)
 * - keep at most `count` options (count clamped to [MIN_COUNT, MAX_COUNT])
 *
 * Returns [] on any failure (garbage in -> empty out).
 */
export function cleanOptions(raw: string, count: number): string[] {
  if (typeof raw !== "string") return [];

  // Clamp count defensively so a bad caller can't blow the cap.
  const cap = Math.min(
    MAX_COUNT,
    Math.max(MIN_COUNT, Math.floor(count) || DEFAULT_COUNT),
  );

  // Strip code fences.
  let cleaned = raw.trim();
  if (cleaned.startsWith("```json")) {
    cleaned = cleaned.slice(7);
  } else if (cleaned.startsWith("```")) {
    cleaned = cleaned.slice(3);
  }
  if (cleaned.endsWith("```")) {
    cleaned = cleaned.slice(0, -3);
  }
  cleaned = cleaned.trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    return [];
  }
  if (!Array.isArray(parsed)) return [];

  const seen = new Set<string>();
  const result: string[] = [];

  for (const item of parsed) {
    if (typeof item !== "string") continue;
    let text = item.trim();
    if (text.length === 0) continue;
    // Truncate if slightly (or grossly) over the limit.
    if (text.length > MAX_OPTION_LENGTH) {
      text = text.slice(0, MAX_OPTION_LENGTH).trim();
      if (text.length === 0) continue;
    }
    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(text);
    if (result.length >= cap) break;
  }

  return result;
}
