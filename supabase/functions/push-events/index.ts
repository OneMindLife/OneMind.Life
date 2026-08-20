// Edge Function: push-events
//
// FCM fan-out for round lifecycle events, driven by the notify_push_round DB
// trigger (the push twin of notify_telegram_round). Fires no matter which
// driver flipped the phase — participation thresholds, the Telegram bot's
// everyone-acted advance, or process-timers' 12h backstop — which is what the
// old design (notifyPhaseChange called only from process-timers) missed.
//
// Events:
//   round_open — "Proposing phase has started". If the previous round of the
//     chat completed seconds ago (continuous chats auto-open the next round
//     after a winner), the push carries the winner too, so the group gets ONE
//     notification instead of a winner+round_open double-ping.
//   vote_open  — "Rating phase has started".
//   winner     — standalone push ONLY when the chat is finished (ended_at
//     set — the final-result payoff moment). While the chat continues, the
//     auto-created next round's merged round_open push carries the winner,
//     so a standalone push would double-ping.
//
// Auth: --no-verify-jwt; bearer = push_internal_secret verified via RPC (the
// secret never leaves the DB). Same pattern as telegram-bot's tgevent.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { notifyChatEvent, notifyPhaseChange, sendPushToTokens } from "../_shared/fcm.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

// A round_open arriving within this window of the previous round's completion
// is treated as the auto-follow of a winner (continuous chats) and the two
// notifications merge into one.
const WINNER_MERGE_WINDOW_MS = 30_000;

function truncate(s: string, n: number): string {
  return s.length <= n ? s : s.slice(0, n - 1).trimEnd() + "…";
}

async function winnerText(roundId: number): Promise<string | null> {
  const { data: round } = await supabase
    .from("rounds").select("winning_proposition_id").eq("id", roundId).maybeSingle();
  if (!round?.winning_proposition_id) return null;
  const { data: wp } = await supabase
    .from("propositions").select("content").eq("id", round.winning_proposition_id).maybeSingle();
  const text = (wp?.content as string) ?? "";
  return text ? truncate(text, 90) : null;
}

// The chat's previous round (id < current) and whether it completed within the
// merge window — plus its winner text if so.
async function recentWinnerBefore(chatId: number, roundId: number): Promise<string | null> {
  const { data: prev } = await supabase
    .from("rounds")
    .select("id, completed_at, cycles!inner(chat_id)")
    .eq("cycles.chat_id", chatId)
    .lt("id", roundId)
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!prev?.completed_at) return null;
  const age = Date.now() - new Date(prev.completed_at as string).getTime();
  if (age > WINNER_MERGE_WINDOW_MS) return null;
  return await winnerText(Number(prev.id));
}

async function handleEvent(event: string, roundId: number, chatId: number): Promise<void> {
  const { data: chat } = await supabase
    .from("chats").select("id, name, ended_at, never_seals").eq("id", chatId).maybeSingle();
  if (!chat) return;
  const name = (chat.name as string) || "OneMind";

  // Repository mode: no proposing/voting phases. The trigger only fires this for
  // the ROOT round (child threads are suppressed to avoid fan-out), so it's a
  // single ~12h re-engagement moment. Nudge with the "N new opinions to place"
  // pull — counted CHAT-WIDE (root + all threads) so it reflects real activity.
  // Skip the ping if nothing's new.
  if (chat.never_seals && (event === "round_open" || event === "vote_open")) {
    const { data: n } = await supabase.rpc("get_chat_new_opinion_count", {
      p_chat_id: chatId,
    });
    const cnt = (n as number | null) ?? 0;
    if (cnt > 0) {
      await notifyChatEvent(
        supabase,
        chatId,
        name,
        `🗂️ ${cnt} new opinion${cnt === 1 ? "" : "s"} to place — tap to rank them`,
      );
    }
    return;
  }

  if (event === "round_open") {
    const winner = await recentWinnerBefore(chatId, roundId);
    if (winner) {
      await notifyChatEvent(supabase, chatId, name, `🏆 "${winner}" won — a new round is open`);
    } else {
      await notifyPhaseChange(supabase, chatId, name, "proposing");
    }
  } else if (event === "vote_open") {
    await notifyPhaseChange(supabase, chatId, name, "rating");
  } else if (event === "winner") {
    // While the chat continues, the next round's merged round_open push
    // carries the winner — a standalone push here would double-ping. Only
    // the final result of a finished chat gets its own push.
    if (!chat.ended_at) return;
    const text = await winnerText(roundId);
    if (text) await notifyChatEvent(supabase, chatId, name, `🏆 Final result: "${text}"`);
  }
}

