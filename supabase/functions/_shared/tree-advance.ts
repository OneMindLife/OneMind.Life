// C15 tree-node (child cycle) round decisions — pure helpers so they're
// testable without importing process-timers' index.ts (Deno.serve at load).
//
// A node round lives on the chat-wide window clock (docs/ONEMIND_CONCEPT.md
// C15): >= 2 propositions to open a vote (the node's single AI prop alone can
// never advance it), >= 1 real (non-skip) vote to seal. Otherwise the node
// idles one FULL cycle — landing on the next same-phase window, keeping the
// whole tree flipping together.

export type TreeNodeAction =
  | "open_vote"
  | "seal"
  | "idle_full_cycle";

/** Proposing window end: enough contenders to vote on? */
export function treeProposingAction(propCount: number): TreeNodeAction {
  return propCount >= 2 ? "open_vote" : "idle_full_cycle";
}

/** Voting window end: did anyone actually judge this node? */
export function treeRatingAction(realVoteCount: number): TreeNodeAction {
  return realVoteCount >= 1 ? "seal" : "idle_full_cycle";
}

/** Idle skips the opposite phase's window: one full cycle. */
export function treeIdleSeconds(
  proposingDurationSeconds: number,
  ratingDurationSeconds: number,
): number {
  return proposingDurationSeconds + ratingDurationSeconds;
}
