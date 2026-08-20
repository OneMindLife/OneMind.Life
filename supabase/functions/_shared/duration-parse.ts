// Parse human window durations for the Telegram /window command — pure so
// it's testable without importing index.ts (Deno.serve at load).
//
// Accepts "2h", "30m", "90m", "1h30m", "12h" (case-insensitive, optional
// spaces). Returns seconds, clamped to [15 minutes, 24 hours]; null when the
// input doesn't parse.

export const WINDOW_MIN_SECONDS = 15 * 60;
export const WINDOW_MAX_SECONDS = 24 * 60 * 60;

export function parseWindowSeconds(input: string): number | null {
  const s = input.trim().toLowerCase().replace(/\s+/g, "");
  if (!s) return null;
  const m = s.match(/^(?:(\d+)h)?(?:(\d+)m)?$/);
  if (!m || (m[1] === undefined && m[2] === undefined)) return null;
  const hours = m[1] ? parseInt(m[1], 10) : 0;
  const minutes = m[2] ? parseInt(m[2], 10) : 0;
  const secs = hours * 3600 + minutes * 60;
  if (secs <= 0) return null;
  return Math.min(WINDOW_MAX_SECONDS, Math.max(WINDOW_MIN_SECONDS, secs));
}

/** Render seconds back as "2h", "90m", "1h30m" for confirmation copy. */
export function formatWindow(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (h > 0 && m > 0) return `${h}h${m}m`;
  if (h > 0) return `${h}h`;
  return `${m}m`;
}
