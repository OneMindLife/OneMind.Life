import { describe, expect, it } from "vitest";
import {
  comparisonSort,
  highlightRanges,
  highlightSegments,
  liveStandings,
  pendingMatches,
  pickGlobalPair,
  scoreBoard,
  similarProps,
  voterCountsByProp,
} from "./treeChat";

// Ports of the Flutter unit suite (test/screens/chat/widgets/
// similar_props_test.dart) so both clients filter/highlight identically.

const board = [
  { id: 1, content: "Pizza night with the team" },
  { id: 2, content: "Go hiking on Saturday" },
  { id: 3, content: "Order pizza and watch a movie" },
  { id: 4, content: "Weekly game night" },
];

const ids = (r: Array<{ id: number }>) => r.map((p) => p.id);

describe("pendingMatches", () => {
  it("pairs two unseen opinions per match (floor of half)", () => {
    expect(pendingMatches(0)).toBe(0);
    expect(pendingMatches(1)).toBe(0); // a lone opinion can't form a pair
    expect(pendingMatches(2)).toBe(1);
    expect(pendingMatches(3)).toBe(1); // leftover strands, still 1 match
    expect(pendingMatches(4)).toBe(2);
    expect(pendingMatches(10)).toBe(5);
  });
  it("floors negatives to 0", () => {
    expect(pendingMatches(-3)).toBe(0);
  });
});

describe("similarProps", () => {
  it("empty query matches nothing", () => {
    expect(similarProps(board, "")).toEqual([]);
    expect(similarProps(board, "   ")).toEqual([]);
  });

  it("token match finds the overlapping takes only", () => {
    const result = ids(similarProps(board, "pizza"));
    expect(result).toContain(1);
    expect(result).toContain(3);
    expect(result).not.toContain(2);
    expect(result).not.toContain(4);
  });

  it("whole-phrase containment ranks above scattered token overlap", () => {
    const result = ids(similarProps(board, "game night"));
    expect(result[0]).toBe(4);
    expect(result).toContain(1);
  });

  it("is case- and punctuation-insensitive", () => {
    const result = ids(similarProps(board, "PIZZA!!!"));
    expect(result).toContain(1);
    expect(result).toContain(3);
  });

  it("prefix typing matches longer words (hik → hiking)", () => {
    expect(ids(similarProps(board, "hik"))).toEqual([2]);
  });

  it("no overlap → empty result", () => {
    expect(similarProps(board, "zqxv")).toEqual([]);
  });

  it("short noise tokens (1 char) are ignored", () => {
    expect(similarProps(board, "a")).toEqual([]);
  });

  it("stopwords carry no similarity signal", () => {
    // A normal sentence built of function words must not match the board.
    expect(similarProps(board, "the car is going to the place")).toEqual([]);
    // ...but real signal tokens still do.
    expect(ids(similarProps(board, "is the pizza good"))).toContain(1);
  });

  it("handles empty contents without throwing", () => {
    const messy = [
      { id: 1, content: "" },
      { id: 3, content: "real take" },
    ];
    expect(ids(similarProps(messy, "real"))).toEqual([3]);
  });
});

