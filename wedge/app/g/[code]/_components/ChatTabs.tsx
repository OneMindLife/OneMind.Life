"use client";

import { useEffect, useState } from "react";
import { getUnplacedCount } from "@/lib/onemind/chat";
import { pendingMatches } from "@/lib/onemind/treeChat";
import css from "../TreeChat.module.css";

// The two-tab surface for repository mode: Replies (read/search/add) and Vote
// (head-to-head matches). The Vote tab carries a notification badge with the
// count of matches waiting for THIS user — the retention pull that turns "there
// are things to rank" into a visible nudge. Pulses during the tutorial vote step.
export function ChatTabs({
  tab,
  setTab,
  replyLabel,
  replyCount,
  roundId,
  participantId,
  votePulse,
}: {
  tab: "replies" | "vote";
  setTab: (t: "replies" | "vote") => void;
  replyLabel: string;
  replyCount: number; // the count of what the list ACTUALLY shows (from the board)
  roundId: number;
  participantId: number;
  votePulse: boolean;
}) {
  const [unplaced, setUnplaced] = useState(0);
  useEffect(() => {
    let alive = true;
    getUnplacedCount(roundId, participantId)
      .then((n) => {
        if (alive) setUnplaced(n);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [roundId, participantId, tab]);

  return (
    <div className={css.chatTabs} role="tablist">
      <button
        role="tab"
        aria-selected={tab === "replies"}
        className={`${css.chatTab} ${tab === "replies" ? css.chatTabOn : ""}`}
        onClick={() => setTab("replies")}
        type="button"
      >
        {replyLabel}
        {replyCount > 0 && <span className={css.tabCount}>({replyCount})</span>}
      </button>
      <button
        role="tab"
        aria-selected={tab === "vote"}
        className={`${css.chatTab} ${tab === "vote" ? css.chatTabOn : ""} ${
          votePulse ? css.pulseCard : ""
        }`}
        onClick={() => setTab("vote")}
        type="button"
      >
        Vote
        {pendingMatches(unplaced) > 0 && (
          <span className={css.tabBadge}>
            {pendingMatches(unplaced) > 9 ? "9+" : pendingMatches(unplaced)}
          </span>
        )}
        {votePulse && (
          <span className={css.tapDemoFinger} aria-hidden>
            👆
          </span>
        )}
      </button>
    </div>
  );
}
