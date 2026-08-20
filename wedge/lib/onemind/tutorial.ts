// The /g guided-tutorial step machine: a 5-step loop taught by DOING (tap into
// a thread → leave a reply → tap back to the root → vote a match → share),
// persisted so it runs once and only ever advances forward. The `back` step
// exists because voting lives at the root (which always has a votable pair),
// whereas the thread you just replied in may be too thin to vote — so we walk
// the user back up before the vote nudge. Pure + storage helpers live here; the
// React wiring is the useTutorial hook.

export type TutStep = "tap" | "reply" | "back" | "vote" | "share" | "done";

/// Monotonic order of the steps — advancing is "take the max of the two".
/// New flow (vote-first, earn-the-list): you land straight in the duel, clear
/// the matches to unlock the discussion, then Share. `tap`/`reply`/`back` are
/// legacy tour steps kept for back-compat (persisted values) but no longer part
/// of the guided sequence — pinned to the start so they resolve to "vote".
export const TUT_ORDER: Record<TutStep, number> = {
  tap: 0,
  back: 0,
  vote: 0,
  reply: 1,
  share: 2,
  done: 3,
};

export const TUT_STORAGE_KEY = "om_tut";

/// The persisted step, or "tap" when absent/unreadable (SSR, private mode).
export function readTutStep(): TutStep {
  try {
    const v = localStorage.getItem(TUT_STORAGE_KEY);
    if (
      v === "reply" ||
      v === "back" ||
      v === "vote" ||
      v === "share" ||
      v === "done"
    )
      return v;
  } catch {
    /* private mode / no window */
  }
  return "vote"; // new flow starts in the duel
}

/// Forward-only advance: returns `to` only when it's strictly later than `cur`,
/// otherwise keeps `cur` (the tutorial never regresses).
export function nextTutStep(cur: TutStep, to: TutStep): TutStep {
  return TUT_ORDER[to] > TUT_ORDER[cur] ? to : cur;
}
