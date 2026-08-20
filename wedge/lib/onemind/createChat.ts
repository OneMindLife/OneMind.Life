import { supabase, ensureSignedIn } from "@/lib/supabase/client";
import { ensureDisplayName } from "@/lib/onemind/identity";

/// The fixed quick-chat (sealed single-use, instant matches) config — mirrors
/// quick_create_screen.dart's createChat call. See docs/wedge-spec/04-data-contracts.md.
/// `mode` is 'decision' (the serious sealed quick chat) or 'game' (the social
/// "best ideas win" mode: persistent room, per-game leaderboard, authorship
/// reveal, affirmer scoring, play-again). See migration 20260624010000.
function quickChatRow(
  question: string,
  creatorId: string,
  hostName: string,
  mode: "decision" | "game",
) {
  const name = question.length > 80 ? question.slice(0, 80).trim() : question;
  return {
    name,
    mode,
    // Games include the default AI player (an is_agent participant added by the
    // add_game_ai_participant trigger; the game-ai-proposer edge fn drives it).
    has_ai_player: mode === "game",
    initial_message: question,
    access_method: "code",
    require_auth: false,
    require_approval: false,
    creator_id: creatorId,
    host_display_name: hostName,
    start_mode: "manual",
    rating_start_mode: "auto",
    proposing_duration_seconds: 86400,
    rating_duration_seconds: 86400,
    proposing_minimum: 3,
    rating_minimum: 2,
    // BOTH proposing thresholds null → the proposing early-advance trigger
    // short-circuits (host advances manually, no auto-advance). These MUST be
    // explicit nulls: the chats table column DEFAULTs are 3 / 2, so omitting
    // them lets the early-advance trigger fire and race proposing → rating
    // before the group is ready (mirrors quick_create_screen.dart).
    proposing_threshold_percent: null,
    proposing_threshold_count: null,
    rating_threshold_percent: null,
    rating_threshold_count: null,
    enable_ai_participant: false,
    enable_agents: false,
    proposing_agent_count: 0,
    rating_agent_count: 0,
    // Lock-in cadence is set by MODE at creation, never mutated later:
    //   decision → CONVERGENCE (2): an idea must win 2 consecutive rounds to
    //     lock in (the deliberate sealed-decision product).
    //   game → INSTANT (1): an idea wins in ONE round and the group moves
    //     straight on (the one-shot reveal game). With max_cycles=1 the answer
    //     cycle completes after a single round — no round 2, so the round-2
    //     "challenge the leader" screen (LeaderChallenge) never renders.
    confirmation_rounds_required: mode === "game" ? 1 : 2,
    show_previous_results: true,
    propositions_per_user: 1,
    // Bilingual support: fire the translate_chat_on_insert trigger so the
    // question (name + initial_message) is machine-translated into every
    // supported language on creation. Without this the column DEFAULTs to
    // false and the trigger skips — which is why translation silently never
    // ran for wedge chats. translation_languages defaults to all 5 (en/es/...).
    translations_enabled: true,
    rating_mode: "matches",
    match_objective: "winner_only",
    allow_skip_proposing: true,
    allow_skip_rating: true,
    max_cycles: 1,
    is_preview: false,
  };
}

/// Create a quick chat and return its invite code (the /c/<code> handle).
/// Steps mirror the Flutter quick-create: ensure anon auth + display name →
/// insert the chats row (DB generates invite_code) → add the host participant.
export async function createQuickChat(
  question: string,
  opts: { mode?: "decision" | "game" } = {},
): Promise<{ code: string; id: number }> {
  const mode = opts.mode ?? "decision";
  const session = await ensureSignedIn();
  const userId = session?.user.id;
  if (!userId) throw new Error("Could not establish an anonymous session.");

  // Game mode does NOT ask the host for a name here — everyone (host included)
  // names themselves once inside the chat via the in-chat name gate. So the host
  // still gets an auto display name at creation; the gate overwrites it.
  const hostName = await ensureDisplayName();

  const { data: chat, error: chatErr } = await supabase
    .from("chats")
    .insert(quickChatRow(question, userId, hostName, mode))
    .select("id, invite_code")
    .single();
  if (chatErr) throw chatErr;
  if (!chat?.invite_code) throw new Error("Chat created without an invite code.");

  const { error: partErr } = await supabase.from("participants").insert({
    chat_id: chat.id,
    display_name: hostName,
    user_id: userId,
    is_host: true,
    is_authenticated: true,
    status: "active",
  });
  if (partErr) throw partErr;

  return { code: chat.invite_code as string, id: chat.id as number };
}
