import { supabase, ensureSignedIn } from "@/lib/supabase/client";

// Scheduled rooms: a chat that is open only during a recurring window (the
// GLOBAL front door runs a daily 30-minute live event — see
// docs/RETENTION_EXPERIMENT.md). The server owns the truth; this module is the
// read side plus the pure formatters the closed screen renders.
//
// Why an RPC rather than deriving the window client-side from
// chats.schedule_windows: the boundaries are weekday+local-time pairs in the
// chat's timezone, so "when does it next open" is DST-dependent. Postgres
// already resolves that in get_chat_schedule_state; duplicating it in JS would
// be a second source of truth that drifts twice a year.

export type ScheduleState = {
  isOpen: boolean;
  /// Start of the current-or-next window (ISO). Null when the chat has no
  /// schedule, or a recurring schedule with no windows configured.
  opensAt: string | null;
  /// End of that same window (ISO).
  closesAt: string | null;
  /// IANA zone the window is expressed in, e.g. "America/New_York".
  timezone: string;
};

/// Read a chat's open/closed state and its next boundary. Chats with no
/// schedule report `isOpen: true` with null boundaries, so callers can run this
/// unconditionally.
export async function getScheduleState(
  chatId: number,
): Promise<ScheduleState> {
  const { data, error } = await supabase.rpc("get_chat_schedule_state", {
    p_chat_id: chatId,
  });
  if (error) throw error;
  const row = ((data as Record<string, unknown>[] | null) ?? [])[0];
  if (!row) return { isOpen: true, opensAt: null, closesAt: null, timezone: "UTC" };
  return {
    isOpen: row.is_open === true,
    opensAt: (row.opens_at as string | null) ?? null,
    closesAt: (row.closes_at as string | null) ?? null,
    timezone: (row.timezone as string | null) ?? "UTC",
  };
}

/// Record that this user wants the "the room is open" ping. Kept separate from
/// root_watches (keyed on participant_id) because the closed screen must NOT
/// join anyone: the whole point is that arrivals between sessions don't land a
/// participant row. Idempotent — the PK is (chat_id, user_id).
export async function subscribeToRoomOpen(chatId: number): Promise<boolean> {
  const session = await ensureSignedIn();
  const uid = session?.user.id;
  if (!uid) return false;
  const { error } = await supabase
    .from("room_open_subscribers")
    .upsert({ chat_id: chatId, user_id: uid }, { onConflict: "chat_id,user_id" });
  return !error;
}

// ── Pure formatters ─────────────────────────────────────────────────────────

/// Coarse-to-fine countdown: hours+minutes far out, minutes+seconds inside the
/// last hour, seconds in the last minute. Returns "now" once the target passes
/// so the caller can re-check instead of rendering a negative clock.
export function countdown(nowMs: number, targetIso: string | null): string {
  if (!targetIso) return "";
  const ms = new Date(targetIso).getTime() - nowMs;
  if (!Number.isFinite(ms) || ms <= 0) return "now";
  const total = Math.floor(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

/// "8:00 AM EDT" — the window's opening time in the ROOM's timezone, which is
/// the time everyone is being asked to show up at. `locale` localizes the clock
/// format (defaults to en-US so existing callers/tests are unchanged); the room
/// screen passes the viewer's language.
export function roomTimeLabel(
  openIso: string | null,
  timezone: string,
  locale: string = "en-US",
): string {
  if (!openIso) return "";
  try {
    return new Intl.DateTimeFormat(locale, {
      hour: "numeric",
      minute: "2-digit",
      timeZone: timezone,
      timeZoneName: "short",
    }).format(new Date(openIso));
  } catch {
    return "";
  }
}

/// "5:30 PM" — the same instant in the VIEWER's timezone. The audience is
/// mostly not in the room's zone, so the room time alone is not actionable.
export function viewerTimeLabel(openIso: string | null): string {
  if (!openIso) return "";
  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      minute: "2-digit",
    }).format(new Date(openIso));
  } catch {
    return "";
  }
}

/// Length of the window as structured parts (language-free). The component
/// composes the label via i18n:
///   mins      → "30 minutes" / "30 minutos"
///   hours     → "2h"     (unit — same in both languages)
///   hoursMins → "2h 15m" (units)
/// Returns null when either edge is unknown or the span is non-positive.
export type WindowLength =
  | { kind: "mins"; n: number }
  | { kind: "hours"; h: number }
  | { kind: "hoursMins"; h: number; m: number };

export function windowLength(
  openIso: string | null,
  closeIso: string | null,
): WindowLength | null {
  if (!openIso || !closeIso) return null;
  const mins = Math.round(
    (new Date(closeIso).getTime() - new Date(openIso).getTime()) / 60000,
  );
  if (!Number.isFinite(mins) || mins <= 0) return null;
  if (mins < 60) return { kind: "mins", n: mins };
  const h = Math.floor(mins / 60);
  const rem = mins % 60;
  return rem === 0 ? { kind: "hours", h } : { kind: "hoursMins", h, m: rem };
}
