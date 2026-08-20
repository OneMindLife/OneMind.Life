// Edge Function: telegram-bot
//
// Webhook handler for @OneMindLifeBot — a LENS onto the one global OneMind room.
//
// The bot does exactly two things:
//   1. Adding it to a group posts a welcome + a button into /c/GLOBAL.
//   2. Each phase change of the official web room (chat 1269) is broadcast to
//      the OneMind channel with a button back into /c/GLOBAL — the retention
//      loop (growth D68: channel-first, never mass DMs).
//
// It does NOT run per-group rooms. The "House" model (/decide, /window, DM take
// capture, the pairwise Mini App API) was REMOVED 2026-08-11: per-group rooms
// fragment liquidity at our scale (docs/TELEGRAM_ARCHITECTURE.md), 0 chats were
// ever bound in prod, and its Mini App deep-links were silently broken — they
// sent `startapp=take_<id>`, which fails the room's start_param parser
// (`/^([A-Za-z0-9]{2,20})(?:_t(\d{1,15}))?$/` needs `_t<digits>`), so tapping
// "Submit your take" dumped the user in the global room instead of their group.
// Git history has the full implementation if Phase 2 ever revives it.
//
// Buttons open `t.me/<bot>/play?startapp=GLOBAL`. BotFather's `play` app points
// at onemind.life/g/GLOBAL, which 302s to /c/GLOBAL; the wedge's TelegramInit
// reads start_param and routes. (The standalone Mini App that used to live at
// onemind-telegram.web.app is orphaned — nothing links to it.)
//
// Auth: --no-verify-jwt. Telegram webhook → X-Telegram-Bot-Api-Secret-Token
// header; DB tgevent → shared vault secret verified via RPC.
// Secrets: TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET, SUPABASE_URL,
// SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const BOT_USERNAME = "OneMindLifeBot";
// The OneMind broadcast channel — the bot is admin here and posts each phase
// transition of the official web room (1269) as the retention loop. Addressed by
// NUMERIC id (the @onemind_life username is a DIFFERENT channel the bot isn't in;
// this -100 id is Joel's channel where the bot is admin). See docs/TELEGRAM_ARCHITECTURE.md.
const BROADCAST_CHANNEL_ID: number | string = -1003908305100;
const API = `https://api.telegram.org/bot${BOT_TOKEN}`;

// The global room's code — the one room the bot is a lens into.
const GLOBAL_CODE = "GLOBAL";

// ── Telegram Bot API helpers ────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
async function tg(method: string, body: Record<string, unknown>): Promise<any> {
  const res = await fetch(`${API}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return res.json();
}

function sendMessage(
  chatId: number | string,
  text: string,
  extra: Record<string, unknown> = {},
) {
  return tg("sendMessage", { chat_id: chatId, text, parse_mode: "HTML", ...extra });
}

// A button that opens the room. Uses the named-app deep-link (`/play?startapp=`)
// because inline web_app buttons are private-chat-only and these must work from
// a GROUP and a CHANNEL too.
function miniAppButton(label: string, payload: string) {
  return {
    inline_keyboard: [[{ text: label, url: `https://t.me/${BOT_USERNAME}/play?startapp=${payload}` }]],
  };
}

const ack = () => new Response("ok", { status: 200 });

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// ── Room data helpers (only what the broadcast needs) ───────────────────────

// The chat a round belongs to.
async function chatIdForRound(roundId: number): Promise<number | null> {
  const { data: round } = await supabase
    .from("rounds").select("cycle_id").eq("id", roundId).maybeSingle();
  if (!round) return null;
  const { data: cycle } = await supabase
    .from("cycles").select("chat_id").eq("id", round.cycle_id).maybeSingle();
  return (cycle?.chat_id as number | undefined) ?? null;
}

// How many takes are in this round so far (privacy-safe social proof: count only).
async function takeCount(roundId: number): Promise<number> {
  const { count } = await supabase
    .from("propositions").select("id", { count: "exact", head: true }).eq("round_id", roundId);
  return count ?? 0;
}

async function completionCount(roundId: number): Promise<number> {
  const { count } = await supabase
    .from("rating_completions").select("id", { count: "exact", head: true }).eq("round_id", roundId);
  return count ?? 0;
}

