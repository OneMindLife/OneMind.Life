// Port of lib/services/matches/match_pair_selector.dart — the pure, stateless
// next-pair chooser for matches (pairwise) rating. Enforces the equal-exposure
// invariant: a match only ever pairs two propositions the user has seen the same
// number of times (no novelty/mere-exposure advantage). See
// docs/MATCHES_RATING_MODE_SPEC.md §3.1.

export type MatchObjective = "winner_only" | "full_rank";

export type Rateable = { id: number; content: string };

export type PriorVote = {
  winnerId: number;
  loserId: number;
  isTie?: boolean;
  isSkip?: boolean;
};

export type MatchPair = {
  top: Rateable;
  bottom: Rateable;
  exposureBalanced: boolean;
};

const MAX_COMPARISONS = 12;

function pairKey(a: number, b: number): string {
  return a < b ? `${a}:${b}` : `${b}:${a}`;
}

function pickLowest(pairs: number[][]): number[] | null {
  if (pairs.length === 0) return null;
  pairs.sort((x, y) => x[2] - y[2]);
  const minKey = pairs[0][2];
  const tied = pairs.filter((p) => p[2] === minKey);
  return tied[Math.floor(Math.random() * tied.length)];
}

// How recently the user saw a prop = the LAST index it appears at in their vote
// history. -1 = never seen; higher = more recent.
function lastSeenIndex(id: number, priorVotes: PriorVote[]): number {
  for (let i = priorVotes.length - 1; i >= 0; i--) {
    if (priorVotes[i].winnerId === id || priorVotes[i].loserId === id) return i;
  }
  return -1;
}

// Did the user actively PICK this prop (a winner in a decisive comparison)?
function votedFor(id: number, priorVotes: PriorVote[]): boolean {
  return priorVotes.some((v) => v.winnerId === id && !v.isTie && !v.isSkip);
}

// Order the pair so the option the user saw MORE RECENTLY sits at the BOTTOM and
// the one seen longest ago (or never) sits at the TOP. This stops a voter from
// reflexively re-clicking the just-seen option at the top without reading the
// other — it forces the eye onto the newer/unseen idea first. Tie on recency
// (e.g. both unseen): the one they actually voted for goes to the bottom.
function buildPair(
  byId: Map<number, Rateable>,
  a: number,
  b: number,
  balanced: boolean,
  priorVotes: PriorVote[],
): MatchPair {
  const pa = byId.get(a)!;
  const pb = byId.get(b)!;
  const ra = lastSeenIndex(a, priorVotes);
  const rb = lastSeenIndex(b, priorVotes);
  let aAtBottom: boolean;
  if (ra !== rb) {
    aAtBottom = ra > rb; // a seen more recently → a sinks to the bottom
  } else {
    aAtBottom = votedFor(a, priorVotes) && !votedFor(b, priorVotes);
  }
  return {
    top: aAtBottom ? pb : pa,
    bottom: aAtBottom ? pa : pb,
    exposureBalanced: balanced,
  };
}

/// Returns the next pair to show, or null when the user is done (objective
/// satisfied, no useful pair left, or budget hit). `rateable` must already
/// EXCLUDE the user's own proposition(s).
export function nextPair(
  rateable: Rateable[],
  priorVotes: PriorVote[],
  objective: MatchObjective,
): MatchPair | null {
  if (rateable.length < 2) return null;
  if (priorVotes.length >= MAX_COMPARISONS) return null;

  const byId = new Map<number, Rateable>(rateable.map((p) => [p.id, p]));
  const ids = [...byId.keys()];

  const exposure = new Map<number, number>(ids.map((id) => [id, 0]));
  const faced = new Set<string>();
  const eliminated = new Set<number>();
  for (const v of priorVotes) {
    if (exposure.has(v.winnerId))
      exposure.set(v.winnerId, exposure.get(v.winnerId)! + 1);
    if (exposure.has(v.loserId))
      exposure.set(v.loserId, exposure.get(v.loserId)! + 1);
    faced.add(pairKey(v.winnerId, v.loserId));
    // Only a real, decisive vote eliminates the loser. Ties/skips carry no
    // ordering signal (but still count as faced + exposure above).
    if (!v.isTie && !v.isSkip) eliminated.add(v.loserId);
  }

  const active =
    objective === "winner_only"
      ? ids.filter((id) => !eliminated.has(id))
      : ids;

  if (objective === "winner_only" && active.length <= 1) return null;

  const equalPairs: number[][] = []; // [a, b, level]
  const diffOnePairs: number[][] = []; // [a, b, combinedExposure]
  for (let i = 0; i < active.length; i++) {
    for (let j = i + 1; j < active.length; j++) {
      const a = active[i];
      const b = active[j];
      if (faced.has(pairKey(a, b))) continue;
      const ea = exposure.get(a)!;
      const eb = exposure.get(b)!;
      if (ea === eb) equalPairs.push([a, b, ea]);
      else if (Math.abs(ea - eb) === 1) diffOnePairs.push([a, b, ea + eb]);
    }
  }

  const equal = pickLowest(equalPairs);
  if (equal) return buildPair(byId, equal[0], equal[1], true, priorVotes);

  const diffOne = pickLowest(diffOnePairs);
  if (diffOne) return buildPair(byId, diffOne[0], diffOne[1], false, priorVotes);

  return null; // nothing useful left → done
}
