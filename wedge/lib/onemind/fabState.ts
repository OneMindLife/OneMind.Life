// Pure state logic for the action FABs — kept free of React so it's unit-tested
// in isolation (see fabState.test.ts). The components (ActionFabs, ComposeSheet,
// TreeChatClient) are thin shells over these.

import { pendingMatches } from "./treeChat";

/// Where a new opinion lands when the Post FAB fires: a live round (post straight
/// in) or an empty leaf (spawn the child thread first, then post into it).
export type ComposeTarget =
  | { kind: "round"; roundId: number }
  | { kind: "leaf"; propId: number };

/// The Post FAB always lands somewhere: the current live round if there is one,
/// else the descended leaf whose thread it will spawn, else nowhere (transient
/// loading state — the FAB is a no-op).
export function composeTargetFor(
  liveRoundId: number | null,
  leafProp: number | null,
): ComposeTarget | null {
  if (liveRoundId != null) return { kind: "round", roundId: liveRoundId };
  if (leafProp != null) return { kind: "leaf", propId: leafProp };
  return null;
}

/// The Vote FAB is live only when this node has a pair to compare AND at least
/// one pairwise match this user hasn't cleared (floor(unplaced/2) >= 1).
export function voteFabEnabled(hasPair: boolean, unplaced: number): boolean {
  return hasPair && pendingMatches(unplaced) > 0;
}