// Has this chat ever completed a round? (Distinguishes the room's first-ever
// round from post-winner auto-created ones.)
async function hasCompletedRound(chatId: number): Promise<boolean> {
  const { data } = await supabase
    .from("rounds")
    .select("id, cycles!inner(chat_id)")
    .eq("cycles.chat_id", chatId)
    .not("completed_at", "is", null)
    .limit(1);
  return (data ?? []).length > 0;
}

// ── Broadcast to the OneMind channel on the official web room's phase changes ─
// Fired by notify_telegram_round for the is_official room (1269). This is the
// retention loop — see growth D68 + the DM-vs-channel decision (channel-first,
// not mass DMs).
async function handleBroadcast(
  event: string,
  roundId: number,
  chatId: number | null = null,
) {
  // room_open — the once-per-session summon for a SCHEDULED room, fired by
  // process_scheduled_chats when the window opens (not by a phase change: at
  // 60s phases that would post ~30 times a session). Carries chat_id, not
  // round_id, because the room opens before anything happens in it.
  if (event === "room_open") {
    if (chatId == null) return;
    const { data: state } = await supabase
      .rpc("get_chat_schedule_state", { p_chat_id: chatId })
      .maybeSingle();
    // The RPC is untyped here (no generated types in the edge runtime), so the
    // row comes back as `{}` — narrow it explicitly.
    const closesIso = (state as { closes_at?: string } | null)?.closes_at ?? null;
    const closesAt = closesIso ? new Date(closesIso) : null;
    const mins = closesAt
      ? Math.max(1, Math.round((closesAt.getTime() - Date.now()) / 60000))
      : null;
    const forHowLong = mins ? ` for the next ${mins} minutes` : "";
    await sendMessage(
      BROADCAST_CHANNEL_ID,
      `🌍 <b>The room is open</b>${forHowLong}.\n\n` +
        `Everyone's here at once — say what you really think, anonymously, ` +
        `and vote on what everyone else said. New round every minute.`,
      { reply_markup: miniAppButton("🌍 Join the room →", GLOBAL_CODE) },
    );
    return;
  }

  if (event === "round_open") {
    // Only the room's FIRST round announces itself here — every later round's
    // "new round" is folded into the winner post (below), so we don't double-post.
    const cid = await chatIdForRound(roundId);
    if (cid && (await hasCompletedRound(cid))) return;
    await sendMessage(
      BROADCAST_CHANNEL_ID,
      `🌍 <b>A new round is open</b>\n\nSay what you really think — anonymously. ` +
        `The room votes the best line to the top.`,
      { reply_markup: miniAppButton("✍️ Say something →", GLOBAL_CODE) },
    );
  } else if (event === "vote_open") {
    const n = await takeCount(roundId);
    await sendMessage(
      BROADCAST_CHANNEL_ID,
      `🗳 <b>Voting is open</b>\n\n${n} ${n === 1 ? "take is" : "takes are"} in. ` +
        `Which one is best? Compare them head-to-head — anonymous, quick.`,
      { reply_markup: miniAppButton("🗳 Vote now →", GLOBAL_CODE) },
    );
  } else if (event === "winner") {
    const { data: round } = await supabase
      .from("rounds").select("winning_proposition_id").eq("id", roundId).maybeSingle();
    if (!round?.winning_proposition_id) return;
    const { data: wp } = await supabase
      .from("propositions").select("content").eq("id", round.winning_proposition_id).maybeSingle();
    const text = (wp?.content as string) ?? "";
    if (!text) return;
    const [takes, voters] = await Promise.all([takeCount(roundId), completionCount(roundId)]);
    const beat = Math.max(0, takes - 1);
    const how = takes <= 1
      ? ""
      : `\n\n<i>Beat ${beat} other ${beat === 1 ? "take" : "takes"} · ` +
        `${voters} ${voters === 1 ? "voter" : "voters"} · nobody knew who wrote what.</i>`;
    await sendMessage(
      BROADCAST_CHANNEL_ID,
      `🏆 <b>The room decided:</b>\n\n“${escapeHtml(text)}”${how}\n\n` +
        `A new round is open — think you can do better?`,
      { reply_markup: miniAppButton("➕ Add your take →", GLOBAL_CODE) },
    );
  }
}

