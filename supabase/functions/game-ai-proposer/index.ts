// Edge Function: game-ai-proposer
//
// The AI players in a wedge GAME. When a game round enters the proposing phase,
// this generates ONE fresh alternative (via Claude) for EACH active proposing
// agent and submits it AS that agent (is_agent) — authored "by AI N", can win,
// never scored (handled in SQL).
//
// Seat-fill (docs/SOLO_GAME_AI_FILL_SPEC.md): a game has up to 2 agent
// identities ("AI 1","AI 2"). The regime selector (select_game_ai_regime) sets
// participants.agent_role per round from the live human count:
//   'player'   — proposes AND votes (FILL: humans < 3)
//   'proposer' — proposes only      (IDEATION: humans >= 3)
//   'off'      — idle
// This function proposes for every active agent with role 'player' or 'proposer'
// (skipping any that already proposed). Agents are processed in id order and each
// sees the prior agents' ideas, so the two bots stay distinct.
//
// Spec: always a fresh, distinct alternative; never affirms; knows the
// round-result history + convergence rule; the idea stays within the proposition
// character limit. Calls the Anthropic Messages API via raw fetch (no SDK) to
// stay boot-safe in the edge runtime. Called by trigger_game_ai_proposer
// (pg_net) with { round_id }.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODEL = "claude-sonnet-4-6";
const CHAR_LIMIT = 300; // matches the proposition input limit

const ok = (message: string) =>
  new Response(JSON.stringify({ ok: true, message }), {
    headers: { "Content-Type": "application/json" },
  });

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

// Trim to the character limit on a word boundary (never mid-word, no trailing
// punctuation/space), so the AI idea always fits and reads clean.
function clamp(s: string): string {
  let t = s.replace(/\s+/g, " ").trim();
  if (t.length <= CHAR_LIMIT) return t;
  t = t.slice(0, CHAR_LIMIT);
  const sp = t.lastIndexOf(" ");
  if (sp > CHAR_LIMIT * 0.6) t = t.slice(0, sp);
  return t.replace(/[\s,;:.\-]+$/, "");
}

