import { supabase, ensureSignedIn } from "@/lib/supabase/client";
import { ensureDisplayName } from "@/lib/onemind/identity";

// Minimal shapes for what the wedge renders. The backend returns more; we type
// only the fields we use. See docs/wedge-spec/04-data-contracts.md.

export type ChatRow = {
  id: number;
  invite_code: string;
  name: string;
  initial_message: string | null;
  access_method: string;
  require_approval: boolean;
  max_cycles: number | null;
  is_preview: boolean;
  ended_at: string | null;
  rating_mode: string;
} & Record<string, unknown>;

export type RoundLite = {
  id: number;
  custom_id: number;
  phase: "waiting" | "proposing" | "rating" | string;
} & Record<string, unknown>;

export type PropositionLite = {
  id: number;
  content: string;
  /// Server-translated content for the requested language (falls back to
  /// English then the original). Present when the bootstrap was loaded with a
  /// language code. Read via `propContent()`.
  content_translated?: string | null;
  participant_id: number | null;
  carried_from_id?: number | null;
  /// Insert time (present on the bootstrap via `to_jsonb(propositions.*)`).
  /// Used by the Global Chat staging list for the "you · 12s" relative label.
  created_at?: string | null;
};

/// Bilingual support. The wedge's UI chrome is translated client-side (lib/i18n);
/// user-generated content (the question + each idea) is translated server-side
/// and returned on the `*_translated` fields when a language code is passed.
export type Lang = "en" | "es";

/// The chat's question in the viewer's language, with graceful fallback. The
/// bootstrap returns `initial_message_translated` / `name_translated`; pre-i18n
/// callers (or untranslated chats) fall back to the raw fields.
export function chatQuestion(chat: Record<string, unknown>): string {
  return (
    (chat.initial_message_translated as string | null) ||
    (chat.initial_message as string | null) ||
    (chat.name_translated as string | null) ||
    (chat.name as string) ||
    ""
  );
}

/// One idea's text in the viewer's language (falls back to the original).
/// Typed on the two fields it actually reads, not on the full proposition, so
/// every translated-text shape (bootstrap rows, ranked rows) can use one helper.
export function propContent(
  p: Pick<PropositionLite, "content" | "content_translated">,
): string {
  return p.content_translated || p.content;
}

export type PriorVote = {
  winnerId: number;
  loserId: number;
  isTie: boolean;
  isSkip: boolean;
  /// Voter (participant) id — present on round-wide fetches, used for the
  /// "N people have voted" participation count. Absent on a voter's own-vote
  /// fetch and on optimistic appends (set to the local voter there).
  voterId?: number | null;
};

export type RankedProp = {
  id: number;
  content: string;
  score: number;
  /// Author of the idea. Used in GAME mode to reveal who wrote each idea in the
  /// results (decision mode never renders it). Null for ownerless/seeded options.
  participantId: number | null;
};

export type ParticipantLite = {
  id: number;
  display_name: string;
  is_host: boolean;
  status: string;
};

export type Bootstrap = {
  chat: ChatRow;
  current_round: RoundLite | null;
  propositions: PropositionLite[];
  my_propositions: PropositionLite[];
  participants: ParticipantLite[];
  my_participant: { id: number; is_host: boolean; status: string } | null;
  participants_who_rated?: number[];
  affirmation_count?: number;
  has_affirmed?: boolean;
} & Record<string, unknown>;

/// Resolve a chat from its invite code (SECURITY DEFINER RPC — works before you
/// are a participant). Returns null if the code doesn't resolve to an active chat.
export async function getChatByCode(code: string): Promise<ChatRow | null> {
  const { data, error } = await supabase.rpc("get_chat_by_code", {
    p_invite_code: code.toUpperCase(),
  });
  if (error) throw error;
  const rows = (data as ChatRow[] | null) ?? [];
  return rows.length > 0 ? rows[0] : null;
}

export type JoinOutcome =
  | { status: "in"; participantId: number }
  | { status: "needs_approval" };

