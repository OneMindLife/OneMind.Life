// Just-in-time concept reveals: one-line explanations that fire the first time
// a user reaches a moment where a piece of the OneMind model becomes real —
// their first head-to-head duel, their first time opening a thread. This is the
// "teach the concept, not the chrome" half of the onboarding: the ConceptSheet
// answers "what is this?" on demand; these teach the same model in the moment,
// which sticks better than any upfront tour and reaches the power user too
// (they fire on the EVENT, not on a walkthrough).
//
// Each reveal fires ONCE, ever, per browser — a concept you've met doesn't need
// re-explaining. Deliberately NOT tied to convergence: the repository model has
// no discrete "your opinion pinned" event to teach against (the #1 spot is
// ambient), so a convergence reveal would have to fire arbitrarily or lie.

export type RevealKey = "duel" | "branch";

/// The copy for each moment. One sentence, plain language, stating the concept
/// the moment reveals — never how to operate the control (that's self-evident).
export const REVEAL_COPY: Record<RevealKey, string> = {
  duel: "Two real opinions, head to head. You pick the stronger one — the crowd's votes decide what “stronger” means, together. There's no right answer set in advance.",
  branch:
    "You just opened an opinion. Any opinion can hold its own discussion — a chat inside the chat, where it competes all over again.",
};

const STORAGE_PREFIX = "om_reveal_";

/// True once this reveal has been shown (and dismissed) before.
export function hasSeenReveal(key: RevealKey): boolean {
  try {
    return localStorage.getItem(STORAGE_PREFIX + key) === "1";
  } catch {
    // Private mode / no window — treat as unseen; worst case it shows again.
    return false;
  }
}

/// Mark a reveal as met, so it never fires again.
export function markRevealSeen(key: RevealKey): void {
  try {
    localStorage.setItem(STORAGE_PREFIX + key, "1");
  } catch {
    /* private mode — it'll simply reappear next session */
  }
}
