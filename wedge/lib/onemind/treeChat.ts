// Pure helpers for the /g/<code> tree-chat surface — the wedge rendering of
// the Flutter app's branching chat UI (lib/screens/chat/widgets/
// tree_stack_section.dart). Ports of the Dart `similarProps` /
// `highlightRanges` so the proposing feed filters and highlights identically
// on both clients. Kept React/Supabase-free for unit testing.

export type FeedProp = {
  id: number;
  content: string;
  participant_id?: number | null;
  is_agent?: boolean;
};

function normForMatch(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/// Function words carry no similarity signal — without this, typing a normal
/// sentence ("the car is going to the place") "matches" nearly every take on
/// the board via the/is/to/and.
const STOPWORDS = new Set([
  "the", "a", "an", "is", "are", "was", "were", "be", "been", "am",
  "i", "we", "you", "he", "she", "it", "they", "my", "our", "your",
  "to", "of", "in", "on", "at", "for", "with", "and", "or", "but",
  "that", "this", "these", "those", "as", "so", "if", "do", "does",
  "not", "no", "have", "has", "had", "will", "would", "should", "can",
  "think", "there", "here", "what", "which", "who", "how", "than",
]);

function signalTokens(norm: string): string[] {
  return norm.split(" ").filter((t) => t.length >= 2 && !STOPWORDS.has(t));
}

/// Fuzzy-match `query` against proposition contents (the similar-props search
/// under the proposing composer): whole-phrase containment scores highest,
/// then per-token exact and prefix matches. Returns matches best-first; empty
/// when nothing is similar. Mirrors the Dart implementation exactly.
/// Padded character trigrams of a word — the unit of fuzzy matching. Padding
/// (" abc ") makes prefixes/suffixes count, so "vote"/"voting" and typo
/// "wedings"/"weddings" share most trigrams.
function trigrams(s: string): Set<string> {
  const t = ` ${s} `;
  const out = new Set<string>();
  for (let i = 0; i < t.length - 2; i++) out.add(t.slice(i, i + 3));
  return out;
}

/// Sørensen–Dice similarity of two words on their trigrams (0..1). Cheap, no
/// deps, and forgiving of typos / morphological variants — the right primitive
/// for fuzzy-matching short opinion text.
function diceWord(a: string, b: string): number {
  if (a === b) return 1;
  if (a.length < 2 || b.length < 2) return 0;
  const A = trigrams(a);
  const B = trigrams(b);
  let inter = 0;
  for (const g of A) if (B.has(g)) inter++;
  return (2 * inter) / (A.size + B.size);
}

export function similarProps<T extends { content: string }>(
  props: T[],
  query: string,
): T[] {
  const q = normForMatch(query);
  if (!q) return [];
  const qTokens = signalTokens(q);
  const scored: Array<[T, number]> = [];
  for (const p of props) {
    const c = normForMatch(p.content ?? "");
    if (!c) continue;
    let score = 0;
    // Whole-phrase bonus only for queries with real signal — a 1-char
    // fragment is contained in nearly everything.
    if (q.length >= 2 && c.includes(q)) score += 3;
    const cWords = c.split(" ");
    const cSet = new Set(cWords);
    for (const t of qTokens) {
      if (cSet.has(t)) {
        score += 1; // exact token
        continue;
      }
      // Best fuzzy match of this token to any content word: prefix (stemming)
      // or trigram similarity (typos, variants). Partial credit scaled by how
      // close it is, so near-misses still surface and rank sensibly.
      let best = 0;
      for (const w of cWords) {
        if (w.length < 3) continue;
        if (w.startsWith(t) || t.startsWith(w)) {
          best = Math.max(best, 0.8);
        } else if (t.length >= 3) {
          best = Math.max(best, diceWord(t, w));
        }
      }
      if (best >= 0.4) score += best; // 0.45–0.8 for a fuzzy hit
    }
    if (score >= 0.4) scored.push([p, score]);
  }
  scored.sort((a, b) => b[1] - a[1]);
  return scored.map(([p]) => p);
}

/// Character ranges [start, end) of the words in `content` that the
/// similar-props search matched for `query` — same token rules as
/// `similarProps` (exact for 2+ chars, prefix for 3+), so the feed can
/// highlight exactly WHY a take was surfaced.
export function highlightRanges(
  content: string,
  query: string,
): Array<[number, number]> {
  const qNorm = normForMatch(query);
  if (!qNorm) return [];

  // Tokenize the content into words with their offsets in the ORIGINAL string,
  // reused by both the phrase pass and the token pass below.
  const cWords: Array<{ w: string; start: number; end: number }> = [];
  const re = /[a-z0-9]+/g;
  const lower = content.toLowerCase();
  let m: RegExpExecArray | null;
  while ((m = re.exec(lower)) !== null) {
    cWords.push({ w: m[0], start: m.index, end: m.index + m[0].length });
  }

  const ranges: Array<[number, number]> = [];

  // Token pass — mark each content word that matches a query signal token
  // (stopwords excluded). Same rules as `similarProps`: exact for 2+ chars,
  // prefix for 3+.
  const qTokens = signalTokens(qNorm);
  for (const cw of cWords) {
    const w = cw.w;
    const hit = qTokens.some(
      (t) =>
        w === t ||
        (t.length >= 3 &&
          w.length >= 3 &&
          (w.startsWith(t) || t.startsWith(w))),
    );
    if (hit) ranges.push([cw.start, cw.end]);
  }

  // Whole-phrase pass — mirrors the whole-phrase score bonus in `similarProps`
  // (`c.includes(q)`). Where the full query appears as a contiguous run of
  // words, add a span covering the ENTIRE run — including function words the
  // token pass skips. Merged with the token spans below, this is why typing
  // "that is true" lights up all of "That is true", not just "true", while
  // scattered token matches elsewhere still highlight.
  const qWords = qNorm.split(" ").filter(Boolean);
  if (qWords.length >= 2) {
    for (let i = 0; i + qWords.length <= cWords.length; i++) {
      let matched = true;
      for (let k = 0; k < qWords.length; k++) {
        if (cWords[i + k].w !== qWords[k]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        ranges.push([cWords[i].start, cWords[i + qWords.length - 1].end]);
      }
    }
  }

  if (ranges.length === 0) return [];

  // Merge overlapping/adjacent spans so the phrase span absorbs its constituent
  // token spans (and the spaces between), leaving clean, ordered ranges.
  ranges.sort((a, b) => a[0] - b[0]);
  const merged: Array<[number, number]> = [[...ranges[0]]];
  for (let j = 1; j < ranges.length; j++) {
    const last = merged[merged.length - 1];
    if (ranges[j][0] <= last[1]) {
      last[1] = Math.max(last[1], ranges[j][1]);
    } else {
      merged.push([...ranges[j]]);
    }
  }
  return merged;
}

/// Live standings for a voting round: `props` re-ranked by the pairwise
/// comparisons submitted so far across ALL raters — a win counts 1, a tie
/// counts ½ for both sides, skips count nothing. Stable: equal scores keep
/// the incoming order. Mirrors the Dart `liveStandings` exactly.
export function liveStandings<T extends { id: number }>(
  props: T[],
  votes: Array<{
    winnerId: number;
    loserId: number;
    isTie: boolean;
    isSkip: boolean;
  }>,
): T[] {
  const score = new Map<number, number>();
  for (const v of votes) {
    if (v.isSkip) continue;
    if (v.isTie) {
      score.set(v.winnerId, (score.get(v.winnerId) ?? 0) + 0.5);
      score.set(v.loserId, (score.get(v.loserId) ?? 0) + 0.5);
    } else {
      score.set(v.winnerId, (score.get(v.winnerId) ?? 0) + 1);
    }
  }
  return props
    .map((p, i) => [p, i] as const)
    .sort((a, b) => {
      const sa = score.get(a[0].id) ?? 0;
      const sb = score.get(b[0].id) ?? 0;
      if (sa !== sb) return sb - sa;
      return a[1] - b[1];
    })
    .map(([p]) => p);
}

/// Split `content` into alternating plain/highlighted segments for rendering.
export function highlightSegments(
  content: string,
  query: string,
): Array<{ text: string; hit: boolean }> {
  const ranges = highlightRanges(content, query);
  if (ranges.length === 0) return [{ text: content, hit: false }];
  const out: Array<{ text: string; hit: boolean }> = [];
  let cursor = 0;
  for (const [start, end] of ranges) {
    if (start > cursor) out.push({ text: content.slice(cursor, start), hit: false });
    out.push({ text: content.slice(start, end), hit: true });
    cursor = end;
  }
  if (cursor < content.length) out.push({ text: content.slice(cursor), hit: false });
  return out;
}

// ── Collaborative sorting (the global list + the attention router) ─────────
//
// The round's board is ONE shared list that every voter helps sort. Scores
// come from ALL votes (smoothed win rate — a cheap Bradley-Terry stand-in);
// the router hands each voter the comparison that reduces sorting
// uncertainty most: adjacent in the current order, least-judged, closest in
// score. Human attention is the scarce resource — spend it on the
// boundaries, not on re-verifying blowouts.

export type Vote = {
  winnerId: number;
  loserId: number;
  isTie: boolean;
  isSkip: boolean;
};

export type ScoredProp<T> = { prop: T; score: number; games: number };

/// Smoothed win rate per prop from ALL votes: (wins + 1) / (games + 2)
/// (Laplace) — unplayed props sit at 0.5, between proven winners and losers.
/// Ties count half. Sort: score desc, then games desc (proven beats
/// unproven at equal rate), then incoming order (stable).
export function scoreBoard<T extends { id: number }>(
  props: T[],
  votes: Vote[],
): ScoredProp<T>[] {
  const wins = new Map<number, number>();
  const games = new Map<number, number>();
  for (const v of votes) {
    if (v.isSkip) continue;
    games.set(v.winnerId, (games.get(v.winnerId) ?? 0) + 1);
    games.set(v.loserId, (games.get(v.loserId) ?? 0) + 1);
    if (v.isTie) {
      wins.set(v.winnerId, (wins.get(v.winnerId) ?? 0) + 0.5);
      wins.set(v.loserId, (wins.get(v.loserId) ?? 0) + 0.5);
    } else {
      wins.set(v.winnerId, (wins.get(v.winnerId) ?? 0) + 1);
    }
  }
  return props
    .map((prop, i) => {
      const g = games.get(prop.id) ?? 0;
      const w = wins.get(prop.id) ?? 0;
      return { prop, score: (w + 1) / (g + 2), games: g, _i: i };
    })
    .sort((a, b) => {
      if (a.score !== b.score) return b.score - a.score;
      if (a.games !== b.games) return b.games - a.games;
      return a._i - b._i;
    })
    .map(({ prop, score, games: g }) => ({ prop, score, games: g }));
}

/// The "instant sort": a head-to-head COMPARISON sort, not a cumulative score.
/// A proposition's position comes from its DIRECT head-to-head result against
/// its neighbours — decided by the votes on that exact pair, swapping on ANY
/// margin (a lone 1-0 is enough) — NOT from a global win total. A win over the
/// item above you bubbles you up past it, cascading until you meet someone who
/// beats you head-to-head. So an idea with many wins over weak takes still
/// sits BELOW one that beat it directly (that's the whole point — see the
/// "cumulative-independent" test).
///
/// Seeded by Copeland (net head-to-head matchups won across the field) so the
/// order is deterministic and TERMINATES even when the crowd is non-transitive
/// (a>b, b>c, c>a — a real possibility among near-tied leaders); the adjacent
/// bubble passes then enforce every neighbour matchup. Ties and skips carry no
/// margin, so they never move anything.
export function comparisonSort<T extends { id: number }>(
  props: T[],
  votes: Vote[],
): T[] {
  // h2h[x][y] = times x beat y head-to-head (ties/skips excluded — no margin).
  const h2h = new Map<number, Map<number, number>>();
  for (const v of votes) {
    if (v.isSkip || v.isTie) continue;
    let m = h2h.get(v.winnerId);
    if (!m) {
      m = new Map();
      h2h.set(v.winnerId, m);
    }
    m.set(v.loserId, (m.get(v.loserId) ?? 0) + 1);
  }
  const beat = (x: number, y: number) => h2h.get(x)?.get(y) ?? 0;
  // >0 ⇒ x ranks above y (won the direct matchup); <0 below; 0 undecided.
  const cmp = (x: number, y: number) => beat(x, y) - beat(y, x);

  // Copeland seed: (# opponents beaten) − (# opponents lost to), head-to-head.
  const copeland = new Map<number, number>();
  for (const p of props) {
    let c = 0;
    for (const q of props) {
      if (p.id === q.id) continue;
      const d = cmp(p.id, q.id);
      c += d > 0 ? 1 : d < 0 ? -1 : 0;
    }
    copeland.set(p.id, c);
  }
  const order = props
    .map((p, i) => ({ p, i }))
    .sort(
      (a, b) => (copeland.get(b.p.id)! - copeland.get(a.p.id)!) || a.i - b.i,
    )
    .map((x) => x.p);

  // Adjacent bubble passes: if the lower neighbour beat the upper one
  // head-to-head, it rises past it. Bounded to n passes ⇒ always terminates
  // (a non-transitive cycle settles to a fixed order instead of oscillating).
  const n = order.length;
  for (let pass = 0; pass < n; pass++) {
    let swapped = false;
    for (let i = 0; i < n - 1; i++) {
      if (cmp(order[i + 1].id, order[i].id) > 0) {
        const t = order[i];
        order[i] = order[i + 1];
        order[i + 1] = t;
        swapped = true;
      }
    }
    if (!swapped) break;
  }
  return order;
}

function pairKey(a: number, b: number): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

/// How many head-to-head MATCHES a voter will actually be served from a pool of
/// `unseenCount` still-unjudged opinions. The strict-fresh router (pickGlobalPair)
/// pairs TWO unseen takes per match and each vote marks both seen, so the pool
/// drains two at a time — a lone leftover can't form a pair. This is the honest
/// "votes to cast" count behind the attention badges; the raw opinion count
/// nearly doubles it (10 opinions → 5 taps).
export function pendingMatches(unseenCount: number): number {
  return Math.max(0, Math.floor(unseenCount / 2));
}

/// The attention router: the next match for THIS voter, or null once no
/// FRESH pair remains. STRICT NOVELTY: both takes must be ones this voter
/// has never seen in any match (skips count as seen) — every vote is a new
/// experience, nothing is ever redundant. When the fresh pool runs dry the
/// voter is done and just watches the list sort; two new arrivals reopen
/// the feed automatically. Among fresh pairs, prefer the most informative
/// for the GLOBAL sort: adjacent in the current order, then fewest total
/// judgments, then smallest score gap. (CSI) own takes excluded unless that
/// starves the pool; the seed spreads simultaneous voters across tied
/// boundaries; presentation orientation is hash-randomized (position bias).
export function pickGlobalPair<T extends { id: number }>(
  props: T[],
  allVotes: Vote[],
  myVotes: Vote[],
  myPropIds: Set<number>,
  seed = 0,
): { top: T; bottom: T } | null {
  if (props.length < 2) return null;
  // Adjacency is defined by the live comparison-sort order — spend attention on
  // neighbouring boundaries, where the head-to-head is closest.
  const order = comparisonSort(props, allVotes);
  const rankOf = new Map<number, number>();
  order.forEach((p, i) => rankOf.set(p.id, i));

  // Every take the voter has EVER been shown (wins, losses, ties, skips).
  const seen = new Set<number>();
  for (const v of myVotes) {
    seen.add(v.winnerId);
    seen.add(v.loserId);
  }

  const judgedCount = new Map<string, number>();
  for (const v of allVotes) {
    const k = pairKey(v.winnerId, v.loserId);
    judgedCount.set(k, (judgedCount.get(k) ?? 0) + 1);
  }

  type Cand = { a: T; b: T; adj: number; jud: number };
  const build = (excludeOwn: boolean): Cand[] => {
    const pool = props.filter(
      (p) => !seen.has(p.id) && (!excludeOwn || !myPropIds.has(p.id)),
    );
    const out: Cand[] = [];
    for (let i = 0; i < pool.length; i++) {
      for (let j = i + 1; j < pool.length; j++) {
        const a = pool[i];
        const b = pool[j];
        out.push({
          a,
          b,
          adj: Math.abs((rankOf.get(a.id) ?? 0) - (rankOf.get(b.id) ?? 0)),
          jud: judgedCount.get(pairKey(a.id, b.id)) ?? 0,
        });
      }
    }
    return out;
  };

  // CSI (self-inclusion): own takes are excluded, EXCEPT in a pool so small that
  // a non-own pair is impossible (e.g. a 2-person thread). At scale, once you've
  // judged every OTHER take you're done — we do NOT fall back to matching your
  // own idea against another. (That fallback also made the Vote badge — which
  // counts only OTHERS' unplaced takes — disagree with reality: badge 0 but a
  // match still appeared, including your own submission.)
  let candidates = build(true);
  if (candidates.length === 0) {
    const nonOwnCount = props.filter((p) => !myPropIds.has(p.id)).length;
    if (nonOwnCount < 2) candidates = build(false);
  }
  if (candidates.length === 0) return null;

  candidates.sort((x, y) => {
    if (x.adj !== y.adj) return x.adj - y.adj;
    return x.jud - y.jud;
  });
  // Among candidates fully tied on every criterion, the seed picks WHICH —
  // different voters land on different boundaries at the same instant.
  const top = candidates[0];
  const ties = candidates.filter(
    (c) => c.adj === top.adj && c.jud === top.jud,
  );
  const best = ties[((seed % ties.length) + ties.length) % ties.length];
  // RANDOMIZED presentation: no take systematically lands on top (position
  // bias). Deterministic hash of (pair, voter) so the orientation is stable
  // across re-renders for THIS voter+pair but balanced across the crowd.
  // Proper avalanche mixing — a plain multiply-add degenerates to id parity
  // (odd multipliers preserve bit 0), which showed up as a systematic
  // rank-on-top pattern.
  let h = Math.imul(best.a.id ^ 0x9e3779b9, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h ^ best.b.id, 0xc2b2ae35);
  h ^= h >>> 16;
  h = Math.imul(h ^ seed, 0x27d4eb2f);
  h ^= h >>> 15;
  const flip = (h & 1) === 1;
  return flip
    ? { top: best.b, bottom: best.a }
    : { top: best.a, bottom: best.b };
}

/// Per-proposition social proof: how many DISTINCT people have judged each
/// proposition head-to-head, from a round's votes. Both sides of a matchup are
/// credited; skips and null voters are ignored; a person counts once per prop no
/// matter how many matchups they were in. Pure (unit-tested) — drives the
/// "N votes" badge on opinion cards.
export function voterCountsByProp(
  votes: {
    winnerId: number;
    loserId: number;
    isSkip?: boolean;
    voterId?: number | null;
  }[],
): Map<number, number> {
  const sets = new Map<number, Set<number>>();
  const add = (pid: number | null | undefined, vid: number | null | undefined) => {
    if (pid == null || vid == null) return;
    let s = sets.get(pid);
    if (!s) {
      s = new Set();
      sets.set(pid, s);
    }
    s.add(vid);
  };
  for (const v of votes) {
    if (v.isSkip) continue;
    add(v.winnerId, v.voterId);
    add(v.loserId, v.voterId);
  }
  const out = new Map<number, number>();
  sets.forEach((s, pid) => out.set(pid, s.size));
  return out;
}