// watch_reply — a new opinion landed in a watched thread. Ping every watcher of
// the parent thread EXCEPT the reply's author, but only those who hold an FCM
// token (away users who opted into push). Recipients are watchers, not chat
// participants, so this can't reuse notifyChatEvent's participant query.
async function handleWatchReply(body: {
  proposition_id: number;
  reply_id: number;
  chat_id: number;
  author_participant_id: number;
}): Promise<void> {
  const { data: chat } = await supabase
    .from("chats").select("name, invite_code").eq("id", body.chat_id).maybeSingle();
  if (!chat) return;
  const name = (chat.name as string) || "OneMind";
  const code: string = (chat.invite_code as string) ?? "";

  const { data: reply } = await supabase
    .from("propositions").select("content").eq("id", body.reply_id).maybeSingle();
  const excerpt = truncate((reply?.content as string) ?? "", 80);

  // Watchers of the parent thread, minus the author. user_id is denormalized
  // onto opinion_watches (single-row RLS), so no participant join needed.
  const { data: watchers } = await supabase
    .from("opinion_watches")
    .select("user_id")
    .eq("proposition_id", body.proposition_id)
    .neq("participant_id", body.author_participant_id);
  if (!watchers || watchers.length === 0) return;

  // deno-lint-ignore no-explicit-any
  const userIds = [...new Set(watchers.map((w: any) => w.user_id).filter(Boolean))];
  if (userIds.length === 0) return;

  const { data: tokens } = await supabase
    .from("fcm_tokens").select("token, platform").in("user_id", userIds);
  if (!tokens || tokens.length === 0) return;

  // deno-lint-ignore no-explicit-any
  const targets = tokens.map((t: any) => ({ token: t.token, platform: t.platform }));
  const body_text = excerpt
    ? `💬 New reply on a thread you're watching: "${excerpt}"`
    : "💬 New reply on a thread you're watching";
  await sendPushToTokens(targets, {
    title: name,
    body: body_text,
    chat_id: String(body.chat_id),
    code,
  });
}

// root_opinion — a new TOP-LEVEL opinion landed in a repository chat. Ping every
// participant who watches root (the default) EXCEPT the author and EXCEPT anyone
// who muted it, but only those holding an FCM token. Recipients are chat
// participants (minus muted), which is why this can't reuse handleWatchReply's
// per-opinion watcher query.
// room_open — the once-per-session summon for a scheduled room, fired by
// process_scheduled_chats when the window opens. Recipients are the explicit
// opt-ins in room_open_subscribers, NOT chat participants: the whole point of
// the closed screen is that someone who arrives between sessions can ask to be
// called back without joining. (This is also why notifyChatEvent can't be
// reused — it fans out to active participants.)
async function handleRoomOpen(body: { chat_id: number }): Promise<void> {
  const { data: chat } = await supabase
    .from("chats").select("name, invite_code").eq("id", body.chat_id).maybeSingle();
  if (!chat) return;
  const name = (chat.name as string) || "OneMind";
  const code: string = (chat.invite_code as string) ?? "";

  const { data: subs } = await supabase
    .from("room_open_subscribers").select("user_id").eq("chat_id", body.chat_id);
  // deno-lint-ignore no-explicit-any
  const userIds = [...new Set((subs ?? []).map((s: any) => s.user_id).filter(Boolean))];
  if (userIds.length === 0) return;

  const { data: tokens } = await supabase
    .from("fcm_tokens").select("token, platform").in("user_id", userIds);
  if (!tokens || tokens.length === 0) return;

  // How long they have to act on it — the urgency IS the message.
  const { data: state } = await supabase
    .rpc("get_chat_schedule_state", { p_chat_id: body.chat_id }).maybeSingle();
  const closesAt = state?.closes_at ? new Date(state.closes_at as string) : null;
  const mins = closesAt
    ? Math.max(1, Math.round((closesAt.getTime() - Date.now()) / 60000))
    : null;

  // deno-lint-ignore no-explicit-any
  const targets = tokens.map((t: any) => ({ token: t.token, platform: t.platform }));
  await sendPushToTokens(targets, {
    title: name,
    body: mins
      ? `🌍 The room is open for ${mins} minutes — everyone's here now`
      : "🌍 The room is open — everyone's here now",
    chat_id: String(body.chat_id),
    code,
  });
}