describe("highlightRanges / highlightSegments", () => {
  const marked = (content: string, query: string) =>
    highlightSegments(content, query)
      .map((s) => (s.hit ? `[${s.text}]` : s.text))
      .join("");

  it("marks exact token matches, preserving original casing", () => {
    expect(marked("Pizza night with the team", "pizza")).toBe(
      "[Pizza] night with the team",
    );
  });

  it("marks every matched word across the take", () => {
    // "game night" appears verbatim (merged into one span); the second "game"
    // is a separate token match.
    expect(marked("game night is game time", "game night")).toBe(
      "[game night] is [game] time",
    );
  });

  it("highlights a full phrase incl. stopwords when it appears verbatim", () => {
    // Regression: "that"/"is" are stopwords, so the token pass alone would mark
    // only "true". The whole-phrase pass lights up the entire verbatim phrase.
    expect(marked("That is true", "that is true")).toBe("[That is true]");
    expect(marked("Well, that is true.", "that is true")).toBe(
      "Well, [that is true].",
    );
  });

  it("falls back to token highlights when the phrase is not contiguous", () => {
    // No verbatim "game night" run → only the signal tokens light up.
    expect(marked("game on a quiet night", "game night")).toBe(
      "[game] on a quiet [night]",
    );
  });

  it("marks prefix matches (hik → hiking)", () => {
    expect(marked("Go hiking on Saturday", "hik")).toBe(
      "Go [hiking] on Saturday",
    );
  });

  it("ignores punctuation in the query", () => {
    expect(marked("Order pizza and watch a movie", "PIZZA!!!")).toBe(
      "Order [pizza] and watch a movie",
    );
  });

  it("no matches → single plain segment / no ranges", () => {
    expect(highlightRanges("Go hiking on Saturday", "zqxv")).toEqual([]);
    expect(highlightRanges("Go hiking on Saturday", "")).toEqual([]);
    expect(highlightRanges("Go hiking on Saturday", "a")).toEqual([]);
    expect(highlightSegments("Go hiking", "zqxv")).toEqual([
      { text: "Go hiking", hit: false },
    ]);
  });

  it("ranges are in bounds, ascending, non-overlapping", () => {
    const content = "pizza pizza pizza";
    const ranges = highlightRanges(content, "pizza");
    expect(ranges).toHaveLength(3);
    let prevEnd = 0;
    for (const [start, end] of ranges) {
      expect(start).toBeGreaterThanOrEqual(prevEnd);
      expect(end).toBeLessThanOrEqual(content.length);
      expect(content.slice(start, end)).toBe("pizza");
      prevEnd = end;
    }
  });
});

// Port of the Dart liveStandings suite — win 1, tie ½ both sides, skip 0,
// stable order for equal scores.
describe("liveStandings", () => {
  const vote = (
    w: number,
    l: number,
    opts: { tie?: boolean; skip?: boolean } = {},
  ) => ({
    winnerId: w,
    loserId: l,
    isTie: opts.tie ?? false,
    isSkip: opts.skip ?? false,
  });
  const props = [
    { id: 1, content: "A" },
    { id: 2, content: "B" },
    { id: 3, content: "C" },
  ];

  it("no votes → incoming order preserved", () => {
    expect(ids(liveStandings(props, []))).toEqual([1, 2, 3]);
  });

  it("wins re-rank; ties within score keep incoming order", () => {
    const result = liveStandings(props, [vote(3, 1), vote(3, 1), vote(2, 1)]);
    expect(ids(result)).toEqual([3, 2, 1]);
  });

  it("a tie gives half a point to BOTH sides", () => {
    expect(ids(liveStandings(props, [vote(2, 3, { tie: true })]))).toEqual([
      2, 3, 1,
    ]);
  });

  it("skips count nothing", () => {
    expect(ids(liveStandings(props, [vote(3, 1, { skip: true })]))).toEqual([
      1, 2, 3,
    ]);
  });

  it("votes for unknown props are ignored gracefully", () => {
    expect(ids(liveStandings(props, [vote(99, 1), vote(2, 98)]))).toEqual([
      2, 1, 3,
    ]);
  });

  it("does not mutate the input list", () => {
    const input = [...props];
    liveStandings(input, [vote(3, 1)]);
    expect(input).toEqual(props);
  });
});


// ── Collaborative sorting: the score model + the attention router ──────────
describe("scoreBoard", () => {
  const vote = (
    w: number,
    l: number,
    opts: { tie?: boolean; skip?: boolean } = {},
  ) => ({
    winnerId: w,
    loserId: l,
    isTie: opts.tie ?? false,
    isSkip: opts.skip ?? false,
  });
  const props = [{ id: 1 }, { id: 2 }, { id: 3 }];

  it("no votes → everyone at 0.5, incoming order", () => {
    const r = scoreBoard(props, []);
    expect(r.map((x) => x.prop.id)).toEqual([1, 2, 3]);
    expect(r.every((x) => x.score === 0.5)).toBe(true);
  });

  it("winners rise, losers sink (smoothed win rate)", () => {
    const r = scoreBoard(props, [vote(3, 1), vote(3, 1)]);
    expect(r[0].prop.id).toBe(3); // 3/4 = 0.75
    expect(r[2].prop.id).toBe(1); // 1/4 = 0.25
    expect(r[1].prop.id).toBe(2); // untouched 0.5 sits between
  });

  it("unplayed items sit BETWEEN proven winners and losers", () => {
    const r = scoreBoard(props, [vote(1, 2)]);
    expect(r.map((x) => x.prop.id)).toEqual([1, 3, 2]);
  });

  it("skips carry no information", () => {
    const r = scoreBoard(props, [vote(3, 1, { skip: true })]);
    expect(r.every((x) => x.score === 0.5)).toBe(true);
  });
});

