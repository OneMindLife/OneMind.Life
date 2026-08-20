"use client";

import { useEffect, useState } from "react";
import { getUnplacedCount } from "@/lib/onemind/chat";
import { pendingMatches } from "@/lib/onemind/treeChat";
import { VoteIcon } from "./icons";
import css from "../TreeChat.module.css";

// Last-known unplaced count per round, cached for the tab session. Seeding the
// toggle from this on (re)mount stops the badge flashing 0→N every time you
// navigate between levels — the RPC still runs and corrects it, quietly.
const countCache = new Map<number, number>();

// The Vote toggle — the single control that swaps the whole surface between the
// opinions list (+ composer) and the head-to-head voting view. Replaces the old
// two-tab bar: one button, pinned under the composer. Tapped ON, the parent
// hides the list/composer and shows the duel; tapped OFF, the list returns. The
// badge shows how many MATCHES still owe this user a verdict (the pull).
export function VoteToggle({
  roundId,
  participantId,
  active,
  onToggle,
  pulse = false,
  disabled = false,
}: {
  roundId: number;
  participantId: number;
  active: boolean;
  onToggle: () => void;
  pulse?: boolean;
  // Rendered greyed and inert in threads with <2 opinions (nothing to compare
  // yet). Shown rather than hidden so the fixed dock keeps a constant height and
  // the textfield above it never shifts when you move between levels.
  disabled?: boolean;
}) {
  // The displayed count is read straight from the cache each render, so a
  // (re)mount or level change shows the last-known number instantly. The RPC
  // updates the cache and bumps a tick to re-render — no 0→N flash, and no
  // synchronous setState inside the effect.
  const [, bump] = useState(0);
  useEffect(() => {
    // Disabled = nothing to compare (thin thread / empty leaf) — skip the fetch
    // entirely so the toggle can be rendered purely for its height, even where
    // there's no round to query.
    if (disabled) return;
    let alive = true;
    getUnplacedCount(roundId, participantId)
      .then((count) => {
        countCache.set(roundId, count);
        if (alive) bump((x) => x + 1);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [roundId, participantId, active, disabled]);

  const n = pendingMatches(countCache.get(roundId) ?? 0);
  return (
    <button
      className={`${css.voteToggle} ${active ? css.voteToggleOn : ""} ${
        pulse ? css.pulseCard : ""
      }`}
      onClick={onToggle}
      type="button"
      disabled={disabled}
      aria-pressed={active}
      title={
        disabled
          ? "Add a 2nd opinion to compare head-to-head"
          : active
            ? "Back to the opinions"
            : "Compare opinions head-to-head"
      }
    >
      <VoteIcon />
      <span>{active ? "Done" : "Vote"}</span>
      {!active && !disabled && n > 0 && (
        <span className={css.voteToggleBadge}>{n > 99 ? "99+" : n}</span>
      )}
      {pulse && (
        <span className={css.tapDemoFinger} aria-hidden>
          👆
        </span>
      )}
    </button>
  );
}
