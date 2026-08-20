import {
  isTelegramContext,
  shareViaTelegram,
  telegramInviteLink,
} from "@/lib/telegram";

/// Share WHERE YOU ARE: the room at root, or the specific opinion's thread when
/// you're inside one (`?take=<id>` / Telegram `startapp=<code>_t<id>`, both of
/// which deep-link straight back to that node).
///
/// This used to always share the root regardless of position — so sharing a
/// thread you liked silently handed your friend the top of the chat instead.
///
/// Inside Telegram it hands off a Mini App deep-link (keeps the recipient
/// in-app); else the native share sheet on mobile; else a clipboard copy.
/// Returns what happened so callers can flash "copied".
export async function shareRoom(
  code: string,
  name: string,
  takeId?: number | null,
): Promise<"shared" | "copied" | "none"> {
  const take = takeId && takeId > 0 ? takeId : null;
  if (isTelegramContext()) {
    const link = telegramInviteLink(code, take);
    if (
      shareViaTelegram(
        link,
        take
          ? "Weigh in on this — anonymous, ranked on merit 👇"
          : "Say what you really think — anonymous, ranked on merit 👇",
      )
    )
      return "shared";
  }
  const url = take
    ? `${window.location.origin}/g/${code}?take=${take}`
    : `${window.location.origin}/g/${code}`;
  const isMobile = /android|iphone|ipad|ipod/i.test(navigator.userAgent);
  if (isMobile && navigator.share) {
    try {
      await navigator.share({ title: name, url });
    } catch {
      /* dismissed */
    }
    return "shared";
  }
  try {
    await navigator.clipboard.writeText(url);
    return "copied";
  } catch {
    return "none";
  }
}
