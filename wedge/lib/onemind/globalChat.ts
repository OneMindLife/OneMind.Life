// Pure data-mapping + derivation helpers for the Global Chat surface (the
// continuous, clock-driven "the room speaks" room, chat code GLOBAL). Kept free
// of React/Supabase so they're unit-testable in isolation — the async loader
// that feeds `mapGlobalWinners` lives in chat.ts (`loadGlobalWinners`).
//
// See docs/design/global-chat/README.md.

/// One permanent winning take in the feed ("OneMind speaks").
export type GlobalWinner = {
  id: number;
  text: string;
  /// How many other takes it eliminated = (props in that round − 1), never < 0.
  beat: number;
  /// How many people's votes decided it (server-counted).
  voters: number;
  /// Raw decision timestamp (ISO) or null. The human-readable label is composed
  /// in the component via `winnerTimeParts` + i18n (so it localizes AND updates
  /// live against the ticking clock, instead of being frozen at load time).
  timeIso: string | null;
  /// Whether the winning take was authored by the current viewer.
  mine: boolean;
};

const PHASE_FALLBACK_SECONDS = 43200; // 12h — GLOBAL's proposing/rating window

// The staging-take dot palette (mirrors the prototype's hue rotation).
const HUES = ["h0", "h2", "h3", "h4", "h5", "h1"] as const;

export function hueFor(index: number): string {
  return HUES[((index % HUES.length) + HUES.length) % HUES.length];
}

/// Compact cadence label for the phase bar ("30s", "1m", "12h"). The room's
/// phase length is a per-chat setting that has already moved once (12h → 60s
/// for the scheduled live event), so the bar reads it from the chat rather
/// than hardcoding it. Falls back to the 12h window for a missing value.
export function phaseLabel(durationSeconds: number | null | undefined): string {
  const s =
    Number.isFinite(durationSeconds) && (durationSeconds as number) > 0
      ? (durationSeconds as number)
      : PHASE_FALLBACK_SECONDS;
  if (s < 60) return `${Math.round(s)}s`;
  if (s < 3600) {
    const m = s / 60;
    return Number.isInteger(m) ? `${m}m` : `${Math.round(m)}m`;
  }
  const h = s / 3600;
  return Number.isInteger(h) ? `${h}h` : `${Math.round(h * 10) / 10}h`;
}