describe("comparisonSort (head-to-head instant sort)", () => {
  const vote = (
    w: number,
    l: number,
    opts: { tie?: boolean; skip?: boolean } = {},
  ) => ({
    winnerId: w,
    loserId: l,
    isTie: opts.tie ?? false,
    isSkip: opts.skip ?? false,
  });
  const ids = (r: { id: number }[]) => r.map((x) => x.id);
  const props = [{ id: 1 }, { id: 2 }, { id: 3 }];

  it("no votes → incoming order preserved", () => {
    expect(ids(comparisonSort(props, []))).toEqual([1, 2, 3]);
  });

  it("SWAP ON ANY MARGIN: a lone 1-0 head-to-head decides order", () => {
    // 2 beat 1 exactly once → 2 ranks above 1.
    expect(ids(comparisonSort([{ id: 1 }, { id: 2 }], [vote(2, 1)]))).toEqual([
      2, 1,
    ]);
  });

  it("CASCADE (Joel's example): c beats b then a → c rises to #1", () => {
    // a=10 #1, b=20 #2, c=30 #3 initially by prior votes; then c beats b and a
    // head-to-head → c bubbles to the top.
    const abc = [{ id: 10 }, { id: 20 }, { id: 30 }];
    const votes = [
      vote(10, 20), // a > b
      vote(20, 30), // b > c  (start: a > b > c)
      vote(30, 20), // c beats b
      vote(30, 20), // c beats b again → c above b
      vote(30, 10), // c beats a → c to #1
    ];
    expect(ids(comparisonSort(abc, votes))[0]).toBe(30);
  });

  it("CUMULATIVE-INDEPENDENT: a direct loss outranks a pile of easy wins", () => {
    // 1 racks up 5 wins over the weak take 3, but LOST head-to-head to 2 once.
    // Win-total (scoreBoard) would rank 1 first; the comparison sort must put
    // 2 above 1 — position is relative, not cumulative.
    const votes = [
      vote(1, 3),
      vote(1, 3),
      vote(1, 3),
      vote(1, 3),
      vote(1, 3),
      vote(2, 1), // 2 beat 1 head-to-head
    ];
    expect(ids(comparisonSort(props, votes))).toEqual([2, 1, 3]);
    // Contrast: the old win-rate model ranks the pile-of-wins idea first.
    expect(scoreBoard(props, votes)[0].prop.id).toBe(1);
  });

  it("NON-TRANSITIVE cycle terminates deterministically (no oscillation)", () => {
    const cyc = [
      vote(1, 2), // 1 > 2
      vote(2, 3), // 2 > 3
      vote(3, 1), // 3 > 1  → rock-paper-scissors
    ];
    const a = comparisonSort(props, cyc);
    const b = comparisonSort(props, cyc);
    expect(a).toHaveLength(3);
    expect(ids(a)).toEqual(ids(b)); // stable, doesn't loop forever
  });

  it("ties and skips carry no margin (never move anything)", () => {
    expect(
      ids(comparisonSort(props, [vote(2, 1, { tie: true }), vote(3, 1, { skip: true })])),
    ).toEqual([1, 2, 3]);
  });
});