async function handleRootOpinion(body: {
  opinion_id: number;
  chat_id: number;
  author_participant_id: number;
}): Promise<void> {
  const { data: chat } = await supabase
    .from("chats").select("name, invite_code").eq("id", body.chat_id).maybeSingle();
  if (!chat) return;
  const name = (chat.name as string) || "OneMind";
  const code: string = (chat.invite_code as string) ?? "";

  const { data: opinion } = await supabase
    .from("propositions").select("content").eq("id", body.opinion_id).maybeSingle();
  const excerpt = truncate((opinion?.content as string) ?? "", 80);

  // Active participants of the chat, minus the author.
  const { data: parts } = await supabase
    .from("participants")
    .select("user_id")
    .eq("chat_id", body.chat_id)
    .eq("status", "active")
    .neq("id", body.author_participant_id);
  if (!parts || parts.length === 0) return;

  // Watching = default; only those who explicitly muted root are excluded.
  const { data: muted } = await supabase
    .from("root_watches").select("user_id").eq("chat_id", body.chat_id).eq("muted", true);
  // deno-lint-ignore no-explicit-any
  const mutedSet = new Set((muted ?? []).map((m: any) => m.user_id).filter(Boolean));

  // deno-lint-ignore no-explicit-any
  const userIds = [...new Set((parts as any[]).map((p) => p.user_id).filter(Boolean))]
    .filter((u) => !mutedSet.has(u));
  if (userIds.length === 0) return;

  const { data: tokens } = await supabase
    .from("fcm_tokens").select("token, platform").in("user_id", userIds);
  if (!tokens || tokens.length === 0) return;

  // deno-lint-ignore no-explicit-any
  const targets = tokens.map((t: any) => ({ token: t.token, platform: t.platform }));
  const body_text = excerpt
    ? `💬 New opinion: "${excerpt}"`
    : "💬 A new opinion was just posted";
  await sendPushToTokens(targets, {
    title: name,
    body: body_text,
    chat_id: String(body.chat_id),
    code,
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("push-events up", { status: 200 });

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: ok } = await supabase.rpc("verify_push_internal", { p_token: token });
  if (ok !== true) return new Response("forbidden", { status: 403 });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { body = null; }
  if (!body?.pushevent) return new Response("bad request", { status: 400 });

  try {
    if (body.pushevent === "watch_reply") {
      await handleWatchReply({
        proposition_id: Number(body.proposition_id),
        reply_id: Number(body.reply_id),
        chat_id: Number(body.chat_id),
        author_participant_id: Number(body.author_participant_id),
      });
    } else if (body.pushevent === "room_open") {
      await handleRoomOpen({ chat_id: Number(body.chat_id) });
    } else if (body.pushevent === "root_opinion") {
      await handleRootOpinion({
        opinion_id: Number(body.opinion_id),
        chat_id: Number(body.chat_id),
        author_participant_id: Number(body.author_participant_id),
      });
    } else {
      await handleEvent(String(body.pushevent), Number(body.round_id), Number(body.chat_id));
    }
  } catch (err) {
    console.error("[push-events] error:", err);
  }
  return new Response("ok", { status: 200 });
});