/// mm:ss for < 1h, h:mm:ss for the 12h clock. Tabular-friendly, zero-padded.
export function formatClock(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(ss)}` : `${m}:${pad(ss)}`;
}

/// Flutter CountdownTimer format: "11h 47m 35s" / "47m 35s" / "35s" (unit
/// suffixes, zero-padded minutes/seconds) — used by the /g countdown copy so it
/// reads identically to the native app.
export function flutterClock(totalSec: number): string {
  const s = Math.max(0, Math.floor(totalSec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  if (h > 0) return `${h}h ${pad(m)}m ${pad(ss)}s`;
  if (m > 0) return `${m}m ${pad(ss)}s`;
  return `${ss}s`;
}

/// % of the phase still remaining (drives the draining phase-bar fill). Clamped.
export function clockPct(remaining: number, duration: number): number {
  if (!Number.isFinite(duration) || duration <= 0) return 0;
  return Math.max(0, Math.min(100, Math.round((remaining / duration) * 100)));
}

export type ClockState = {
  remaining: number; // seconds until phase_ends_at (>= 0)
  duration: number; // phase length in seconds (phase_ends_at − phase_started_at)
  pct: number; // remaining / duration, 0..100
};

/// Derive the countdown from the round's server clock. `remaining` counts down
/// to `phase_ends_at`; `duration` is the true phase length so the bar drains
/// from 100→0 over the real window (not a client-side guess). Re-sync on every
/// refresh; tick `now` locally each second between refreshes.
export function deriveClock(
  // Typed as a loose record so it accepts the bootstrap's RoundLite (whose extra
  // columns are `unknown`); the two timestamp fields are coerced to strings.
  round: Record<string, unknown> | null | undefined,
  now: Date,
): ClockState {
  const endsRaw = round?.phase_ends_at;
  if (!round || endsRaw == null) {
    return { remaining: 0, duration: PHASE_FALLBACK_SECONDS, pct: 0 };
  }
  const ends = new Date(String(endsRaw)).getTime();
  const startedRaw = round.phase_started_at;
  const started =
    startedRaw != null
      ? new Date(String(startedRaw)).getTime()
      : ends - PHASE_FALLBACK_SECONDS * 1000;
  const duration = Math.max(1, Math.round((ends - started) / 1000));
  const remaining = Math.max(0, Math.round((ends - now.getTime()) / 1000));
  return { remaining, duration, pct: clockPct(remaining, duration) };
}

/// The backend can only end a proposing phase once this many new takes are in
/// (`proposing_minimum` — below it, process-timers extends the timer forever),
/// and it advances early the moment `proposing_threshold_count` people have
/// acted. Mirror the first fact honestly in the dock: below the minimum a
/// countdown is a lie (it will silently extend), so show the threshold goal
/// instead of a clock.
export const PROPOSING_MIN_TAKES = 2;

export type ProposingBar =
  | { mode: "goal"; pct: number }
  | { mode: "countdown"; pct: number };

/// What the proposing phase-bar should show: a threshold goal ("need 2 to vote
/// · 1 in") while the round can't end yet, a real countdown once it can. In
/// goal mode the fill measures takes toward the minimum (goal-gradient framing),
/// not time. The English/Spanish copy lives in the component (i18n) — this
/// returns only the mode + fill %.
export function proposingBar(takesCount: number, clock: ClockState): ProposingBar {
  if (takesCount < PROPOSING_MIN_TAKES) {
    return {
      mode: "goal",
      pct: Math.round((takesCount / PROPOSING_MIN_TAKES) * 100),
    };
  }
  return { mode: "countdown", pct: clock.pct };
}

/// Bracket progress for `winner_only`: the honest denominator is the bracket
/// size ≈ (n − 1) matches; `done` = comparisons cast so far (capped at total).
/// Never a fabricated "pair X of Y".
export function voteProgress(
  rateableCount: number,
  votesCast: number,
): { total: number; done: number } {
  const total = Math.max(1, rateableCount - 1);
  const done = Math.max(0, Math.min(votesCast, total));
  return { total, done };
}

/// Structured "when a take landed" for the live staging list. Language-free —
/// the component turns the parts into localized copy ("now" / "12s" / "3m").
/// (Currently no render path uses it, but it's kept structured so a live-feed
/// timestamp can be localized when re-introduced.)
export type TakeAgo =
  | { kind: "now" }
  | { kind: "secs"; n: number }
  | { kind: "mins"; n: number };

export function takeAgoParts(iso: string | null | undefined, now: Date): TakeAgo {
  if (!iso) return { kind: "now" };
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return { kind: "now" };
  const s = Math.max(0, Math.floor((now.getTime() - t) / 1000));
  if (s < 3) return { kind: "now" };
  if (s < 60) return { kind: "secs", n: s };
  return { kind: "mins", n: Math.floor(s / 60) };
}

/// Structured decision time for a winner card. Language- and locale-free — the
/// component composes the label via i18n + the viewer's locale, and against the
/// live ticking clock so "Just now" ages correctly without a refetch.
///   now      → decided < 1 min ago
///   minsAgo  → decided < 1 h ago (n minutes)
///   today    → same calendar day; component formats the wall-clock time
///   yesterday→ the previous calendar day
///   dated    → older; component formats a short date + time
/// Returns null when there is no valid timestamp (→ the card shows no time).
export type WinnerTime =
  | { kind: "now" }
  | { kind: "minsAgo"; n: number }
  | { kind: "today"; iso: string }
  | { kind: "yesterday"; iso: string }
  | { kind: "dated"; iso: string };

export function winnerTimeParts(iso: string | null, now: Date): WinnerTime | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const diffMin = Math.floor((now.getTime() - d.getTime()) / 60000);
  if (diffMin < 1) return { kind: "now" };
  if (diffMin < 60) return { kind: "minsAgo", n: diffMin };
  if (d.toDateString() === now.toDateString()) return { kind: "today", iso };
  const yest = new Date(now);
  yest.setDate(now.getDate() - 1);
  if (d.toDateString() === yest.toDateString()) return { kind: "yesterday", iso };
  return { kind: "dated", iso };
}

/// One resolved row from the `get_global_winners` RPC — the server already
/// computed text (translated), beat, voters, and the winning author, so the
/// client mapper is a straight passthrough (no stitching, no extra round trips).
export type GlobalWinnerRow = {
  id: number;
  text: string | null;
  beat: number | null;
  voters: number | null;
  time_iso: string | null;
  winning_participant_id: number | null;
};

/// Compose the permanent winners chain from the single RPC snapshot. Pure +
/// null-safe: `mine` is resolved client-side against the viewer's participant id
/// (the server returns the winning author, not a per-viewer flag).
export function mapGlobalWinners(
  rows: GlobalWinnerRow[],
  myParticipantId: number | null,
): GlobalWinner[] {
  return rows.map((r) => ({
    id: r.id,
    text: r.text ?? "",
    beat: Math.max(0, r.beat ?? 0),
    voters: r.voters ?? 0,
    timeIso: r.time_iso,
    mine:
      r.winning_participant_id != null &&
      r.winning_participant_id === myParticipantId,
  }));
}

/// Pick up to `n` starter takes to offer as tappable chips: dedupe, drop
/// blanks, and drop anything already on the round's board (case/whitespace
/// insensitive) so a tap can't collide with DuplicatePropositionError or
/// parrot an existing take. Order is preserved (the LLM's diversity ordering).
export function pickStarters(
  options: string[],
  existingTexts: string[],
  n = 3,
): string[] {
  const norm = (t: string) => t.trim().replace(/\s+/g, " ").toLowerCase();
  const taken = new Set(existingTexts.map(norm));
  const out: string[] = [];
  for (const o of options) {
    const t = o.trim();
    if (!t) continue;
    const k = norm(t);
    if (taken.has(k)) continue;
    taken.add(k);
    out.push(t);
    if (out.length >= n) break;
  }
  return out;
}

// The room was previously split into alternating QUESTION / ANSWER rounds
// derived client-side from whether the latest winner ended in "?". That was
// removed 2026-07-09: naive "?" detection mis-classified winners, the per-round
// suggestion cache was mode-blind (an answer pool got served to a client that
// thought it was question time), and normalizeQuestion stapled a "?" onto
// statements, producing fake questions ("I enjoy the complexity, actually?").
// The room is now one continuous conversation; the AI starter reads the full
// history and proposes the single best next take, no mode, no forced "?".

// The rotating composer invitation placeholders (cycled every ~4s) moved into
// GlobalChat's Composer so they can be localized via i18n (`room.ph0`…`room.ph4`).