describe("pickGlobalPair (the attention router — strict fresh-only)", () => {
  const vote = (
    w: number,
    l: number,
    opts: { tie?: boolean; skip?: boolean } = {},
  ) => ({
    winnerId: w,
    loserId: l,
    isTie: opts.tie ?? false,
    isSkip: opts.skip ?? false,
  });
  const props = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }];
  const none = new Set<number>();

  it("null when fewer than 2 props", () => {
    expect(pickGlobalPair([{ id: 1 }], [], [], none)).toBeNull();
  });

  it("NOVELTY: never shows a take the voter has seen, in ANY match", () => {
    const mine = [vote(1, 2)];
    const p = pickGlobalPair(props, mine, mine, none)!;
    expect([p.top.id, p.bottom.id].sort()).toEqual([3, 4]);
  });

  it("CSI GATE: once all OTHERS are judged, returns null — no own-idea filler", () => {
    // 3 others (1,2,3) all seen, 1 mine (9). Enough others exist (>=2), so the
    // voter is DONE — we do NOT fall back to pairing them against their own take.
    // Mirrors the Vote badge, which counts unseen OTHERS only.
    const withMine = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 9 }];
    const seen = [vote(1, 2), vote(2, 3), vote(1, 3)];
    expect(pickGlobalPair(withMine, seen, seen, new Set([9]))).toBeNull();
  });

  it("CSI GATE: in a tiny pool (only 1 other), still includes own take", () => {
    // Only 1 non-own prop → a fresh others-only pair is impossible. Here CSI
    // kicks in so a lone early voter still gets a match instead of a dead end.
    const p = pickGlobalPair([{ id: 1 }, { id: 9 }], [], [], new Set([9]))!;
    expect(p).not.toBeNull();
    expect([p.top.id, p.bottom.id].sort()).toEqual([1, 9]);
  });

  it("DONE: once no fresh pair remains, the voter just watches the list", () => {
    // Saw 1v2 and 3v4 → every take seen once → no redundancy, done.
    const mine = [vote(1, 2), vote(3, 4)];
    expect(pickGlobalPair(props, mine, mine, none)).toBeNull();
    // A lone unseen take can't pair with seen ones either.
    const three = [{ id: 1 }, { id: 2 }, { id: 3 }];
    const saw = [vote(1, 2)];
    expect(pickGlobalPair(three, saw, saw, none)).toBeNull();
  });

  it("LIMITLESS: two new arrivals reopen the feed after done", () => {
    const mine = [vote(1, 2), vote(3, 4)];
    const grown = [...props, { id: 5 }, { id: 6 }];
    const p = pickGlobalPair(grown, mine, mine, none)!;
    expect([p.top.id, p.bottom.id].sort()).toEqual([5, 6]);
  });

  it("prefers ADJACENT pairs among fresh candidates", () => {
    // Others' votes: 3 beat 1 twice → order 3 > 2,4 > 1. All fresh for ME;
    // the chosen pair must be an adjacent boundary.
    const all = [vote(3, 1), vote(3, 1)];
    const p = pickGlobalPair(props, all, [], none)!;
    const order = [3, 2, 4, 1];
    const rankGap = Math.abs(
      order.indexOf(p.top.id) - order.indexOf(p.bottom.id),
    );
    expect(rankGap).toBe(1);
  });

  it("JOEL'S EXAMPLE: a#1 vs b#2 has 2 votes, b#2 vs c#3 has 1 → serve b vs c", () => {
    // Others' votes: a beat b twice (pair a-b: 2 votes), b beat c once
    // (pair b-c: 1 vote). Current order: a > b > c. A fresh voter must be
    // routed to the adjacent boundary with the LEAST votes: b vs c.
    const three = [{ id: 10 }, { id: 20 }, { id: 30 }]; // a, b, c
    const all = [vote(10, 20), vote(10, 20), vote(20, 30)];
    const p = pickGlobalPair(three, all, [], none)!;
    expect([p.top.id, p.bottom.id].sort()).toEqual([20, 30]);
  });

  it("among adjacent fresh pairs, prefers the LEAST-judged one", () => {
    const all = [vote(1, 2), vote(1, 2), vote(1, 2)];
    const p = pickGlobalPair(props, all, [], none)!;
    const k = new Set([p.top.id, p.bottom.id]);
    expect(k.has(1) && k.has(2)).toBe(false);
  });

  it("excludes my own takes (CSI) unless the pool starves", () => {
    const mine = new Set([1, 2]);
    const p = pickGlobalPair(props, [], [], mine)!;
    expect([p.top.id, p.bottom.id].sort()).toEqual([3, 4]);
    const tiny = [{ id: 1 }, { id: 2 }];
    const p2 = pickGlobalPair(tiny, [], [], mine)!;
    expect([p2.top.id, p2.bottom.id].sort()).toEqual([1, 2]);
  });

  it("presentation order is STABLE per voter+pair (no per-render flicker)", () => {
    const a = pickGlobalPair(props, [], [], none, 7)!;
    const b = pickGlobalPair(props, [], [], none, 7)!;
    expect([a.top.id, a.bottom.id]).toEqual([b.top.id, b.bottom.id]);
  });

  it("presentation order is BALANCED across voters (no position bias)", () => {
    // The same tiny board across many seeds: both orientations must occur,
    // roughly evenly (catches parity-degenerate hashes).
    const tiny = [{ id: 1 }, { id: 2 }];
    let firstOnTop = 0;
    for (let seed = 0; seed < 64; seed++) {
      const p = pickGlobalPair(tiny, [], [], none, seed)!;
      if (p.top.id === 1) firstOnTop++;
    }
    expect(firstOnTop).toBeGreaterThan(16);
    expect(firstOnTop).toBeLessThan(48);
  });

  it("CONSECUTIVE-id pairs do not all share one orientation (parity trap)", () => {
    // For a FIXED voter, consecutive-id pairs (i, i+1) must not uniformly
    // orient the same way — the exact failure mode of a parity hash.
    const tops = new Set<string>();
    for (let base = 100; base < 132; base += 2) {
      const two = [{ id: base }, { id: base + 1 }];
      const p = pickGlobalPair(two, [], [], none, 7)!;
      tops.add(p.top.id === base ? "low" : "high");
    }
    expect(tops.size).toBe(2);
  });

  it("CONCURRENCY: tied candidates spread across different seeds", () => {
    const a = pickGlobalPair(props, [], [], none, 1)!;
    const b = pickGlobalPair(props, [], [], none, 2)!;
    const ka = [a.top.id, a.bottom.id].sort().join("_");
    const kb = [b.top.id, b.bottom.id].sort().join("_");
    expect(ka).not.toBe(kb);
  });

  it("skips count toward exposure (novelty holds through skips)", () => {
    const mine = [vote(1, 2, { skip: true })];
    const p = pickGlobalPair(props, mine, mine, none)!;
    expect([p.top.id, p.bottom.id].sort()).toEqual([3, 4]);
  });
});

