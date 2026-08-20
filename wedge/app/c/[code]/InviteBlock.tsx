"use client";

import { useState } from "react";
import { track } from "@/lib/onemind/analytics";
import { useI18n } from "@/lib/i18n";
import {
  isTelegramContext,
  telegramInviteLink,
  shareViaTelegram,
  isMobile,
} from "@/lib/telegram";
import { ShareIcon } from "../../components/ui";

/// The "invite your group" card — the share loop that is OneMind's growth
/// engine, and the fix for the solo-stall (a lone host who never pulls anyone
/// in and dead-ends with only the AI). Shown prominently to the host so they
/// bring their group before the game gets going. Inside Telegram the button
/// opens the native "send to a chat" picker with the Mini App deep-link (one
/// tap → the invitee lands straight in this game, auto-named); on the web it
/// uses the native share sheet, falling back to copying the chat link.
export default function InviteBlock({ code }: { code: string }) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);
  const url =
    typeof window !== "undefined"
      ? isTelegramContext()
        ? telegramInviteLink(code)
        : `${window.location.origin}/c/${code}`
      : "";
  const display = url.replace(/^https?:\/\//, "");

  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
      track("quick_chat_share", { source: "invite" });
    } catch {
      /* clipboard blocked — no-op */
    }
  }

  async function share() {
    // Inside Telegram: native "send to a chat" picker with the deep-link.
    if (shareViaTelegram(url, t("rail.shareText"))) {
      track("quick_chat_share", { source: "invite_telegram" });
      return;
    }
    // Mobile → native share sheet. Web → skip straight to copying the link.
    if (isMobile() && typeof navigator !== "undefined" && navigator.share) {
      try {
        await navigator.share({ url });
        track("quick_chat_share", { source: "invite_native" });
        return;
      } catch {
        /* dismissed — fall through to copy */
      }
    }
    await copy();
  }

  return (
    <div className="share invite-card">
      <div className="lbl">
        <ShareIcon />
        {t("inv.title")}
      </div>
      <div className="row">
        <div className="link">{display}</div>
        <button className="copy beckon-w" onClick={share} type="button">
          {copied ? t("inv.copied") : t("inv.share")}
        </button>
      </div>
    </div>
  );
}
