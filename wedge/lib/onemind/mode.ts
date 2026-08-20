// Fun-mode A/B (experiment H-FUN, 2026-06-08). Tests whether framing OneMind as
// a quick group *game* (fun seeds + "play again") makes groups REPLAY + SHARE
// more than the "decision tool" framing — i.e. whether the game-likeness our
// testers noticed is a retention/virality unlock (D39), not an acquisition play.
//
// Assignment is 50/50 per session, set in app/analytics.tsx's first-touch script
// (sessionStorage `_om_mode`), and stamped onto every analytics event by the
// bridge — so replay (quick_chat_create_another) and share (quick_chat_share)
// are segmentable by mode with no DB change. Default "decision" (= current
// behaviour) on SSR / if unset.
export type Mode = "fun" | "decision";

export function getMode(): Mode {
  if (typeof window === "undefined") return "decision";
  try {
    return sessionStorage.getItem("_om_mode") === "fun" ? "fun" : "decision";
  } catch {
    return "decision";
  }
}

// Fun-framed seed chips (opinion/curiosity questions that fit the anonymous
// converge mechanic — no person-ranking, since there's no roster). Swapped in
// for the decision seeds when the session is in fun mode.
export const FUN_SEEDS = [
  "Most overrated movie ever?",
  "Best pizza topping — settled?",
  "What's our group's hottest take?",
];
