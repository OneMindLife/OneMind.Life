"use client";

import { useEffect, useState } from "react";
import { getUnplacedCount } from "@/lib/onemind/chat";
import { voteFabEnabled } from "@/lib/onemind/fabState";
import { pendingMatches } from "@/lib/onemind/treeChat";
import { VoteIcon } from "./icons";
import css from "../TreeChat.module.css";

// Last-known pending count per round (session cache) — seeds the Vote FAB so it
// doesn't flash off→on when you navigate between levels.
const readyCache = new Map<number, number>();

/// The Vote action as a docked BOTTOM BAR — a full-width button shaped like the
/// list rows, so it reads as "vote on THIS list" (clearly tied to the ranking
/// above) rather than a floating corner action. Inert/muted when there's nothing
/// to weigh in on at this node, accent-filled + glowing with a count when there
/// is; toggles to "Back to browsing" while voting. Fetches its own pending count.
///
/// There is no Post button here: the opinion composer lives at the TOP of the
/// list on every screen (OpinionComposer), which makes adding your own
/// self-evident instead of hiding it behind a "+".
export function ActionFabs({
  roundId,
  participantId,
  hasPair,
  refreshKey,
  voteActive,
  onVote,
  tutVote = false,
}: {
  roundId: number | null; // current node's live round (null while it loads)
  participantId: number;
  hasPair: boolean; // >=2 real opinions here (a pair to compare)
  refreshKey: string | number; // bump to refetch (mode change / board grew)
  voteActive: boolean; // currently in voting mode?
  onVote: () => void;
  tutVote?: boolean; // tutorial is on the "vote" step
}) {
  const [, bump] = useState(0);
  useEffect(() => {
    if (roundId == null) return;
    let alive = true;
    getUnplacedCount(roundId, participantId)
      .then((n) => {
        readyCache.set(roundId, n);
        if (alive) bump((x) => x + 1);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [roundId, participantId, refreshKey]);

  const count = roundId != null ? (readyCache.get(roundId) ?? 0) : 0;
  const voteEnabled = voteFabEnabled(hasPair, count);
  // How many head-to-head duels you can clear right here (current level only).
  const duelsHere = pendingMatches(count);
  const votePulse = tutVote && voteEnabled;
  const voteState = voteActive
    ? css.voteBarActive
    : voteEnabled
      ? css.voteBarReady
      : css.voteBarDisabled;

  // Label carries the meaning (a ballot glyph isn't universally read) AND ties
  // the button to the list: "Vote on these" reads as the action for the ranking
  // right above it.
  const label = voteActive
    ? "Back to browsing"
    : voteEnabled
      ? "Vote on these"
      : "Nothing to vote on yet";
  return (
    <div className={css.voteBar}>
      <button
        className={`${css.voteBarBtn} ${voteState} ${
          votePulse ? css.pulseCard : ""
        }`}
        onClick={onVote}
        disabled={!voteEnabled && !voteActive}
        type="button"
        aria-pressed={voteActive}
        aria-label={voteActive ? "Back to browsing" : "Vote on these opinions"}
        title={
          voteActive
            ? "Back to browsing"
            : voteEnabled
              ? "Vote — pick which idea is stronger"
              : "Nothing to weigh in on here yet"
        }
      >
        <VoteIcon />
        <span className={css.voteBarLabel}>{label}</span>
        {/* Count of duels you can clear here, right now — inline with the label. */}
        {voteEnabled && !voteActive && duelsHere > 0 && (
          <span className={css.voteBarCount}>
            {duelsHere > 99 ? "99+" : duelsHere}
          </span>
        )}
      </button>
    </div>
  );
}
