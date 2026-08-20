"use client";

import { useState } from "react";
import { getChatSocialProof, getRankedProps, type WalkProp } from "@/lib/onemind/chat";
import { renderChainCard } from "@/lib/onemind/chainCard";
import { track } from "@/lib/onemind/analytics";
import {
  isTelegramContext,
  shareViaTelegram,
  telegramInviteLink,
} from "@/lib/telegram";
import { ShareIcon } from "./icons";
import css from "../TreeChat.module.css";

// The user's descended path as a SHAREABLE artifact. The stack IS the content:
// share a card that mirrors the on-screen chain (so the recipient understands
// OneMind before clicking) + a link back. Grows with depth — the label narrates
// the mechanic ("your chain · N ideas"). Self-curating: people share the chains
// they're proud of, so quality controls itself.
export function ChainShareBar({
  quotes,
  code,
  chatId,
  pulse = false,
  onShared,
}: {
  quotes: { text: string; propId: number; roundId: number }[];
  code: string;
  chatId: number;
  pulse?: boolean;
  onShared?: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const clean = quotes.filter((q) => q.text);
  const n = clean.length;
  // Only surfaces once you've descended (picked ≥1 for the stack). At the root
  // (list of opinions) the appbar Share handles room-sharing instead.
  if (n < 1) return null;

  async function share() {
    if (busy) return;
    onShared?.(); // last tutorial step / completes the share beat optimistically
    setBusy(true);
    const url = `${window.location.origin}/g/${code}`;

    // Inside Telegram: deep-link the recipient straight onto this chain's LEAF
    // take via the native picker. openTelegramLink can't carry the chain image,
    // so we send the link + a one-line hook (still opens in-app on the take,
    // which is the point). No-op / false outside Telegram → falls through.
    if (isTelegramContext()) {
      const leaf = clean[clean.length - 1];
      if (
        shareViaTelegram(
          telegramInviteLink(code, leaf?.propId),
          "A chain of ideas from OneMind — the best win, not the loudest 👇",
        )
      ) {
        track("chain_shared", { depth: n, code, tg: true });
        setBusy(false);
        return;
      }
    }

    // Nothing descended yet — just share the room link (native sheet on mobile,
    // clipboard on desktop). No chain card to render at depth 0.
    if (n === 0) {
      track("room_shared", { code });
      try {
        if (navigator.share) await navigator.share({ title: "OneMind", url });
        else {
          await navigator.clipboard.writeText(url);
          setToast("Link copied");
          setTimeout(() => setToast(null), 2000);
        }
      } catch {
        /* dismissed / clipboard unavailable */
      }
      setBusy(false);
      return;
    }

    track("chain_shared", { depth: n, code });

    // Each idea's TRUE rank at its OWN level (getRankedProps is best-first).
    // This is the only honest head-to-head claim — the stack itself is a path,
    // not a set ranked against each other. Memoize per round.
    const rankCache = new Map<number, WalkProp[]>();
    const enriched = await Promise.all(
      clean.map(async (q) => {
        try {
          let ranked = rankCache.get(q.roundId);
          if (!ranked) {
            ranked = await getRankedProps(q.roundId);
            rankCache.set(q.roundId, ranked);
          }
          const idx = ranked.findIndex((p) => p.id === q.propId);
          return {
            text: q.text,
            rank: idx >= 0 ? idx + 1 : null,
            total: ranked.length || null,
          };
        } catch {
          return { text: q.text, rank: null, total: null };
        }
      }),
    );

    const text =
      "A chain of ideas from OneMind — where the best ideas win, not the loudest:\n\n" +
      enriched
        .map(
          (q, i) =>
            `${i + 1}. “${q.text}”${q.rank ? ` (ranked #${q.rank} of ${q.total} at its level)` : ""}`,
        )
        .join("\n\n") +
      `\n\nExplore → ${url}`;
    try {
      const stats = await getChatSocialProof(chatId).catch(() => null);
      const blob = await renderChainCard(enriched, stats);
      const file = blob
        ? new File([blob], "onemind-chain.png", { type: "image/png" })
        : null;
      const nav = navigator as Navigator & {
        canShare?: (d: { files?: File[] }) => boolean;
      };
      if (file && nav.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], text, url } as ShareData);
      } else if (navigator.share) {
        await navigator.share({ text, url });
      } else {
        // Desktop: hand them the card to post + copy the link.
        if (blob) {
          const a = document.createElement("a");
          a.href = URL.createObjectURL(blob);
          a.download = "onemind-chain.png";
          a.click();
          URL.revokeObjectURL(a.href);
        }
        try {
          await navigator.clipboard.writeText(url);
        } catch {
          /* clipboard unavailable */
        }
        setToast(blob ? "Card saved · link copied" : "Link copied");
        setTimeout(() => setToast(null), 2200);
      }
    } catch {
      /* share sheet dismissed or failed — no-op */
    } finally {
      setBusy(false);
    }
  }

  return (
    <button
      className={`${css.chainShareBtn} ${pulse ? css.pulseCard : ""}`}
      onClick={() => void share()}
      type="button"
      disabled={busy}
    >
      {toast ?? "Share"} <ShareIcon />
    </button>
  );
}
