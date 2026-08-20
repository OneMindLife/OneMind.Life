"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { withTelegram, telegramStartTarget } from "@/lib/telegram";

/// Mounted once in the root layout. Inside Telegram it readies/expands the Mini
/// App and, if opened via a t.me/<bot>?startapp=<code[_t<take>]> invite, routes
/// straight into that chat (and onto a specific take when present). No-op on the
/// normal web.
export default function TelegramInit() {
  const router = useRouter();
  useEffect(() => {
    withTelegram((app) => {
      try {
        app.ready?.();
        app.expand?.();
      } catch {
        /* older Telegram clients — fine */
      }
      const target = telegramStartTarget();
      const code = target?.code ?? null;
      // Definitive Telegram attribution: a super-property stamped on every
      // future event + a one-shot launch event carrying the deep-link param
      // (start_param = which shared invite brought them). Can't be stripped
      // like a UTM. No-op outside Telegram (withTelegram never fires there).
      try {
        const ph = (window as unknown as { posthog?: {
          register?: (p: Record<string, unknown>) => void;
          capture?: (n: string, p?: Record<string, unknown>) => void;
        } }).posthog;
        ph?.register?.({ channel: "telegram", tg_start_param: code ?? null });
        ph?.capture?.("telegram_launch", { tg_start_param: code ?? null });
      } catch {
        /* posthog not ready — attribution still falls back to ATTR script */
      }
      // Route into the group-chat surface (/c/<code>) — the live GLOBAL room.
      // BotFather still loads /g/GLOBAL, which Firebase 302s to /c/GLOBAL, so we
      // land on the /c shell; the take (when present) arrives via start_param,
      // not the URL — we apply it here.
      if (code) {
        const onChat = window.location.pathname.startsWith(`/c/${code}`);
        const hasTake = new URLSearchParams(window.location.search).has("take");
        const takeQ = target?.take ? `?take=${target.take}` : "";
        if (!onChat) {
          router.replace(`/c/${code}${takeQ}`);
        } else if (target?.take && !hasTake) {
          router.replace(`/c/${code}?take=${target.take}`);
        }
      }
    });
  }, [router]);
  return null;
}