// Generate one idea for a single agent, given the round context. Returns the
// clamped idea text, or null on any failure (logged, non-fatal).
async function generateIdea(opts: {
  isTopic: boolean;
  isArena?: boolean;
  initialMessage: string;
  leader: string | null;
  others: string[];
  history: string;
  usedTopics?: string[];
  voice?: string;
}): Promise<string | null> {
  const { isTopic, isArena = false, initialMessage, leader, others, history, usedTopics = [], voice } = opts;
  let system: string;
  const userParts: string[] = [];
  if (isArena && !isTopic) {
    // Continuous global arena: the room is ONE evolving conversation that
    // develops question → answer → question → answer. Instead of re-answering
    // the seed every round (which produced a flat, repetitive list), each agent
    // reads the whole thread and advances it: answer the standing question, or
    // pose the next one. The model decides Q vs A from the thread — no brittle
    // punctuation rule.
    system =
      "You are one anonymous voice in a conversation among strangers that flows like a real chat: " +
      "a QUESTION, the best ANSWER, then a follow-up that BUILDS ON it, and so on. Read the " +
      "conversation so far — pay closest attention to the MOST RECENT line — then add the single " +
      "best NEXT line, following these rules STRICTLY:\n" +
      "- If the most recent line is a QUESTION, give a DIRECT, concrete ANSWER — your own honest, " +
      "specific take, written as a STATEMENT (never reply to a question with another question).\n" +
      "- If the most recent line is an ANSWER, ask a follow-up that CONTINUES THAT EXACT THREAD: " +
      "pick up a specific detail or idea from what was just said and dig one step further, or take " +
      "it somewhere closely related — the way a curious friend keeps a conversation going. STAY " +
      "on the current topic for several turns; do NOT change the subject to an unrelated thing.\n" +
      "Keep every line CONCRETE, relatable, and everyday — the kind of thing anyone instantly has " +
      "an opinion on. Never drift into abstract philosophy or get heavier each round — stay light " +
      "and grounded. NEVER repeat or reword anything already said. Reply with ONLY the line, under " +
      `${CHAR_LIMIT} characters, no preamble, no quotes.`;
    userParts.push("The conversation so far (oldest first):");
    userParts.push(`Opening question: ${initialMessage}`);
    if (history) {
      userParts.push(history);
    } else {
      userParts.push("(no answers yet — the room is still on the opening question)");
    }
    if (others.length) {
      userParts.push(`Already proposed this round (do NOT duplicate):\n- ${others.join("\n- ")}`);
    }
    userParts.push("Your single best next line:");
  } else if (isTopic) {
    system =
      "You are a player in a group game where everyone proposes what the group " +
      "should DISCUSS or settle NEXT, then votes. Submit ONE fun, specific topic " +
      "or question the group can actually have opinions on and vote between — not " +
      "a vague category. CRUCIAL: pick something in a COMPLETELY DIFFERENT domain " +
      "from anything already used in this room — do NOT repeat or reword a past " +
      "topic, and avoid tired defaults (e.g. pineapple-on-pizza). Rotate across " +
      "domains: food, music, movies, travel, money, ethics, weird hypotheticals, " +
      "work, relationships, sports. Reply with ONLY the topic: one tight line, " +
      `under ${CHAR_LIMIT} characters, no preamble, no quotes.`;
    userParts.push(`Prompt: ${initialMessage}`);
    if (usedTopics.length) {
      userParts.push(
        `ALREADY USED in this room (do NOT repeat or rephrase ANY of these — pick a different domain):\n- ${usedTopics.join("\n- ")}`,
      );
    }
    if (others.length) userParts.push(`Topics already proposed this round:\n- ${others.join("\n- ")}`);
    userParts.push("Your fresh, different topic:");
  } else {
    system =
      "You are a player in OneMind, a group decision GAME. Everyone secretly " +
      "submits one idea answering the question; the group votes head-to-head, and " +
      "the same idea must win two rounds in a row to lock in (converge). Losing " +
      "ideas drop; the winner carries forward as the 'leader' to beat. Submit ONE " +
      "fresh, specific, genuinely better alternative that could win — never repeat " +
      "or reword an idea on the board, and don't just echo the group's direction; " +
      "give them a real choice. Reply with ONLY the idea text: one tight line, " +
      `under ${CHAR_LIMIT} characters, no preamble, no quotes.`;
    userParts.push(`Question: ${initialMessage}`);
    if (leader) userParts.push(`Current leader to beat: ${leader}`);
    if (others.length) userParts.push(`Other ideas this round:\n- ${others.join("\n- ")}`);
    if (history) userParts.push(`History so far:\n${history}`);
    userParts.push("Your single best alternative:");
  }

  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 120,
      system: withVoice(voice, system),
      messages: [{ role: "user", content: userParts.join("\n\n") }],
    }),
  });
  if (!resp.ok) {
    const body = await resp.text();
    console.log("[game-ai-proposer] anthropic error", resp.status, body.slice(0, 200));
    return null;
  }
  const data = await resp.json();
  const raw = (data.content ?? [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text?: string }) => b.text ?? "")
    .join(" ")
    .replace(/^["']|["']$/g, "");
  const text = clamp(raw);
  return text || null;
}

// A PLAYER bot (FILL regime — a stand-in for an absent human) uses judgment on
// a round with a carried leader: keep the leader ('KEEP') or challenge it with a
// genuinely better idea. Returns 'KEEP', a clamped idea string, or null on
// failure. (The persistent 'proposer' bot never calls this — it always proposes.)
async function decideKeepOrIdea(opts: {
  initialMessage: string;
  leader: string;
  others: string[];
  history: string;
  voice?: string;
}): Promise<string | null> {
  const { initialMessage, leader, others, history, voice } = opts;
  const system =
    "You are a player in OneMind, a group decision GAME. Everyone submits one " +
    "idea; the group votes head-to-head, and the same idea must win two rounds in " +
    "a row to lock in (converge). There is a current LEADER (last round's winner). " +
    "Use your honest judgment like a real participant would: if you genuinely have " +
    "a SPECIFIC, fresh idea that is BETTER than the leader, propose it to give the " +
    "group a real choice; if the leader is already the best option, keep it. Reply " +
    "with EITHER only your new idea (one tight line, under " + CHAR_LIMIT +
    " characters, no quotes) OR exactly the single word KEEP — nothing else.";
  const userParts = [`Question: ${initialMessage}`, `Current leader: ${leader}`];
  if (others.length) userParts.push(`Other ideas this round:\n- ${others.join("\n- ")}`);
  if (history) userParts.push(`History so far:\n${history}`);
  userParts.push("Your decision (a better idea, or KEEP):");

  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 120,
      system: withVoice(voice, system),
      messages: [{ role: "user", content: userParts.join("\n\n") }],
    }),
  });
  if (!resp.ok) {
    console.log("[game-ai-proposer] keep/idea anthropic error", resp.status);
    return null;
  }
  const data = await resp.json();
  const raw = (data.content ?? [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text?: string }) => b.text ?? "")
    .join(" ")
    .replace(/^["']|["']$/g, "")
    .trim();
  if (/^keep[\s.!]*$/i.test(raw)) return "KEEP";
  const text = clamp(raw);
  return text || null;
}

Deno.serve(async (req) => {
  try {
    const { round_id } = await req.json();
    if (!round_id) return ok("no round_id");

    const { data: round } = await supabase
      .from("rounds").select("id, cycle_id, custom_id, phase").eq("id", round_id).maybeSingle();
    if (!round || round.phase !== "proposing") return ok("round not proposing");

    const { data: cycle } = await supabase
      .from("cycles").select("id, chat_id, is_topic").eq("id", round.cycle_id).maybeSingle();
    if (!cycle) return ok("no cycle");
    const isTopic = cycle.is_topic === true;

    const { data: chat } = await supabase
      .from("chats").select("id, initial_message, mode, has_ai_player").eq("id", cycle.chat_id).maybeSingle();
    if (!chat || !chat.has_ai_player) return ok("not an AI game");
    // Arena = the continuous, non-game global room. Its agents advance ONE
    // evolving Q→A→Q→A conversation instead of re-answering the seed each round.
    const isArena = chat.mode !== "game";

    // Every active agent the regime selector marked as proposing this round.
    const { data: agents } = await supabase
      .from("participants").select("id, agent_role, session_token, agent_persona")
      .eq("chat_id", chat.id).eq("is_agent", true).eq("status", "active")
      .in("agent_role", ["proposer", "player"])
      .order("id", { ascending: true });
    if (!agents || agents.length === 0) return ok("no proposing agents");

    // Persona voices: one query for every distinct persona these agents carry.
    // {key: voice}; legacy/generic agents (null persona) aren't in the map and
    // fall back to the plain prompt below.
    const voices = await fetchPersonaVoices(
      agents.map((a) => a.agent_persona).filter((k): k is string => !!k),
    );

    // Winner history (shared context for all agents).
    //  • ARENA: the conversation spans CYCLES (each decision is its own cycle),
    //    so pull the whole chat's winners in chronological order — plain lines,
    //    the evolving thread. Cap to the last 30 to bound the prompt.
    //  • GAME: per-cycle round-winner history (the sealed game's own rounds).
    let history = "";
    if (isArena) {
      const { data: chatCycles } = await supabase
        .from("cycles").select("id").eq("chat_id", chat.id);
      const cycleIds = (chatCycles ?? []).map((c) => c.id);
      if (cycleIds.length) {
        const { data: winRounds } = await supabase
          .from("rounds").select("winning_proposition_id, completed_at")
          .in("cycle_id", cycleIds).not("winning_proposition_id", "is", null)
          .order("completed_at", { ascending: true });
        const ids = (winRounds ?? []).map((r) => r.winning_proposition_id);
        if (ids.length) {
          const { data: winProps } = await supabase
            .from("propositions").select("id, content").in("id", ids);
          const byId = new Map((winProps ?? []).map((p) => [p.id, p.content]));
          history = (winRounds ?? [])
            .map((r) => byId.get(r.winning_proposition_id))
            .filter((c): c is string => !!c)
            .slice(-30)
            .join("\n");
        }
      }
    } else {
      const { data: histRounds } = await supabase
        .from("rounds").select("custom_id, winning_proposition_id").eq("cycle_id", cycle.id)
        .not("winning_proposition_id", "is", null).order("custom_id", { ascending: true });
      if (histRounds && histRounds.length > 0) {
        const ids = histRounds.map((r) => r.winning_proposition_id);
        const { data: winProps } = await supabase.from("propositions").select("id, content").in("id", ids);
        const byId = new Map((winProps ?? []).map((p) => [p.id, p.content]));
        history = histRounds
          .map((r) => `Round ${r.custom_id} winner: ${byId.get(r.winning_proposition_id) ?? "?"}`)
          .join("\n");
      }
    }

    // TOPIC rounds: gather every topic already PROPOSED and every question already
    // PLAYED across THIS room (cross-cycle), so the AI stops re-pitching the same
    // ones each round (without this it drifts back to pineapple-pizza etc.).
    let usedTopics: string[] = [];
    if (isTopic) {
      const { data: answerCycles } = await supabase
        .from("cycles").select("question")
        .eq("chat_id", chat.id).eq("is_topic", false).not("question", "is", null);
      const pastQuestions = (answerCycles ?? []).map((c) => c.question as string).filter(Boolean);

      const { data: topicCycles } = await supabase
        .from("cycles").select("id").eq("chat_id", chat.id).eq("is_topic", true);
      let pastTopicProps: string[] = [];
      const topicCycleIds = (topicCycles ?? []).map((c) => c.id);
      if (topicCycleIds.length) {
        const { data: topicRounds } = await supabase
          .from("rounds").select("id").in("cycle_id", topicCycleIds);
        const topicRoundIds = (topicRounds ?? []).map((r) => r.id).filter((id) => id !== round_id);
        if (topicRoundIds.length) {
          const { data: tprops } = await supabase
            .from("propositions").select("content").in("round_id", topicRoundIds);
          pastTopicProps = (tprops ?? []).map((p) => p.content as string);
        }
      }
      usedTopics = Array.from(new Set([...pastQuestions, ...pastTopicProps]));
    }

    // R2+ proposing auto-advances once everyone PRESENT (humans + proposing
    // agents) has responded. So an agent that fails to generate must still
    // "respond" via a round_skip — otherwise a dead bot stalls the round. (R1 is
    // host-paced, so the backstop is only needed for custom_id > 1.)
    const needsSkipBackstop = (round.custom_id ?? 1) > 1;
    const skipForAgent = async (agentId: number) => {
      if (!needsSkipBackstop) return;
      const { error } = await supabase
        .from("round_skips").insert({ round_id, participant_id: agentId, chat_id: chat.id });
      if (error && error.code !== "23505") {
        console.log(`[game-ai-proposer] skip backstop failed for agent ${agentId}:`, error.message);
      }
    };

    let proposed = 0;
    let affirmed = 0;
    for (const ai of agents) {
      // Skip an agent that already acted this round (fresh proposition OR
      // affirmation). Its carried leader (carried_from_id != null) must NOT count
      // as "proposed" — else it never adds an alternative in rounds it's leading.
      const { data: existing } = await supabase
        .from("propositions").select("id").eq("round_id", round_id)
        .eq("participant_id", ai.id).is("carried_from_id", null).limit(1);
      if (existing && existing.length > 0) continue;
      const { data: existingAff } = await supabase
        .from("affirmations").select("id").eq("round_id", round_id).eq("participant_id", ai.id).limit(1);
      if (existingAff && existingAff.length > 0) continue;

      // Re-fetch props each iteration so a later agent sees an earlier one's idea
      // (keeps the two bots distinct).
      const { data: props } = await supabase
        .from("propositions").select("content, carried_from_id, participant_id").eq("round_id", round_id);
      const leader = (props ?? []).find((p) => p.carried_from_id != null)?.content ?? null;
      const others = (props ?? [])
        .filter((p) => p.carried_from_id == null && p.participant_id !== ai.id)
        .map((p) => p.content);

      // PLAYER bots (FILL — human stand-ins) judge keep-vs-challenge when there's
      // a leader on a non-topic round. The persistent 'proposer' (IDEATION
      // ideation bot) ALWAYS proposes — its job is to spark a fresh alternative.
      const canAffirm = ai.agent_role === "player" && leader != null && !isTopic;
      const voice = ai.agent_persona ? voices.get(ai.agent_persona) : undefined;
      const action = canAffirm
        ? await decideKeepOrIdea({ initialMessage: chat.initial_message, leader, others, history, voice })
        : await generateIdea({ isTopic, isArena, initialMessage: chat.initial_message, leader, others, history, usedTopics, voice });

      if (action === "KEEP") {
        // Affirm the leader. Agents have no auth user_id, so use the bot's stable
        // session_token for the NOT-NULL user_id (satisfies the unique-per-round).
        const { error: affErr } = await supabase
          .from("affirmations")
          .insert({ round_id, participant_id: ai.id, user_id: ai.session_token, chat_id: chat.id });
        if (affErr && affErr.code !== "23505") {
          console.log(`[game-ai-proposer] affirm failed for agent ${ai.id}:`, affErr.message);
          await skipForAgent(ai.id);
          continue;
        }
        console.log(`[game-ai-proposer] round ${round_id} agent ${ai.id}: KEEP (affirmed leader)`);
        affirmed++;
        continue;
      }

      if (!action) { await skipForAgent(ai.id); continue; }

      const { error: insErr } = await supabase
        .from("propositions").insert({ round_id, participant_id: ai.id, chat_id: chat.id, content: action });
      if (insErr) {
        console.log(`[game-ai-proposer] insert skipped for agent ${ai.id}:`, insErr.message);
        await skipForAgent(ai.id);
        continue;
      }
      console.log(`[game-ai-proposer] round ${round_id} agent ${ai.id}: "${action}"`);
      proposed++;
    }

    return ok(`proposed ${proposed}, affirmed ${affirmed}`);
  } catch (e) {
    console.log("[game-ai-proposer] error:", String(e));
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
