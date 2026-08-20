// The tree-walk: the pure core of the /g/<code> navigable-web screen.
//
// Given the loaded data (root rounds, cached boards, cached node snapshots) and
// the user's committed choices, it computes — with NO React, NO JSX, NO fetching
// — everything the screen needs to render one frame of the walk:
//
//   • steps       — the spine of committed cards + the current options list,
//                    described as DATA (the component maps these to JSX)
//   • chain        — the committed path (root → here) for the share card
//   • liveStop     — the live round the walk arrived at (proposing/vote surface)
//   • leafProp     — an empty leaf awaiting its first reply (composer target)
//   • pending      — a level's data isn't loaded yet (show a spinner)
//   • needRounds   — round ids whose boards must be fetched
//   • needNodes    — proposition ids whose node snapshots must be fetched
//
// Keeping this pure is what makes the navigation logic testable in isolation —
// the component became a thin renderer over the result. See treeWalk.test.ts.

// Type-only import — keeps this module free of the Supabase client (chat.ts
// pulls it in), so the walk stays a pure, unit-testable function.
import type { Bootstrap, WalkProp, WalkRound } from "./chat";

/// Prefer a translated body when present (mirrors chat.ts propContent, inlined
/// to avoid a runtime import of the client-bearing module).
const propContent = (p: { content: string; content_translated?: string | null }) =>
  p.content_translated || p.content;

/// A node bootstrap snapshot (a subround's round + board + window phase). Shape
/// mirrors the get_node_bootstrap RPC; kept loose because the walk only reads a
/// handful of fields defensively.
export type NodeSnapshot = Record<string, unknown>;

/// The live round the walk arrived at (round + its board), or null when the
/// walk stopped on options / an empty leaf.
export type LiveStop = { round: WalkRound; props: WalkProp[]; key: number };

/// One rendered row of the walk spine: either a committed card (tap to reopen
/// that level) or the options list at the current stop (tap one to descend).
export type WalkStep =
  | { kind: "options"; key: number; options: WalkProp[] }
  | { kind: "committed"; key: number; content: string };

/// A quote on the committed path — its text plus enough ids for the share card
/// to show each idea's TRUE rank at its own level.
export type ChainLink = { text: string; propId: number; roundId: number };

export type WalkInput = {
  roots: WalkRound[];
  data: Bootstrap;
  propsByRound: Record<number, WalkProp[]>;
  nodes: Record<number, NodeSnapshot>;
  choices: Record<number, number>;
  /// Repository mode (never_seals): always alive — reply threads open anytime,
  /// no proposing-window gate.
  repository: boolean;
};

export type WalkResult = {
  steps: WalkStep[];
  chain: ChainLink[];
  liveStop: LiveStop | null;
  leafProp: number | null;
  leafWindowOpen: boolean;
  pending: boolean;
  needRounds: number[];
  needNodes: number[];
};