/// View+join on open: if already a participant, return; if an open (non-approval)
/// chat, auto-join (the link is the credential); if approval-required, signal it.
/// NOTE: a plain participant row ≠ "has participated" — that's derived from
/// votes/props, so a link-peeker doesn't pollute the host's voted-count (spec 01).
export async function ensureParticipant(chat: ChatRow): Promise<JoinOutcome> {
  const session = await ensureSignedIn();
  const uid = session?.user.id;
  if (!uid) throw new Error("Could not establish a session.");

  const { data: existing } = await supabase
    .from("participants")
    .select("id, status")
    .eq("chat_id", chat.id)
    .eq("user_id", uid)
    .maybeSingle();
  if (existing) return { status: "in", participantId: existing.id as number };

  if (chat.require_approval) return { status: "needs_approval" };

  const name = await ensureDisplayName();
  // First-touch acquisition source (captured by analytics.tsx into _om_attr)
  // stamped onto the participant row — makes "which channel did this
  // proposer/voter come from?" a plain SQL join forever.
  let source: string | null = null;
  try {
    const attr = JSON.parse(sessionStorage.getItem("_om_attr") || "{}");
    if (typeof attr.visitor_source === "string" && attr.visitor_source) {
      source = attr.visitor_source.slice(0, 40);
    }
  } catch {
    /* attribution is best-effort */
  }
  const { data: row, error } = await supabase
    .from("participants")
    .insert({
      chat_id: chat.id,
      display_name: name,
      user_id: uid,
      is_host: false,
      is_authenticated: true,
      status: "active",
      source,
    })
    .select("id")
    .single();
  if (error) throw error;
  // Tie the analytics person to the Supabase user so browser sessions and
  // DB participants join cleanly.
  try {
    (window as unknown as { posthog?: { identify?: (id: string) => void } })
      .posthog?.identify?.(uid);
  } catch {
    /* analytics identify is best-effort */
  }
  return { status: "in", participantId: row.id as number };
}