describe("voterCountsByProp (per-idea social proof)", () => {
  it("credits both sides of a matchup, distinct voter per prop", () => {
    const votes = [
      { winnerId: 1, loserId: 2, voterId: 10 },
      { winnerId: 2, loserId: 3, voterId: 11 },
    ];
    const m = voterCountsByProp(votes);
    expect(m.get(1)).toBe(1); // voter 10
    expect(m.get(2)).toBe(2); // voters 10 and 11
    expect(m.get(3)).toBe(1); // voter 11
  });

  it("counts a person once per prop across many matchups", () => {
    const votes = [
      { winnerId: 1, loserId: 2, voterId: 10 },
      { winnerId: 1, loserId: 3, voterId: 10 }, // same voter, prop 1 again
    ];
    expect(voterCountsByProp(votes).get(1)).toBe(1);
  });

  it("ignores skips and null voters", () => {
    const votes = [
      { winnerId: 1, loserId: 2, voterId: 10, isSkip: true },
      { winnerId: 1, loserId: 2, voterId: null },
      { winnerId: 1, loserId: 2, voterId: 12 },
    ];
    const m = voterCountsByProp(votes);
    expect(m.get(1)).toBe(1); // only voter 12
    expect(m.get(2)).toBe(1);
  });

  it("empty input → empty map", () => {
    expect(voterCountsByProp([]).size).toBe(0);
  });
});

describe("similarProps — fuzzy (trigram) matching", () => {
  const fb = [
    { id: 1, content: "Expensive weddings are overrated" },
    { id: 2, content: "We need voting reform now" },
    { id: 3, content: "Artificial intelligence cannot dream" },
    { id: 4, content: "Go hiking on the weekend" },
  ];
  const fids = (r: Array<{ id: number }>) => r.map((p) => p.id);

  it("tolerates typos (wedings → weddings)", () => {
    expect(fids(similarProps(fb, "wedings"))).toContain(1);
  });
  it("matches morphological variants (vote → voting)", () => {
    expect(fids(similarProps(fb, "vote"))).toContain(2);
  });
  it("matches a partial/typo'd longer word (inteligence → intelligence)", () => {
    expect(fids(similarProps(fb, "inteligence"))).toContain(3);
  });
  it("still returns nothing for pure gibberish", () => {
    expect(similarProps(fb, "zqxjkw")).toEqual([]);
  });
  it("does not fuzzy-match unrelated words", () => {
    // "wedding"-ish must not pull in hiking/AI/voting.
    expect(fids(similarProps(fb, "wedings"))).toEqual([1]);
  });
});
