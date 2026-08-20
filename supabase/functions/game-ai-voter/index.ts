// Edge Function: game-ai-voter
//
// The voting half of the game AI seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md).
// When a game ANSWER round enters the RATING phase, each active 'player' agent
// (FILL regime: humans < 3) casts pairwise votes so a small/solo game can still
// resolve a winner and converge. 'proposer'/'off' agents never vote; topic
// rounds are human-decided (no agent votes).
//
// Per player agent: rank the propositions it can rate (everything except the
// ones it authored), emit a pairwise_comparison for every unordered pair
// consistent with that ranking, then write a rating_completion. On ANY failure
// (LLM error, unparseable ranking) it instead writes a rating_skip — so a dead
// bot is counted "done" and can never strand the round (it is held in the
// matches "eligible" set from rating-open by get_matches_rating_progress).
//
// Votes feed the SAME MOVDA engine as human matches votes; the bot's row is
// excluded from the leaderboard but its vote counts toward the winner. Calls the
// Anthropic Messages API via raw fetch (no SDK). Called by trigger_game_ai_voter
// (pg_net) with { round_id }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = "claude-sonnet-4-6";

const ok = (message: string) =>
  new Response(JSON.stringify({ ok: true, message }), {
    headers: { "Content-Type": "application/json" },
  });

interface Prop { id: number; content: string; participant_id: number | null; }

// Fetch {personaKey: voice} for the given keys in ONE query. Empty in → empty
// map (no query). Used once per invocation to give each agent its persona voice.
async function fetchPersonaVoices(keys: string[]): Promise<Map<string, string>> {
  const unique = Array.from(new Set(keys));
  if (unique.length === 0) return new Map();
  const { data } = await supabase
    .from("arena_agent_personas").select("key, voice").in("key", unique);
  return new Map((data ?? []).map((r) => [r.key as string, r.voice as string]));
}

// Prepend the agent's persona voice to a generic system prompt. No voice → the
// prompt is returned unchanged (backward compatible with legacy/generic agents).
function withVoice(voice: string | undefined, system: string): string {
  return voice ? `Your perspective: ${voice}\n\n${system}` : system;
}

// Ask Claude to rank the rateable propositions best→worst. Returns an array of
// indices (a permutation of 0..n-1), or null on any failure.
async function rankIdeas(question: string, ideas: string[], voice?: string): Promise<number[] | null> {
  const numbered = ideas.map((c, i) => `${i}. ${c}`).join("\n");
  const system = withVoice(
    voice,
    "You are a player in a group decision game, voting on which idea best answers " +
    "the question. Rank ALL the ideas from best to worst by your honest judgment. " +
    "Reply with ONLY a JSON array of the idea numbers, best first, e.g. [2,0,1]. " +
    "No prose, no code fence.",
  );
  const user = `Question: ${question}\n\nIdeas:\n${numbered}\n\nYour ranking (JSON array of numbers, best first):`;

  let resp: Response;
  try {
    resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 100,
        system,
        messages: [{ role: "user", content: user }],
      }),
    });
  } catch (e) {
    console.log("[game-ai-voter] fetch error", String(e));
    return null;
  }
  if (!resp.ok) {
    console.log("[game-ai-voter] anthropic error", resp.status, (await resp.text()).slice(0, 200));
    return null;
  }
  const data = await resp.json();
  const raw = (data.content ?? [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text?: string }) => b.text ?? "")
    .join(" ");
  const m = raw.match(/\[[\d,\s]*\]/);
  if (!m) return null;
  let arr: unknown;
  try { arr = JSON.parse(m[0]); } catch { return null; }
  if (!Array.isArray(arr)) return null;
  const rank = arr.map((x) => Number(x));
  // Must be a permutation of 0..n-1.
  const n = ideas.length;
  if (rank.length !== n) return null;
  const seen = new Set<number>();
  for (const r of rank) {
    if (!Number.isInteger(r) || r < 0 || r >= n || seen.has(r)) return null;
    seen.add(r);
  }
  return rank;
}