export function walkTree(input: WalkInput): WalkResult {
  const { roots, data, propsByRound, nodes, choices, repository } = input;

  const steps: WalkStep[] = [];
  // The committed path (root → current) — the user's shareable "chain". Each
  // entry carries its prop + round id so the share card can show each idea's
  // TRUE rank AT ITS LEVEL (#N of M). The stack is a PATH down the tree, NOT a
  // set ranked against each other.
  const chain: ChainLink[] = [];
  const needRounds: number[] = [];
  const needNodes: number[] = [];
  let liveStop: LiveStop | null = null;
  let leafProp: number | null = null;
  let leafWindowOpen = false;
  let pending = false;

  const pushOptions = (key: number, options: WalkProp[]) => {
    steps.push({ kind: "options", key, options });
  };
  const pushCommitted = (
    key: number,
    content: string,
    propId?: number,
    roundId?: number,
  ) => {
    if (content && propId != null && roundId != null)
      chain.push({ text: content, propId, roundId });
    steps.push({ kind: "committed", key, content });
  };

  let descended = false;
  let walkEnded = false;
  let lastWinner: number | null = null;

  for (const r of roots) {
    const sealed = r.completed_at != null;
    if (!sealed) {
      // Live ROOT round: prefer the bootstrap's board (realtime-fresh).
      const cur = data.current_round as Record<string, unknown> | null;
      const board =
        cur && (cur.id as number) === r.id
          ? (data.propositions ?? []).map((p) => ({
              id: p.id,
              content: propContent(p),
              participant_id: p.participant_id,
            }))
          : propsByRound[r.id];
      if (!board) {
        needRounds.push(r.id);
        pending = true;
        walkEnded = true;
        break;
      }
      const key = -r.id;
      const opened = choices[key];
      if (opened != null) {
        // An opinion was tapped open → drop into its thread.
        const chosen = board.find((p) => p.id === opened);
        pushCommitted(key, chosen?.content ?? "", opened, r.id);
        descended = true;
        leafProp = opened;
        break;
      }
      liveStop = { round: r, props: board, key };
      walkEnded = true;
      break;
    }
    const board = propsByRound[r.id];
    if (!board) {
      needRounds.push(r.id);
      pending = true;
      walkEnded = true;
      break;
    }
    const key = -r.id;
    const choice = choices[key];
    if (choice == null) {
      pushOptions(key, board);
      walkEnded = true;
      break;
    }
    const chosen = board.find((p) => p.id === choice);
    pushCommitted(key, chosen?.content ?? "", choice, r.id);
    lastWinner = r.winning_proposition_id;
    if (choice !== r.winning_proposition_id) {
      // Divergence: walk into the sibling's subtree.
      descended = true;
      leafProp = choice;
      break;
    }
  }

  // Tree era: after the last committed winner, or down a divergent branch.
  if (!walkEnded || descended) {
    let current = descended ? leafProp! : lastWinner;
    leafProp = null;
    for (let depth = 0; current != null && depth < 20; depth++) {
      const nb = nodes[current];
      if (!nb) {
        needNodes.push(current);
        pending = true;
        break;
      }
      const node = nb.node as Record<string, unknown> | null;
      // Repository mode (never_seals) is always alive — you can start a reply
      // thread anytime, regardless of the window phase. Only phase-gated chats
      // wait for the proposing window.
      const windowProposing = repository || nb.window_phase === "proposing";
      if (!node) {
        leafProp = current;
        leafWindowOpen = windowProposing;
        break;
      }
      const round = node.round as Record<string, unknown>;
      const sealed = round.completed_at != null;
      const roundLike: WalkRound = {
        id: round.id as number,
        cycle_id: node.cycle_id as number,
        custom_id: 1,
        phase: round.phase as string,
        completed_at: (round.completed_at as string | null) ?? null,
        winning_proposition_id:
          (round.winning_proposition_id as number | null) ?? null,
        phase_started_at: (round.phase_started_at as string | null) ?? null,
        phase_ends_at: (round.phase_ends_at as string | null) ?? null,
      };
      if (!sealed) {
        // Route the node's list through getRankedProps (propsByRound), same as
        // sealed — it's SCORE-RANKED and carries the score. Using
        // node.propositions here rendered CHRONOLOGICAL order under "ranked"
        // labels (a node's "#1" was just its first reply). Wait for it to load.
        const board = propsByRound[roundLike.id];
        if (!board) {
          needRounds.push(roundLike.id);
          pending = true;
          break;
        }
        const opened = choices[current];
        if (opened != null) {
          const chosen = board.find((p) => p.id === opened);
          pushCommitted(current, chosen?.content ?? "", opened, roundLike.id);
          current = opened;
          continue;
        }
        liveStop = { round: roundLike, props: board, key: current };
        break;
      }
      const board = propsByRound[roundLike.id];
      if (!board) {
        needRounds.push(roundLike.id);
        pending = true;
        break;
      }
      const key = current;
      const choice = choices[key];
      if (choice == null) {
        pushOptions(key, board);
        break;
      }
      const chosen = board.find((p) => p.id === choice);
      pushCommitted(key, chosen?.content ?? "", choice, roundLike.id);
      current = choice;
    }
  }

  return {
    steps,
    chain,
    liveStop,
    leafProp,
    leafWindowOpen,
    pending,
    needRounds,
    needNodes,
  };
}
