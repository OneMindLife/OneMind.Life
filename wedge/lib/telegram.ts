// Telegram Mini App glue. All of this is a no-op outside Telegram (the helpers
// return null / false), so it's safe to ship to the normal web app.
//
// The SDK (telegram.org/js/telegram-web-app.js) creates window.Telegram.WebApp
// when the page runs inside Telegram's webview. We load it lazily, only when a
// Telegram context is detected, so regular web users never fetch it.

const BOT_USERNAME = "OneMindLifeBot";

type TgUser = { first_name?: string; last_name?: string; username?: string };
type TgWebApp = {
  ready?: () => void;
  expand?: () => void;
  openTelegramLink?: (url: string) => void;
  initData?: string;
  initDataUnsafe?: { user?: TgUser; start_param?: string };
};

function w(): (Window & { Telegram?: { WebApp?: TgWebApp }; TelegramWebviewProxy?: unknown }) | null {
  return typeof window === "undefined" ? null : (window as never);
}

export function telegramWebApp(): TgWebApp | null {
  return w()?.Telegram?.WebApp ?? null;
}

/// True when the page is (or was opened) inside Telegram. Detected without the
/// SDK so we know whether it's worth loading it.
export function isTelegramContext(): boolean {
  const win = w();
  if (!win) return false;
  if (win.Telegram?.WebApp?.initData) return true;
  if (win.TelegramWebviewProxy) return true;
  return /tgWebApp/i.test(win.location.hash + win.location.search);
}

/// The player's Telegram display name (first + last, or @username). Null outside
/// Telegram or when Telegram didn't share the user.
export function telegramName(): string | null {
  const u = telegramWebApp()?.initDataUnsafe?.user;
  if (!u) return null;
  const full = [u.first_name, u.last_name].filter(Boolean).join(" ").trim();
  return full || u.username || null;
}

/// Parse the deep-link start_param into a chat code + optional take (a specific
/// proposition to auto-descend onto). Formats:
///   "<CODE>"          → open the room
///   "<CODE>_t<takeId>" → open the room and descend to that take
/// (underscore is one of the few punctuation chars Telegram allows in startapp).
export function telegramStartTarget(): {
  code: string;
  take: number | null;
} | null {
  const raw = telegramWebApp()?.initDataUnsafe?.start_param;
  if (!raw) return null;
  const m = /^([A-Za-z0-9]{2,20})(?:_t(\d{1,15}))?$/.exec(raw);
  if (!m) return null;
  return { code: m[1], take: m[2] ? Number(m[2]) : null };
}

/// The deep-link chat code (back-compat: used for attribution). Just the code
/// segment of the start_param, ignoring any take suffix.
export function telegramStartParam(): string | null {
  return telegramStartTarget()?.code ?? null;
}

/// True on phones/tablets — used to decide native-share (mobile) vs copy (web).
/// `navigator.share` alone leaks on some desktop browsers, so we require an
/// actual touch/mobile signal.
export function isMobile(): boolean {
  if (typeof navigator === "undefined") return false;
  if (/Mobi|Android|iPhone|iPad|iPod/i.test(navigator.userAgent)) return true;
  return (
    navigator.maxTouchPoints > 0 &&
    typeof matchMedia === "function" &&
    matchMedia("(pointer: coarse)").matches
  );
}

/// A Telegram invite that re-opens the Mini App straight into this chat — and,
/// when a takeId is given, straight onto that specific proposition (the
/// daily-frontier button and chain shares use this). Decoded by
/// telegramStartTarget() on the other end.
export function telegramInviteLink(code: string, takeId?: number | null): string {
  // Named Mini App ("play", registered via BotFather /newapp) so the deep-link
  // reliably opens the Mini App with the chat code as start_param.
  const startapp = takeId && takeId > 0 ? `${code}_t${takeId}` : code;
  return `https://t.me/${BOT_USERNAME}/play?startapp=${encodeURIComponent(startapp)}`;
}

/// Open Telegram's native "send to a chat" picker with the invite link pre-filled.
/// Returns true if it fired (i.e. we're inside Telegram). One tap → pick chat → sent.
export function shareViaTelegram(link: string, text: string): boolean {
  const app = telegramWebApp();
  if (!app?.openTelegramLink) return false;
  const url =
    `https://t.me/share/url?url=${encodeURIComponent(link)}` +
    `&text=${encodeURIComponent(text)}`;
  app.openTelegramLink(url);
  return true;
}

/// Load the SDK (once) and run `cb` with the WebApp. Resolves to null outside
/// Telegram.
export function withTelegram(cb: (app: TgWebApp) => void): void {
  if (typeof window === "undefined") return;
  const existing = telegramWebApp();
  if (existing) { cb(existing); return; }
  if (!isTelegramContext()) return;
  const s = document.createElement("script");
  s.src = "https://telegram.org/js/telegram-web-app.js";
  s.async = true;
  s.onload = () => { const app = telegramWebApp(); if (app) cb(app); };
  document.head.appendChild(s);
}
