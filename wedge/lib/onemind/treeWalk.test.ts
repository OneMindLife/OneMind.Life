import { describe, expect, it } from "vitest";
import { walkTree, type NodeSnapshot, type WalkInput } from "./treeWalk";
import type { Bootstrap, WalkProp, WalkRound } from "./chat";

// ── Fixtures ─────────────────────────────────────────────────────────────────
const round = (over: Partial<WalkRound> & { id: number }): WalkRound => ({
  cycle_id: 1,
  custom_id: 1,
  phase: "proposing",
  completed_at: null,
  winning_proposition_id: null,
  phase_started_at: null,
  phase_ends_at: null,
  ...over,
});

const prop = (id: number, content = `p${id}`, participant = 1): WalkProp => ({
  id,
  content,
  participant_id: participant,
});

// Only current_round + propositions are read; cast a minimal shape.
const boot = (over: Partial<Bootstrap> = {}): Bootstrap =>
  ({ current_round: null, propositions: [], ...over }) as unknown as Bootstrap;

const base = (over: Partial<WalkInput> = {}): WalkInput => ({
  roots: [],
  data: boot(),
  propsByRound: {},
  nodes: {},
  choices: {},
  repository: true,
  ...over,
});

describe("walkTree (the /g navigable-web core)", () => {
  it("nothing loaded → empty frame, nothing pending", () => {
    const r = walkTree(base());
    expect(r.steps).toEqual([]);
    expect(r.chain).toEqual([]);
    expect(r.liveStop).toBeNull();
    expect(r.leafProp).toBeNull();
    expect(r.pending).toBe(false);
    expect(r.needRounds).toEqual([]);
    expect(r.needNodes).toEqual([]);
  });

  it("live root, board from bootstrap → liveStop with the mapped board", () => {
    const r = round({ id: 5 });
    const res = walkTree(
      base({
        roots: [r],
        data: boot({
          current_round: { id: 5 } as never,
          propositions: [
            { id: 10, content: "A", participant_id: 2 } as never,
            { id: 11, content: "B", participant_id: null } as never,
          ],
        }),
      }),
    );
    expect(res.liveStop).not.toBeNull();
    expect(res.liveStop!.round.id).toBe(5);
    expect(res.liveStop!.key).toBe(-5);
    expect(res.liveStop!.props.map((p) => p.id)).toEqual([10, 11]);
    expect(res.pending).toBe(false);
    expect(res.steps).toEqual([]);
  });

  it("live root, translated content wins in the mapped board", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5 })],
        data: boot({
          current_round: { id: 5 } as never,
          propositions: [
            { id: 10, content: "hola", content_translated: "hello", participant_id: 2 } as never,
          ],
        }),
      }),
    );
    expect(res.liveStop!.props[0].content).toBe("hello");
  });

  it("live root, board not loaded → requests it and pends", () => {
    // current_round doesn't match this root and propsByRound is empty.
    const res = walkTree(base({ roots: [round({ id: 5 })] }));
    expect(res.needRounds).toEqual([5]);
    expect(res.pending).toBe(true);
    expect(res.liveStop).toBeNull();
  });

  it("sealed root, no choice → options list to render", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t" })],
        propsByRound: { 5: [prop(10), prop(11)] },
      }),
    );
    expect(res.steps).toEqual([
      { kind: "options", key: -5, options: [prop(10), prop(11)] },
    ]);
    expect(res.liveStop).toBeNull();
  });

  it("sealed root, choice == winner → committed card, descends into tree era", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t", winning_proposition_id: 10 })],
        propsByRound: { 5: [prop(10, "winner"), prop(11)] },
        choices: { [-5]: 10 },
        // node 10 not loaded → the tree era must request it.
      }),
    );
    expect(res.steps).toEqual([{ kind: "committed", key: -5, content: "winner" }]);
    expect(res.chain).toEqual([{ text: "winner", propId: 10, roundId: 5 }]);
    expect(res.needNodes).toEqual([10]);
    expect(res.pending).toBe(true);
  });

  it("sealed root, choice != winner → divergence walks the sibling subtree", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t", winning_proposition_id: 10 })],
        propsByRound: { 5: [prop(10), prop(11, "sibling")] },
        choices: { [-5]: 11 }, // picked the loser → descend into 11's tree
      }),
    );
    expect(res.steps).toEqual([{ kind: "committed", key: -5, content: "sibling" }]);
    expect(res.needNodes).toEqual([11]); // walks into 11, not the winner 10
    expect(res.pending).toBe(true);
  });

  it("empty leaf (node has no subround) → composer target + window flag", () => {
    const nodes: Record<number, NodeSnapshot> = {
      10: { node: null, window_phase: "rating" },
    };
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t", winning_proposition_id: 10 })],
        propsByRound: { 5: [prop(10, "w")] },
        choices: { [-5]: 10 },
        nodes,
        repository: false, // so window_phase governs
      }),
    );
    expect(res.leafProp).toBe(10);
    expect(res.leafWindowOpen).toBe(false); // rating, not proposing
    expect(res.liveStop).toBeNull();
  });

  it("repository mode forces the leaf window open regardless of phase", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t", winning_proposition_id: 10 })],
        propsByRound: { 5: [prop(10, "w")] },
        choices: { [-5]: 10 },
        nodes: { 10: { node: null, window_phase: "rating" } },
        repository: true,
      }),
    );
    expect(res.leafWindowOpen).toBe(true);
  });

  // A live node's list must be SCORE-RANKED (via propsByRound / getRankedProps),
  // NOT node.propositions (which is chronological). Two cases: waiting for the
  // ranked board, and using it once loaded — ignoring node.propositions' order.
  const liveNode = (over: Record<string, unknown> = {}): NodeSnapshot => ({
    cycle_id: 2,
    window_phase: "proposing",
    node: {
      round: { id: 99, phase: "proposing", completed_at: null },
      // node.propositions is CHRONOLOGICAL (20 then 21) — must be IGNORED.
      propositions: [
        { id: 20, content: "reply A", participant_id: 3 },
        { id: 21, content: "reply B", participant_id: null },
      ],
      ...over,
    },
  });

  it("live node, ranked board NOT loaded → requests it and pends (no chronological node.propositions fallback)", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t", winning_proposition_id: 10 })],
        propsByRound: { 5: [prop(10, "root win")] }, // node round 99 not loaded
        choices: { [-5]: 10 },
        nodes: { 10: liveNode() },
      }),
    );
    expect(res.chain).toEqual([{ text: "root win", propId: 10, roundId: 5 }]);
    expect(res.liveStop).toBeNull(); // does NOT render node.propositions
    expect(res.needRounds).toContain(99);
    expect(res.pending).toBe(true);
  });

  it("live node, ranked board loaded → liveStop uses the SCORE-RANKED board, not node.propositions order", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t", winning_proposition_id: 10 })],
        propsByRound: {
          5: [prop(10, "root win")],
          // getRankedProps order for the node round: 21 (score 90) before 20 (40).
          99: [
            { id: 21, content: "reply B", participant_id: null, score: 90 },
            { id: 20, content: "reply A", participant_id: 3, score: 40 },
          ],
        },
        choices: { [-5]: 10 },
        nodes: { 10: liveNode() },
      }),
    );
    expect(res.liveStop).not.toBeNull();
    expect(res.liveStop!.round.id).toBe(99);
    expect(res.liveStop!.key).toBe(10);
    // Score order (21,20) from propsByRound — NOT chronological (20,21).
    expect(res.liveStop!.props.map((p) => p.id)).toEqual([21, 20]);
    expect(res.liveStop!.props[0].score).toBe(90);
    expect(res.pending).toBe(false);
  });

  it("descending PAST a live node uses the ranked board to resolve the chosen opinion's text", () => {
    const res = walkTree(
      base({
        roots: [round({ id: 5, completed_at: "t", winning_proposition_id: 10 })],
        propsByRound: {
          5: [prop(10, "root win")],
          99: [
            { id: 21, content: "reply B", participant_id: null, score: 90 },
            { id: 20, content: "reply A", participant_id: 3, score: 40 },
          ],
        },
        choices: { [-5]: 10, 10: 21 }, // descend into reply B
        nodes: { 10: liveNode(), 21: { node: null, window_phase: "proposing" } },
      }),
    );
    // "reply B" (from the ranked board) is committed as the next spine card.
    expect(res.chain.map((c) => c.text)).toEqual(["root win", "reply B"]);
    expect(res.leafProp).toBe(21);
  });
});
