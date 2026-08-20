"use client";

import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { track } from "@/lib/onemind/analytics";
import { useI18n } from "@/lib/i18n";
import { isTelegramContext, telegramInviteLink, shareViaTelegram, isMobile } from "@/lib/telegram";
import { ShareIcon } from "./ui";

/// Compact, always-present invite in the top rail — so a host can pull people in
/// at ANY phase, including mid-voting where the big InviteBlock isn't shown. The
/// invite loop is OneMind's growth engine (D39; chat 794 = one ad click → a
/// 10-person group via shared link), and mid-voting is exactly when a host
/// realizes they need more voters (the small-group fix). Fires quick_chat_share
/// (the viral signal; auto play_mode-stamped for the H-FUN experiment).
///
/// Tapping it opens a dialog with the copyable link AND a QR code — so the host
/// can either send the link remotely or have people in the room scan to join.
export default function RailInvite({ code }: { code: string }) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  // Inside Telegram, invite via the bot deep-link so tapping it re-opens the
  // Mini App straight into this chat (the group loop). On the web, the plain
  // chat URL.
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
      track("quick_chat_share", { source: "rail" });
    } catch {
      /* clipboard blocked — no-op */
    }
  }

  async function share() {
    // Inside Telegram: open Telegram's native "send to a chat" picker, pre-filled
    // with the deep-link — one tap, pick the group, sent.
    if (shareViaTelegram(url, t("rail.shareText"))) {
      track("quick_chat_share", { source: "telegram" });
      return;
    }
    // Mobile → native share sheet. Web → skip straight to copying the link.
    if (isMobile() && typeof navigator !== "undefined" && navigator.share) {
      try {
        await navigator.share({ url });
        track("quick_chat_share", { source: "rail_native" });
        return;
      } catch {
        /* user dismissed or share unavailable — fall through to copy */
      }
    }
    await copy();
  }

  return (
    <>
      <button
        className="rail-invite beckon-w"
        onClick={() => setOpen(true)}
        type="button"
      >
        <ShareIcon />
        <span>{t("rail.invite")}</span>
      </button>

      {open && (
        <div className="scrim" onClick={() => setOpen(false)}>
          <div className="sheet" onClick={(e) => e.stopPropagation()}>
            <h3>{t("rail.dialogTitle")}</h3>
            <div className="sub">{t("rail.dialogSub")}</div>

            <button className="primary beckon-w" onClick={share} type="button">
              <ShareIcon />
              {t("rail.shareLink")}
            </button>

            <div className="share" style={{ marginTop: 12, marginBottom: 0 }}>
              <div className="row">
                <div className="link">{display}</div>
                <button className="copy" onClick={copy} type="button">
                  {copied ? t("rail.copied") : t("rail.copy")}
                </button>
              </div>
            </div>

            <div className="invite-qr-wrap">
              <div className="invite-qr-or">{t("rail.orScan")}</div>
              <div className="invite-qr">
                <QRCodeSVG value={url} size={180} level="M" />
              </div>
            </div>

            <button
              className="secondary"
              onClick={() => setOpen(false)}
              type="button"
            >
              <u>{t("rail.done")}</u>
            </button>
          </div>
        </div>
      )}
    </>
  );
}