// One agent votes. Returns 'voted' | 'completed-empty' | 'skipped'.
async function voteForAgent(
  agentId: number, roundId: number, chatId: number, question: string, props: Prop[],
  voice?: string,
): Promise<string> {
  // Idempotent: if this agent already has a completion or skip, do nothing.
  const { data: doneRows } = await supabase
    .from("rating_completions").select("id").eq("round_id", roundId).eq("participant_id", agentId).limit(1);
  if (doneRows && doneRows.length > 0) return "already-done";

  const writeSkip = async () => {
    await supabase.from("rating_skips").insert({ round_id: roundId, participant_id: agentId, chat_id: chatId });
    return "skipped";
  };
  const writeCompletion = async () =>
    supabase.from("rating_completions").insert({ round_id: roundId, participant_id: agentId, chat_id: chatId });

  // Rateable = every proposition this agent did NOT author (can't rate your own).
  const rateable = props.filter((p) => p.participant_id !== agentId);
  if (rateable.length < 2) {
    // Nothing to compare — mark complete so the round can advance.
    await writeCompletion();
    return "completed-empty";
  }

  const ranking = await rankIdeas(question, rateable.map((p) => p.content), voice);
  if (!ranking) return await writeSkip();

  // Emit one pairwise_comparison per unordered pair, winner = higher-ranked.
  const rows = [];
  for (let i = 0; i < ranking.length; i++) {
    for (let j = i + 1; j < ranking.length; j++) {
      rows.push({
        round_id: roundId,
        participant_id: agentId,
        winner_proposition_id: rateable[ranking[i]].id,
        loser_proposition_id: rateable[ranking[j]].id,
        is_tie: false,
        is_skip: false,
      });
    }
  }
  const { error: pcErr } = await supabase.from("pairwise_comparisons").insert(rows);
  // 23505 = a pair already voted (re-run); not fatal.
  if (pcErr && pcErr.code !== "23505") {
    console.log(`[game-ai-voter] pairwise insert failed for agent ${agentId}:`, pcErr.message);
    return await writeSkip();
  }
  await writeCompletion();
  return "voted";
}

Deno.serve(async (req) => {
  try {
    const { round_id } = await req.json();
    if (!round_id) return ok("no round_id");

    const { data: round } = await supabase
      .from("rounds").select("id, cycle_id, phase").eq("id", round_id).maybeSingle();
    if (!round || round.phase !== "rating") return ok("round not rating");

    const { data: cycle } = await supabase
      .from("cycles").select("id, chat_id, is_topic").eq("id", round.cycle_id).maybeSingle();
    if (!cycle) return ok("no cycle");

    const { data: chat } = await supabase
      .from("chats").select("id, initial_message, mode, has_ai_player").eq("id", cycle.chat_id).maybeSingle();
    if (!chat || !chat.has_ai_player) return ok("not an AI game");

    // On a TOPIC round the props are candidate next-game questions; rank them by
    // which would be the best to play, not by the current chat's question.
    const question = cycle.is_topic === true
      ? "Which of these would be the best, most fun topic for the group to discuss and vote on next?"
      : chat.initial_message;

    const { data: agents } = await supabase
      .from("participants").select("id, agent_persona")
      .eq("chat_id", chat.id).eq("is_agent", true).eq("status", "active").eq("agent_role", "player")
      .order("id", { ascending: true });
    if (!agents || agents.length === 0) return ok("no voting agents");

    // Persona voices: one query for every distinct persona these agents carry.
    // {key: voice}; legacy/generic agents (null persona) aren't in the map and
    // fall back to the plain ranking prompt.
    const voices = await fetchPersonaVoices(
      agents.map((a) => a.agent_persona).filter((k): k is string => !!k),
    );

    const { data: props } = await supabase
      .from("propositions").select("id, content, participant_id").eq("round_id", round_id);
    if (!props || props.length === 0) return ok("no propositions");

    const results: string[] = [];
    for (const ai of agents) {
      const voice = ai.agent_persona ? voices.get(ai.agent_persona) : undefined;
      const r = await voteForAgent(ai.id, round_id, chat.id, question, props as Prop[], voice);
      results.push(`${ai.id}:${r}`);
    }
    console.log(`[game-ai-voter] round ${round_id}: ${results.join(", ")}`);
    return ok(`voted ${results.join(", ")}`);
  } catch (e) {
    console.log("[game-ai-voter] error:", String(e));
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