// ── Webhook entrypoint ──────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("telegram-bot up", { status: 200 });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try { body = await req.json(); } catch { body = null; }

  // Internal event from the DB (notify_telegram_round trigger) — authed by the
  // shared vault secret, verified via RPC (the secret never leaves the DB).
  if (body?.tgevent) {
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: ok } = await supabase.rpc("verify_telegram_internal", { p_token: token });
    if (ok !== true) return new Response("forbidden", { status: 403 });
    try {
      // Only the official web room broadcasts. Per-group (bound-chat) events are
      // ignored — the House model is gone; nothing binds telegram_chat_id.
      if (body.broadcast) {
        await handleBroadcast(
          String(body.tgevent),
          Number(body.round_id),
          body.chat_id == null ? null : Number(body.chat_id),
        );
      }
    } catch (err) { console.error("[telegram-bot] tgevent error:", err); }
    return ack();
  }

  // Telegram webhook — authed by the secret header.
  if (WEBHOOK_SECRET) {
    const got = req.headers.get("X-Telegram-Bot-Api-Secret-Token");
    if (got !== WEBHOOK_SECRET) return new Response("forbidden", { status: 403 });
  }
  if (!body) return ack();
  try { await handleUpdate(body); } catch (err) {
    console.error("[telegram-bot] handleUpdate error:", err);
  }
  return ack();
});

// deno-lint-ignore no-explicit-any
async function handleUpdate(update: any): Promise<void> {
  if (update.my_chat_member) return handleChatMember(update.my_chat_member);
  const msg = update.message ?? update.edited_message;
  if (msg?.text) return handleMessage(msg);
}

// LENS: adding the bot to a group points that group at the ONE global room. It
// does NOT create a per-group room.
// deno-lint-ignore no-explicit-any
async function handleChatMember(u: any): Promise<void> {
  const status = u.new_chat_member?.status;
  const chat = u.chat;
  const isGroup = chat?.type === "group" || chat?.type === "supergroup";
  if (!isGroup || (status !== "member" && status !== "administrator")) return;

  await sendMessage(
    chat.id,
    `🌍 <b>OneMind is live here.</b>\n\n` +
      `One room the whole world is in. Post what's actually on your mind — ` +
      `<b>anonymously</b> — read what everyone else is saying, and vote the best ` +
      `line to the top. No names, no followers, no algorithm.\n\n` +
      `Every round, the room's best line rises and is kept.`,
    { reply_markup: miniAppButton("🌍 Open the room →", GLOBAL_CODE) },
  );
}

// deno-lint-ignore no-explicit-any
async function handleMessage(msg: any): Promise<void> {
  const chatId = msg.chat.id;
  const text: string = (msg.text ?? "").trim();
  const from = msg.from ?? {};
  const isPrivate = msg.chat.type === "private";

  // /start — the DM front door. (Deep-link payloads are ignored: the room reads
  // start_param itself once the Mini App opens.)
  if (text === "/start" || text.startsWith("/start ") || text.startsWith("/start@")) {
    await sendMessage(
      chatId,
      `👋 Hey ${escapeHtml(from.first_name ?? "there")} — this is <b>OneMind</b>, ` +
        `the world's group chat.\n\n` +
        `One room the whole world is in. Say what you actually think, ` +
        `<b>anonymously</b>; the room votes the best line to the top and keeps it. ` +
        `No account, no followers, no algorithm.\n\n` +
        `Add me to a group to put the room in front of your people.`,
      { reply_markup: miniAppButton("🌍 Open the room →", GLOBAL_CODE) },
    );
    return;
  }

  // Any other DM → point back at the room. Group messages are ignored entirely
  // (the bot is a lens, not a participant).
  if (isPrivate) {
    await sendMessage(
      chatId,
      `Everything happens in the room — tap below to open it.`,
      { reply_markup: miniAppButton("🌍 Open the room →", GLOBAL_CODE) },
    );
  }
}
