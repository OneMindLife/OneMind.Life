// Pure, DB-free helpers for the matches-mode rating advance decision used by
// process-timers. Extracted here so they can be unit-tested directly (the
// process-timers index.ts calls Deno.serve at module load, so it can't be
// imported from a test). The DB-backed counting (get_matches_rating_progress)
// is covered separately by pgtap test 111; these helpers cover the decision
// rules and the done-count dedup.

export interface RaterRow {
  participant_id: number | null;
}

/// Distinct rater count across the given row sets (rating_completions,
/// grid_rankings, rating_skips). A participant counted in more than one set
/// (e.g. has both a completion and a grid row) is counted once. Null
/// participant_ids (anonymous/session-only rows) are ignored.
export function distinctRaterCount(...rowSets: RaterRow[][]): number {
  const seen = new Set<number>();
  for (const rows of rowSets) {
    for (const r of rows) {
      if (r.participant_id != null) seen.add(r.participant_id);
    }
  }
  return seen.size;
}

/// Early-advance rule for a matches rating round: advance once every eligible
/// rater has finished (per-rater completion, not per-proposition coverage).
export function shouldEarlyAdvanceMatches(done: number, eligible: number): boolean {
  return eligible > 0 && done >= eligible;
}

/// Timer-expiry minimum for a matches rating round: advance if at least one
/// rater finished; otherwise extend. (Pure-human matches votes never touch
/// grid_rankings, so the grid avg-raters check would otherwise extend forever.)
export function matchesTimerMinimumMet(done: number): boolean {
  return done >= 1;
}

/// Whether the early-advance loop should evaluate a round at all: only when a
/// percent/count threshold is configured. This is mode-agnostic — matches
/// rating honors the wizard's "Rating auto-advance" toggle exactly like grid.
/// When the toggle is OFF (both thresholds NULL) the phase is timer-paced; the
/// timer-expiry path (matchesTimerMinimumMet / checkMinimumMet) still advances
/// it once the phase ends, so it never hangs. When ON, checkThresholdsMet →
/// shouldEarlyAdvanceMatches advances on full turnout. This mirrors the DB
/// trigger matches_preview_maybe_finalize (gated on the same toggle for
/// continuous chats), so both the instant and cron paths agree.
/// (isProposing / ratingMode are retained in the signature for call-site
/// clarity but no longer affect the decision.)
export function autoAdvanceGateOpen(params: {
  isProposing: boolean;
  ratingMode: string | null | undefined;
  thresholdPercent: number | null;
  thresholdCount: number | null;
}): boolean {
  const { thresholdPercent, thresholdCount } = params;
  if (thresholdPercent === null && thresholdCount === null) {
    return false;
  }
  return true;
}