/// Group-ideas path: start the chat → create the cycle + a round-1 in PROPOSING
/// (no timer; manual quick chat). Idempotent: reuses an existing cycle/round so a
/// double-tap can't create a second cycle. Mirrors ChatService.startChat.
export async function startGroupChat(chatId: number): Promise<void> {
  const { data: existingCycle } = await supabase
    .from("cycles")
    .select("id")
    .eq("chat_id", chatId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  let cycleId = existingCycle?.id as number | undefined;
  if (cycleId) {
    const { data: existingRound } = await supabase
      .from("rounds")
      .select("id")
      .eq("cycle_id", cycleId)
      .order("custom_id", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (existingRound) return; // already started — reuse
  } else {
    const { data: cyc, error } = await supabase
      .from("cycles")
      .insert({ chat_id: chatId })
      .select("id")
      .single();
    if (error) throw error;
    cycleId = cyc.id as number;
  }

  const { error: rErr } = await supabase.from("rounds").insert({
    cycle_id: cycleId,
    custom_id: 1,
    phase: "proposing",
    phase_started_at: new Date().toISOString(),
  });
  if (rErr) throw rErr;
}

/// Seeded path ("I already have the options"): create the cycle + a round-1
/// directly in RATING, seeded with the given options (ownerless props). No timer
/// (real shared chat) — pass null duration. Mirrors ChatService.seedPrioritizationRound.
export async function seedOptions(
  chatId: number,
  options: string[],
): Promise<void> {
  const { error } = await supabase.rpc("seed_prioritization_round", {
    p_chat_id: chatId,
    p_options: options,
    p_rating_duration_seconds: null,
  });
  if (error) throw error;
}

/// One-round-trip snapshot of the whole chat-detail state (the primary read).
/// Pass a language code so the question + ideas come back translated (the RPC
/// applies a requested-language → English → original fallback). Defaults to
/// 'en' (was previously `null`, which returned only the source text — passing
/// 'en' additionally gives English renderings of Spanish-authored content).
export async function loadBootstrap(
  chatId: number,
  lang: Lang = "en",
): Promise<Bootstrap | null> {
  const { data, error } = await supabase.rpc("get_chat_detail_bootstrap", {
    p_chat_id: chatId,
    p_language_code: lang,
    p_include_previous_results: false,
  });
  if (error) throw error;
  return (data as Bootstrap | null) ?? null;
}

// ── Proposing ─────────────────────────────────────────────────────────────

/// Thrown when the round already has this idea (normalized). Callers surface a
/// "someone already added that" message; the word "duplicate" in the message is
/// what the proposing UI keys off.
export class DuplicatePropositionError extends Error {
  constructor(message = "duplicate proposition") {
    super(message);
    this.name = "DuplicatePropositionError";
  }
}

/// Submit one idea into the proposing round. Goes through the `submit-proposition`
/// edge function (translation + duplicate detection). On a 409 the edge function
/// returns `{ code: 'DUPLICATE_PROPOSITION' }` in the body — we read it off the
/// error's Response so the UI can show the specific "already added" message
/// instead of a generic failure. Mirrors PropositionService.submitProposition.
export async function submitProposition(
  roundId: number,
  participantId: number,
  content: string,
): Promise<number | null> {
  // The edge fn returns { proposition } (with .id) on success — return the id so
  // the caller can descend into the just-posted opinion + offer to share it.
  const { data, error } = await supabase.functions.invoke("submit-proposition", {
    body: { round_id: roundId, participant_id: participantId, content },
  });
  if (!error) {
    const prop = (data as { proposition?: { id?: number } } | null)?.proposition;
    return prop?.id ?? null;
  }
  // FunctionsHttpError carries the raw Response on `context`; the 409 body has
  // the typed code. Best-effort parse — fall back to the raw error.
  const ctx = (error as { context?: Response }).context;
  if (ctx && typeof ctx.json === "function") {
    try {
      const body = await ctx.json();
      if (body?.code === "DUPLICATE_PROPOSITION") {
        throw new DuplicatePropositionError(body.error || "duplicate proposition");
      }
    } catch (e) {
      if (e instanceof DuplicatePropositionError) throw e;
      /* body not JSON / already read — fall through */
    }
  }
  throw error;
}

/// Endorse the carried-forward leader instead of challenging it ("No, this is
/// the one"). Records an affirmation — a real, counted response, so the host can
/// tell "people are keeping it" from "nobody showed up". If EVERY active
/// participant affirms/skips and no one challenges, an AFTER-INSERT trigger
/// auto-resolves the round (leader re-wins, skips rating) → converges. Benign
/// no-op if you already affirmed / submitted / skipped. Requires the proposing
/// phase (R2+ challenge step).
export async function affirmRound(roundId: number): Promise<void> {
  const { error } = await supabase.rpc("affirm_round", { p_round_id: roundId });
  // P0005 already submitted · P0006 already skipped · P0007 already affirmed —
  // all mean "this user already responded", which is fine.
  if (error && !["P0005", "P0006", "P0007"].includes(error.code ?? "")) {
    throw error;
  }
}

/// Host flips the round proposing → rating. Manual quick chat = no timer, so we
/// don't set phase_ends_at. Mirrors ChatService.advanceToRating (manual branch).
export async function advanceToRating(roundId: number): Promise<void> {
  const { error } = await supabase
    .from("rounds")
    .update({ phase: "rating", phase_started_at: new Date().toISOString() })
    .eq("id", roundId);
  if (error) throw error;
}

// ── Matches (pairwise) voting ───────────────────────────────────────────────

/// The matches a participant has already cast this round (drives the pair
/// selector's exposure counts + faced-pair tracking).
export async function getPriorPairwiseVotes(
  roundId: number,
  participantId: number,
): Promise<PriorVote[]> {
  const { data, error } = await supabase
    .from("pairwise_comparisons")
    .select("winner_proposition_id, loser_proposition_id, is_tie, is_skip")
    .eq("round_id", roundId)
    .eq("participant_id", participantId);
  if (error) throw error;
  return ((data as Record<string, unknown>[] | null) ?? []).map((r) => ({
    winnerId: r.winner_proposition_id as number,
    loserId: r.loser_proposition_id as number,
    isTie: (r.is_tie as boolean | null) ?? false,
    isSkip: (r.is_skip as boolean | null) ?? false,
  }));
}

// ── C15 tree walk (the /g surface's navigable web) ─────────────────────────

export type WalkRound = {
  id: number;
  cycle_id: number;
  custom_id: number;
  phase: string;
  completed_at: string | null;
  winning_proposition_id: number | null;
  phase_started_at: string | null;
  phase_ends_at: string | null;
};

export type WalkProp = {
  id: number;
  content: string;
  participant_id: number | null;
  /// The opinion's 0–100 rank score (global_score) — what ORDERS the list and
  /// justifies its position, straight from get_propositions_with_scores.
  /// Absent on live/unranked boards and optimistic appends.
  score?: number;
};

/// The chat's ROOT cycle rounds, oldest first — the walk's positions.
export async function getRootRounds(chatId: number): Promise<WalkRound[]> {
  const { data: cyc } = await supabase
    .from("cycles")
    .select("id")
    .eq("chat_id", chatId)
    .is("parent_proposition_id", null)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (!cyc) return [];
  const { data, error } = await supabase
    .from("rounds")
    .select(
      "id, cycle_id, custom_id, phase, completed_at, winning_proposition_id, phase_started_at, phase_ends_at",
    )
    .eq("cycle_id", cyc.id as number)
    .order("custom_id", { ascending: true });
  if (error) throw error;
  return (data as WalkRound[] | null) ?? [];
}

/// A round's propositions in FINAL-RANKING order (best first) via the
/// get_propositions_with_scores RPC; falls back to submission order for
/// rounds that never got scores (live rounds).
export async function getRankedProps(
  roundId: number,
  lang: Lang = "en",
): Promise<WalkProp[]> {
  const { data, error } = await supabase.rpc("get_propositions_with_scores", {
    p_round_id: roundId,
    p_language_code: lang,
  });
  if (error) throw error;
  // Resolve to the reader's language HERE, at the fetch boundary, rather than
  // handing both strings down and hoping every render site remembers to pick.
  // The pool is global and multilingual: an opinion you can't read is one you
  // can't judge, and an unjudgeable card in a duel is noise in the ranking.
  // The RPC ranks by global_score DESC and returns it — so the score both
  // ORDERS the list and is the number we surface (no extra query). Nodes use
  // this same path now (see treeWalk), so descended lists are score-ranked too.
  const ranked = ((data as Record<string, unknown>[] | null) ?? []).map(
    (p) => ({
      id: p.proposition_id as number,
      content: propContent({
        content: (p.content as string) ?? "",
        content_translated: p.content_translated as string | null,
      }),
      participant_id: (p.participant_id as number | null) ?? null,
      score: (p.global_score as number | null) ?? undefined,
    }),
  );
  if (ranked.length > 0) return ranked;
  // Fallback (round the RPC can't score): submission order, no score.
  const { data: raw, error: e2 } = await supabase
    .from("propositions")
    .select("id, content, participant_id")
    .eq("round_id", roundId)
    .order("id", { ascending: true });
  if (e2) throw e2;
  return (raw as WalkProp[] | null) ?? [];
}

/// One node's full snapshot: parent, window phase, and (when materialized)
/// its live/sealed subround + propositions. Mirrors ChatService.getNodeBootstrap.
export async function getNodeBootstrap(
  propositionId: number,
  lang: Lang = "en",
): Promise<Record<string, unknown>> {
  const { data, error } = await supabase.rpc("get_node_bootstrap", {
    p_proposition_id: propositionId,
    p_language_code: lang,
  });
  if (error) throw error;
  // Resolve to the reader's language HERE, at the fetch boundary, so treeWalk
  // (and everything downstream) keeps reading `.content` and shows English for
  // a foreign-language thread. 7 of 10 non-English opinions live in nodes, so
  // this is the surface where an unreadable duel actually bit. Same reason as
  // getRankedProps: an opinion you can't read is a vote you can't cast.
  // The node's ranked LIST no longer comes from node.propositions (that was
  // chronological); treeWalk routes it through getRankedProps(node.round.id) for
  // correct score-ranking + score. The bootstrap still carries the parent,
  // window phase, and winner.
  return resolveNodeLang((data as Record<string, unknown>) ?? {});
}

/// Fold each content_translated into content across a node bootstrap payload:
/// the parent, every proposition, and the sealed winner. Idempotent on payloads
/// that carry no translations (content_translated absent → content unchanged).
function resolveNodeLang(
  nb: Record<string, unknown>,
): Record<string, unknown> {
  const fold = (o: unknown): void => {
    if (!o || typeof o !== "object") return;
    const rec = o as Record<string, unknown>;
    const t = rec.content_translated;
    if (typeof t === "string" && t) rec.content = t;
  };
  fold(nb.parent);
  const node = nb.node as Record<string, unknown> | null;
  if (node) {
    (node.propositions as unknown[] | undefined)?.forEach(fold);
    fold(node.winner);
  }
  return nb;
}

/// Lazily materialize a proposition's follow-up subround (idempotent).
export async function spawnNodeCycle(propositionId: number): Promise<void> {
  const { error } = await supabase.rpc("get_or_create_node_cycle", {
    p_proposition_id: propositionId,
  });
  if (error) throw error;
}

/// The root→target path of a proposition (for the /g?take=<id> deep-link): an
/// ordered list from the root ancestor down to the target, so the client can
/// pre-commit the walk's choices and auto-descend onto it.
export type PropPathStep = {
  proposition_id: number;
  round_id: number;
  depth: number;
};
export async function getPropositionPath(
  propId: number,
): Promise<PropPathStep[]> {
  const { data, error } = await supabase.rpc("get_proposition_path", {
    p_proposition_id: propId,
  });
  if (error || !data) return [];
  return data as PropPathStep[];
}

/// ALL raters' judgments for a round (not just mine) — powers the live
/// standings above the tree duel. Mirrors
/// PropositionService.getRoundPairwiseVotes.
export async function getRoundPairwiseVotes(
  roundId: number,
): Promise<PriorVote[]> {
  const { data, error } = await supabase
    .from("pairwise_comparisons")
    .select("winner_proposition_id, loser_proposition_id, is_tie, is_skip, participant_id")
    .eq("round_id", roundId);
  if (error) throw error;
  return ((data as Record<string, unknown>[] | null) ?? []).map((r) => ({
    winnerId: r.winner_proposition_id as number,
    loserId: r.loser_proposition_id as number,
    isTie: (r.is_tie as boolean | null) ?? false,
    isSkip: (r.is_skip as boolean | null) ?? false,
    voterId: (r.participant_id as number | null) ?? null,
  }));
}

/// Record one pairwise comparison (a real preference, or a tie). The pair
/// selector never re-offers a faced pair, so this is a plain insert; the UI must
/// debounce. Mirrors PropositionService.submitPairwiseComparison.
export async function submitPairwiseComparison(
  roundId: number,
  participantId: number,
  winnerPropositionId: number,
  loserPropositionId: number,
  isTie = false,
): Promise<void> {
  const { error } = await supabase.from("pairwise_comparisons").insert({
    round_id: roundId,
    participant_id: participantId,
    winner_proposition_id: winnerPropositionId,
    loser_proposition_id: loserPropositionId,
    is_tie: isTie,
    is_skip: false,
  });
  if (error) throw error;
}

/// Record a per-match skip (faced + counts toward exposure, crowns no winner).
/// Idempotent: a duplicate unordered-pair insert (23505) is swallowed.
export async function submitPairwiseSkip(
  roundId: number,
  participantId: number,
  propAId: number,
  propBId: number,
): Promise<void> {
  const { error } = await supabase.from("pairwise_comparisons").insert({
    round_id: roundId,
    participant_id: participantId,
    winner_proposition_id: propAId,
    loser_proposition_id: propBId,
    is_tie: false,
    is_skip: true,
  });
  if (error && error.code !== "23505") throw error;
}

/// How many participants have finished voting this round (matches mode). Drives
/// the host's "end voting" gate. NOTE: a rater with no pair to vote on is still
/// marked complete (the selector exhausts immediately), so a tiny group still
/// reaches the threshold.
export async function getMatchesDoneCount(roundId: number): Promise<number> {
  // DEFINER RPC — authoritative, not gated by the caller's (maybe not-yet-
  // committed) participant row. See migration 20260607180000.
  const { data, error } = await supabase.rpc("get_round_voter_count", {
    p_round_id: roundId,
  });
  if (error) throw error;
  return (data as number | null) ?? 0;
}

/// How many REAL (non-skip) pairwise votes the round has. DEFINER RPC (migration
/// 20260608100000). The host's end-gate requires >=1 so a 0-vote round (everyone
/// could only see their own idea) can't be ended into a meaningless winner.
export async function getMatchesVoteCount(roundId: number): Promise<number> {
  const { data, error } = await supabase.rpc("get_round_vote_count", {
    p_round_id: roundId,
  });
  if (error) throw error;
  return (data as number | null) ?? 0;
}

/// Ask the LLM for a small batch of candidate options for a question (the "Let
/// AI suggest" path). Wraps the `generate-options` edge function (same one the
/// Flutter app used). Returns up to `count` short option strings, or [] on any
/// failure (the caller falls back to manual entry). count is clamped 2..6
/// server-side.
export async function generateOptions(
  question: string,
  count = 5,
  roundId?: number,
  history?: string[],
): Promise<string[]> {
  try {
    const body: Record<string, unknown> = { question, count };
    if (roundId != null) body.round_id = roundId;
    if (history && history.length > 0) body.history = history;
    const { data, error } = await supabase.functions.invoke("generate-options", {
      body,
    });
    if (error) return [];
    const opts = (data as { options?: unknown[] } | null)?.options ?? [];
    return opts.map((o) => String(o)).filter((s) => s.trim().length > 0);
  } catch {
    return [];
  }
}

/// Mark this participant finished rating the round (matches mode). Idempotent.
/// Feeds matches-mode progress% + early-advance.
export async function markRatingComplete(
  roundId: number,
  participantId: number,
): Promise<void> {
  const { error } = await supabase
    .from("rating_completions")
    .insert({ round_id: roundId, participant_id: participantId });
  if (error && error.code !== "23505") throw error;
}

// ── Ending & results ────────────────────────────────────────────────────────

/// Host tallies votes as they stand, locks in the winner, ends the chat
/// (max_cycles == 1). Host-only, enforced server-side. Idempotent if already
/// finalized. Mirrors ChatService.hostEndVoting.
export async function hostEndVoting(chatId: number): Promise<void> {
  const { error } = await supabase.rpc("host_end_voting", {
    p_chat_id: chatId,
  });
  if (error) throw error;
}

/// Live server-computed ranking scores for a round → { propositionId: score }.
/// The scoring strategy (Bradley-Terry by default; see chats.scoring_algorithm)
/// runs server-side and writes proposition_global_scores; the DuelSection reads
/// THIS as the single source of truth for the LIVE RANKING, so the displayed
/// order always matches the sealed winner. Empty until the first server compute
/// (cold start) — the caller falls back to a client sort until then.
/// Repository mode: how many opinions at this round the participant hasn't
/// placed yet (no pairwise comparison involving them) — drives the "N to place"
/// pull. Degrades to 0 on error so the banner just hides.
export async function getUnplacedCount(
  roundId: number,
  participantId: number,
): Promise<number> {
  const { data, error } = await supabase.rpc("get_unplaced_opinion_count", {
    p_round_id: roundId,
    p_participant_id: participantId,
  });
  if (error) return 0;
  return (data as number | null) ?? 0;
}

export type ChatSocialProof = {
  people: number;
  ideas: number;
  judgments: number;
};

/// Cumulative human social proof for a chat: people who've weighed in, ideas
/// contributed, judgments cast. Poll it (~15s) for a live-ticking counter —
/// safe because it's ONE aggregate, not a per-vote subscription. Null on error
/// so the header just hides.
export async function getChatSocialProof(
  chatId: number,
): Promise<ChatSocialProof | null> {
  const { data, error } = await supabase.rpc("get_chat_social_proof", {
    p_chat_id: chatId,
  });
  if (error || !data) return null;
  const d = data as Record<string, number>;
  return {
    people: d.people ?? 0,
    ideas: d.ideas ?? 0,
    judgments: d.judgments ?? 0,
  };
}

export type RoundSocialProof = { opinions: number; votes: number };

/// Per-LEVEL social proof (opinions + votes) scoped to one round — drives the
/// metric bar attached to the composer that describes only THIS node's content.
export async function getRoundSocialProof(
  roundId: number,
): Promise<RoundSocialProof | null> {
  const { data, error } = await supabase.rpc("get_round_social_proof", {
    p_round_id: roundId,
  });
  if (error || !data) return null;
  const d = data as Record<string, number>;
  return { opinions: d.opinions ?? 0, votes: d.votes ?? 0 };
}

/// Record (idempotently) that this participant opened an idea's thread — powers
/// the "N opened" subthread metric. Best-effort: never blocks or throws.
export async function recordThreadOpen(
  propositionId: number,
  participantId: number,
): Promise<void> {
  try {
    await supabase.rpc("record_thread_open", {
      p_proposition_id: propositionId,
      p_participant_id: participantId,
    });
  } catch {
    /* vanity metric — best effort */
  }
}

/// Per-option reply counts: how many human replies live in each proposition's
/// thread → drives the "content inside" badge on option cards.
export async function getThreadReplyCounts(
  roundId: number,
): Promise<Map<number, number>> {
  const m = new Map<number, number>();
  const { data, error } = await supabase.rpc("get_thread_reply_counts", {
    p_round_id: roundId,
  });
  if (error || !data) return m;
  for (const row of data as { proposition_id: number; replies: number }[]) {
    m.set(row.proposition_id, Number(row.replies));
  }
  return m;
}

/// Per-option "votes waiting for YOU inside" counts: how many placeable
/// opinions (others', unpaired, >=2) sit in each proposition's child thread for
/// this participant → drives the personalized attention badge on option cards.
export async function getThreadUnplacedCounts(
  roundId: number,
  participantId: number,
): Promise<Map<number, number>> {
  const m = new Map<number, number>();
  const { data, error } = await supabase.rpc("get_thread_unplaced_counts", {
    p_round_id: roundId,
    p_participant_id: participantId,
  });
  if (error || !data) return m;
  for (const row of data as { proposition_id: number; unplaced: number }[]) {
    m.set(row.proposition_id, Number(row.unplaced));
  }
  return m;
}

/// Per-option "votes waiting below" counts: total pending pairwise MATCHES this
/// participant still owes across the WHOLE subtree beneath each proposition (all
/// descendant rounds, not just the immediate child thread). Already match-counted
/// server-side (floor(unplaced/2) summed) — use the value directly, no
/// pendingMatches() on top. Drives the per-option votes-waiting slot; the count
/// is per-user and depletes as they vote.
export async function getSubtreePendingMatches(
  roundId: number,
  participantId: number,
): Promise<Map<number, number>> {
  const m = new Map<number, number>();
  const { data, error } = await supabase.rpc("get_subtree_pending_matches", {
    p_round_id: roundId,
    p_participant_id: participantId,
  });
  if (error || !data) return m;
  for (const row of data as { proposition_id: number; matches: number }[]) {
    m.set(row.proposition_id, Number(row.matches));
  }
  return m;
}

/// Total pending pairwise matches this participant still owes across the WHOLE
/// chat (resolved from any round in it). Drives the chat-wide "N more votes
/// still need you" pull-banner. Per-user; depletes as they vote.
export async function getChatPendingMatchTotal(
  roundId: number,
  participantId: number,
): Promise<number> {
  const { data, error } = await supabase.rpc("get_chat_pending_match_total", {
    p_round_id: roundId,
    p_participant_id: participantId,
  });
  if (error || data == null) return 0;
  return Number(data);
}

/// Distinct-opener counts per idea in a round → drives the "N opened" badge.
export async function getRoundOpenCounts(
  roundId: number,
): Promise<Map<number, number>> {
  const m = new Map<number, number>();
  const { data, error } = await supabase.rpc("get_round_open_counts", {
    p_round_id: roundId,
  });
  if (error || !data) return m;
  for (const row of data as { proposition_id: number; opens: number }[]) {
    m.set(row.proposition_id, Number(row.opens));
  }
  return m;
}

/// How many voters have finished a ballot this round (rating_completions) — the
/// "N people have voted" social-proof count for the post-ballot leaderboard.
export async function getVoterCount(roundId: number): Promise<number> {
  const { count, error } = await supabase
    .from("rating_completions")
    .select("participant_id", { count: "exact", head: true })
    .eq("round_id", roundId);
  if (error) throw error;
  return count ?? 0;
}

export async function getRoundScores(
  roundId: number,
): Promise<Map<number, number>> {
  const { data, error } = await supabase
    .from("proposition_global_scores")
    .select("proposition_id, global_score")
    .eq("round_id", roundId);
  if (error) throw error;
  const m = new Map<number, number>();
  for (const r of (data as { proposition_id: number; global_score: number }[] | null) ??
    []) {
    m.set(r.proposition_id, r.global_score);
  }
  return m;
}

/// The just-completed round's propositions, ranked desc by global score (in a
/// matches/winner_only chat this score is derived from the pairwise duels, not
/// a grid) — the data for the ended-state leaderboard. Mirrors
/// PropositionService.getPropositionsWithRatings (no-translation path).
export async function loadRanking(
  roundId: number,
  lang: Lang = "en",
): Promise<RankedProp[]> {
  // DEFINER RPC that returns each proposition's content translated to the
  // requested language (English → original fallback) plus its global score —
  // so the results/ranking screens read in the viewer's language. Mirrors the
  // Flutter app's getPropositionsWithRatings translation path.
  const { data, error } = await supabase.rpc(
    "get_propositions_with_translations",
    { p_round_id: roundId, p_language_code: lang },
  );
  if (error) throw error;
  const rows = (data as Record<string, unknown>[] | null) ?? [];
  const ranked = rows.map((r) => {
    const scores = r.proposition_global_scores as
      | { global_score: number | null }
      | null;
    const score = scores?.global_score ?? 0;
    const content =
      (r.content_translated as string | null) || (r.content as string);
    return {
      id: r.id as number,
      content,
      score,
      participantId: (r.participant_id as number | null) ?? null,
    };
  });
  ranked.sort((a, b) => b.score - a.score);
  return ranked;
}

export type RoundHistoryEntry = {
  id: number;
  customId: number;
  winner: string | null;
  voters: number;
  keeps: number;
};

/// Per-round timeline for the "How it converged" screen: every round in order,
/// its winning answer, and how many people voted that round. One authoritative
/// DEFINER RPC — server-computed counts, no client-side RLS race (the old
/// direct-read version could flash "0 voters" before a fresh join committed).
export async function loadRoundHistory(
  chatId: number,
): Promise<RoundHistoryEntry[]> {
  const { data, error } = await supabase.rpc("get_round_history", {
    p_chat_id: chatId,
  });
  if (error) throw error;
  return (
    (data as
      | {
          id: number;
          custom_id: number;
          winner: string | null;
          voters: number;
          keeps: number;
        }[]
      | null) ?? []
  ).map((r) => ({
    id: r.id,
    customId: r.custom_id,
    winner: r.winner ?? null,
    voters: r.voters ?? 0,
    keeps: r.keeps ?? 0,
  }));
}

/// Summary stats for the ended-state header: how many rounds it took (>=2 means
/// it converged — won consecutive rounds), how many people decided, and how many
/// head-to-head comparisons were cast. Authoritative DEFINER RPC (no RLS race).
export async function getResultMeta(chatId: number): Promise<{
  rounds: number;
  people: number;
  comparisons: number;
}> {
  const { data, error } = await supabase.rpc("get_chat_result_meta", {
    p_chat_id: chatId,
  });
  if (error) throw error;
  const m = (data as { rounds?: number; people?: number; comparisons?: number } | null) ?? {};
  return {
    rounds: m.rounds ?? 0,
    people: m.people ?? 0,
    comparisons: m.comparisons ?? 0,
  };
}

/// Resolve the latest round for a chat (used to find the completed round of an
/// ended chat, whose bootstrap current_round may be stale/empty).
export async function getLatestRound(
  chatId: number,
): Promise<{ id: number; custom_id: number } | null> {
  const { data: cycles } = await supabase
    .from("cycles")
    .select("id")
    .eq("chat_id", chatId);
  const cycleIds = ((cycles as { id: number }[] | null) ?? []).map((c) => c.id);
  if (cycleIds.length === 0) return null;
  const { data, error } = await supabase
    .from("rounds")
    .select("id, custom_id")
    .in("cycle_id", cycleIds)
    .order("custom_id", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return (data as { id: number; custom_id: number } | null) ?? null;
}

/// Heartbeat for the continuous AI arena: mark a human present so the seat-fill
/// bots keep running (and wake them if the room had gone cold). Best-effort — the
/// client fires this on mount + on an interval; any error is swallowed (a missed
/// beat just means the next one warms the room). No-op server-side for non-arena
/// chats. See migration 20260709220000_arena_pause_when_empty.
export async function touchArenaPresence(chatId: number): Promise<void> {
  try {
    await supabase.rpc("touch_arena_presence", { p_chat_id: chatId });
  } catch {
    /* best-effort presence heartbeat — ignore */
  }
}

// ── Global Chat (continuous "the room speaks" feed) ──────────────────────────

/// The permanent winners chain for the Global Chat feed, fetched in ONE round
/// trip via `get_global_winners` (DEFINER, public-readable). Previously this
/// fanned out to 4 sequential requests (get_round_history → rounds →
/// propositions → translations) which dominated cold-start latency — perf_logs
/// showed a ~5s median for this step while the SQL itself ran in tens of ms.
/// Only SEALED rounds (winner set) come back; the in-progress round is the live
/// staging block, not history.
export async function loadGlobalWinners(
  chatId: number,
  myParticipantId: number | null,
  lang: string,
): Promise<import("./globalChat").GlobalWinner[]> {
  const { mapGlobalWinners } = await import("./globalChat");
  const { data, error } = await supabase.rpc("get_global_winners", {
    p_chat_id: chatId,
    p_language_code: lang,
  });
  if (error) throw error;
  const rows = (data as import("./globalChat").GlobalWinnerRow[] | null) ?? [];
  return mapGlobalWinners(rows, myParticipantId);
}

// ── Game mode ────────────────────────────────────────────────────────────────

/// One row of the per-game (per-cycle) leaderboard: a player and their average
/// rank across this game's rounds. Higher avgRank = better (closer to the group).
export type LeaderRow = {
  participantId: number;
  name: string;
  avgRank: number;
  rounds: number;
};

/// The per-GAME leaderboard (game mode): players ranked by how they did across
/// the latest cycle's rounds. Resolves the chat's latest cycle, then calls the
/// get_cycle_leaderboard RPC (migration 20260624010000). Empty until at least one
/// round has scored ranks.
export async function loadCycleLeaderboard(chatId: number): Promise<LeaderRow[]> {
  // The latest ANSWER cycle (is_topic = false). Topic rounds are selection, not
  // the game — they never count toward the leaderboard.
  const { data: cyc } = await supabase
    .from("cycles")
    .select("id")
    .eq("chat_id", chatId)
    .eq("is_topic", false)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!cyc) return [];
  const { data, error } = await supabase.rpc("get_cycle_leaderboard", {
    p_cycle_id: cyc.id,
  });
  if (error) throw error;
  return (
    (data as
      | {
          participant_id: number;
          display_name: string;
          avg_rank: number | null;
          rounds_participated: number | null;
        }[]
      | null) ?? []
  ).map((r) => ({
    participantId: r.participant_id,
    name: r.display_name,
    avgRank: r.avg_rank ?? 0,
    rounds: r.rounds_participated ?? 0,
  }));
}

/// "Play again" (game mode): host reopens the SAME room with a new question and a
/// fresh cycle — participants carry over. Host-only, enforced server-side
/// (start_new_game RPC, migration 20260624010000). Returns the new cycle id.
export async function startNewGame(
  chatId: number,
  question: string,
): Promise<number> {
  const { data, error } = await supabase.rpc("start_new_game", {
    p_chat_id: chatId,
    p_question: question,
  });
  if (error) throw error;
  return data as number;
}

/// "Next game" (game mode): host opens a TOPIC ROUND — the group proposes the
/// next topic and votes; the winning topic becomes the next answer game's
/// question (server-side, on_round_winner_set topic branch). Host-only
/// (start_topic_round RPC, migration 20260624050000). Host paces *when*, the
/// group picks *what*. Returns the new topic cycle id.
export async function startTopicRound(
  chatId: number,
  prompt: string,
): Promise<number> {
  const { data, error } = await supabase.rpc("start_topic_round", {
    p_chat_id: chatId,
    p_prompt: prompt,
  });
  if (error) throw error;
  return data as number;
}

/// Set the current user's display name in this chat (the in-chat name gate —
/// same UX for host and participant in game mode). RLS allows a participant to
/// update their own row ("Host or self can update participants").
export async function setMyName(chatId: number, name: string): Promise<void> {
  const session = await ensureSignedIn();
  const uid = session?.user.id;
  if (!uid) throw new Error("Could not establish a session.");
  const clean = name.trim().slice(0, 40);
  if (!clean) throw new Error("A name is required.");
  const { error } = await supabase
    .from("participants")
    .update({ display_name: clean })
    .eq("chat_id", chatId)
    .eq("user_id", uid);
  if (error) throw error;
}
