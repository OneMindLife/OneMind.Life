"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  getPriorPairwiseVotes,
  getRoundPairwiseVotes,
  getRoundScores,
  markRatingComplete,
  submitPairwiseComparison,
  submitPairwiseSkip,
  type PriorVote,
  type WalkProp,
} from "@/lib/onemind/chat";
import { comparisonSort, pickGlobalPair } from "@/lib/onemind/treeChat";
import { flutterClock } from "@/lib/onemind/globalChat";
import type { TutStep } from "@/lib/onemind/tutorial";
import { BalanceIcon } from "./icons";
import css from "../TreeChat.module.css";

// Voting (live round): collaborative sorting. One GLOBAL list, sorted by
// everyone together. The attention router hands this voter the most informative
// remaining pair (adjacent in the current order → least-judged → closest
// scores); every vote re-sorts the LIVE RANKING below, vote by vote.
export function DuelSection({
  roundId,
  board,
  participantId,
  remainingSec,
  onChanged,
  onExit,
  onVoted,
  advanceTut,
  tutVote = false,
}: {
  roundId: number;
  board: WalkProp[];
  participantId: number;
  remainingSec: number;
  onChanged: () => Promise<void> | void;
  onExit?: () => void;
  onVoted?: () => void; // fired once a real vote lands — peak-intent push offer
  advanceTut?: (to: TutStep) => void;
  tutVote?: boolean; // tutorial is on the "vote" step
}) {
  const myPropIds = useMemo(
    () =>
      new Set(
        board
          .filter((p) => p.participant_id === participantId)
          .map((p) => p.id),
      ),
    [board, participantId],
  );

  const [myVotes, setMyVotes] = useState<PriorVote[] | null>(null);
  // True once this voter has acted on a pair this session — so we auto-close the
  // duel when THEY empty the queue, but not when they open it already-caught-up.
  const acted = useRef(false);
  const [allVotes, setAllVotes] = useState<PriorVote[]>([]);
  const [scores, setScores] = useState<Map<number, number>>(() => new Map());
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);

  const refreshStandings = useCallback(async () => {
    // Server-computed ranking (Bradley-Terry by default) is the source of truth
    // for the LIVE RANKING, so the displayed order always matches the sealed
    // winner. Votes are still fetched for the pair router.
    try {
      const [votes, srv] = await Promise.all([
        getRoundPairwiseVotes(roundId),
        getRoundScores(roundId),
      ]);
      setAllVotes(votes);
      setScores(srv);
    } catch {
      /* standings degrade to the client fallback order */
    }
  }, [roundId]);

  // All votes: refresh on mount, every 10s, and after each own cast.
  useEffect(() => {
    void refreshStandings();
    const t = setInterval(() => void refreshStandings(), 10000);
    return () => clearInterval(t);
  }, [refreshStandings]);

  // My prior judgments (once per round).
  useEffect(() => {
    let alive = true;
    getPriorPairwiseVotes(roundId, participantId)
      .then((v) => {
        if (alive) setMyVotes(v);
      })
      .catch(() => {
        if (alive) setMyVotes([]);
      });
    return () => {
      alive = false;
    };
  }, [roundId, participantId]);

  // Display the SERVER ranking once it exists (single source of truth = matches
  // the winner). Before the first server compute (cold start), fall back to the
  // client head-to-head sort so the list is never unordered.
  const ranked = useMemo(() => {
    if (scores.size > 0) {
      return [...board].sort(
        (a, b) => (scores.get(b.id) ?? -1) - (scores.get(a.id) ?? -1),
      );
    }
    return comparisonSort(board, allVotes);
  }, [board, scores, allVotes]);
  // The shown matchup is PINNED once chosen — the router picks a new pair only
  // when we don't have one (initial, or right after you act), NOT on every
  // render. Without this, each standings refresh (the mount fetch + the 10s
  // poll) re-ran pickGlobalPair — whose adjacency depends on allVotes — and
  // swapped the matchup out from under the reader a few seconds after load.
  const [pinnedPair, setPinnedPair] = useState<{
    top: WalkProp;
    bottom: WalkProp;
  } | null>(null);
  const [exhausted, setExhausted] = useState(false);
  useEffect(() => {
    if (myVotes == null || done) return; // still loading / already finished
    if (pinnedPair != null) return; // keep the current matchup
    const next = pickGlobalPair(
      board,
      allVotes,
      myVotes,
      myPropIds,
      participantId,
    );
    if (next) {
      setPinnedPair(next);
      setExhausted(false);
    } else {
      setExhausted(true);
    }
    // allVotes/board are read to PICK the next pair, but we only pick when
    // pinnedPair is null — so a refresh mid-matchup can't swap the shown pair.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [myVotes, done, pinnedPair, board.length, participantId]);
  const pair = pinnedPair;

  // Anti-spam: a freshly-shown match can't be voted for 3s — it forces a beat
  // of actual consideration instead of mashing through every pair (we saw 37
  // votes in 2 minutes). `voteReady` is DERIVED from which pair the countdown
  // has cleared, not a boolean reset in an effect: resetting in an effect leaves
  // a one-frame window where a new pair renders still-"ready" from the previous
  // one (a fast tap slips through). Deriving locks the new pair on the SAME
  // render — readyKey still points at the old pair until its countdown ends.
  const pairKey = pair ? `${pair.top.id}-${pair.bottom.id}` : null;
  const [readyKey, setReadyKey] = useState<string | null>(null);
  const [countdown, setCountdown] = useState(3);
  const voteReady = pairKey != null && readyKey === pairKey;
  useEffect(() => {
    if (!pairKey) return;
    setCountdown(3);
    let n = 3;
    const id = setInterval(() => {
      n -= 1;
      setCountdown(n);
      if (n <= 0) {
        setReadyKey(pairKey);
        clearInterval(id);
      }
    }, 1000);
    return () => clearInterval(id);
  }, [pairKey]);

  // Content-neutral social proof: how many PEOPLE have weighed in (not per-idea
  // vote counts — those would herd honest judgment). Hidden below a floor so a
  // quiet round never advertises its own emptiness.
  const voterCount = useMemo(
    () => new Set(allVotes.map((v) => v.voterId).filter((x) => x != null)).size,
    [allVotes],
  );
  const showVoterCount = voterCount >= 5;

  // Mark completion once the router runs dry for this voter (no pair to pin).
  useEffect(() => {
    if (exhausted && !done) {
      setDone(true);
      markRatingComplete(roundId, participantId).catch(() => {});
      void onChanged();
      // Clearing the queue is the tutorial's payoff — the list UNLOCKS. Advance
      // the guided step here (not on the first vote), so "you unlocked it" only
      // fires once the lock actually releases.
      if (acted.current) advanceTut?.("share");
      // Cast the last vote → auto-toggle the duel off (back to the list) after a
      // brief "all caught up" beat. Only when THEY drained it, not on open.
      if (acted.current && onExit) setTimeout(onExit, 1100);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [exhausted, done, roundId, participantId]);

  async function cast(winnerId: number, loserId: number, isTie: boolean) {
    if (busy || myVotes == null || !voteReady) return; // 3s consideration gate
    setBusy(true);
    try {
      await submitPairwiseComparison(
        roundId,
        participantId,
        winnerId,
        loserId,
        isTie,
      );
      // My judgment lands in both pools instantly — the ranking re-sorts
      // vote by vote, and the router picks my next match from fresh state.
      const v = { winnerId, loserId, isTie, isSkip: false, voterId: participantId };
      const firstVote = !acted.current;
      acted.current = true;
      setMyVotes((prev) => [...(prev ?? []), v]);
      setAllVotes((prev) => [...prev, v]);
      setPinnedPair(null); // acted → let the router pick the next matchup
      void refreshStandings();
      // Voting is the most common engaged action (far more people vote than
      // post), so this is where the return-ping offer reaches the widest slice.
      // Fire once, on the first vote — the offer itself is idempotent.
      if (firstVote) onVoted?.();
    } catch {
      /* leave the pair up — a retry can win */
    } finally {
      setBusy(false);
    }
  }

  /// Skip THIS pair: counts as seen (exposure) and never re-offers the
  /// matchup, crowns no winner, moves on.
  async function skipPair(aId: number, bId: number) {
    if (busy || myVotes == null) return;
    setBusy(true);
    try {
      await submitPairwiseSkip(roundId, participantId, aId, bId);
      const v = {
        winnerId: aId,
        loserId: bId,
        isTie: false,
        isSkip: true,
        voterId: participantId,
      };
      acted.current = true;
      setMyVotes((prev) => [...(prev ?? []), v]);
      setAllVotes((prev) => [...prev, v]);
      setPinnedPair(null); // skipped → let the router pick the next matchup
    } catch {
      /* leave the pair up */
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      {/* No back control here — the Replies|Vote tab bar above already returns
          to the opinions list; a second "back" was redundant chrome. */}
      {pair && (
        <>
          {tutVote && (
            <div className={css.tapHint}>
              👋 Pick the one you think is stronger — your call moves the
              ranking. This is how you&apos;re heard.
            </div>
          )}
          {/* CONSTANT header — it used to swap to "READ BOTH · 3" during the
              gate, which made the top of the screen flicker on every pair. The
              countdown now lives in the Equal pill (dead centre, between the two
              options — where the eye already is while you read them). */}
          <div className={`${css.levelHeader} ${css.actionHeader}`}>
            <span className={css.levelHeaderText}>
              {onExit ? "VOTE — TAP THE STRONGER" : "VOTE — TAP THE BETTER ONE"}
            </span>
          </div>
          <div
            className={`${css.duelWrap} ${busy ? css.busyDim : ""} ${
              !voteReady ? css.duelLocked : ""
            }`}
          >
            <div
              className={css.duelCol}
              key={`${pair.top.id}_${pair.bottom.id}`}
            >
              <button
                className={css.duelOption}
                onClick={() => void cast(pair.top.id, pair.bottom.id, false)}
                disabled={busy || !voteReady}
                type="button"
              >
                {pair.top.content}
              </button>
              <div className={css.equalRow}>
                <button
                  className={`${css.equalPill} ${
                    !voteReady ? css.equalPillCounting : ""
                  }`}
                  onClick={() => void cast(pair.top.id, pair.bottom.id, true)}
                  disabled={busy || !voteReady}
                  type="button"
                  aria-label={
                    voteReady ? "Equal" : `Read both — ${countdown} seconds`
                  }
                >
                  {voteReady ? (
                    <>
                      <BalanceIcon />
                      Equal
                    </>
                  ) : (
                    // The gate, shown where you're already looking. Reverts to
                    // "Equal" the moment it clears.
                    <span className={css.equalCount}>{countdown}</span>
                  )}
                </button>
              </div>
              <button
                className={css.duelOption}
                onClick={() => void cast(pair.bottom.id, pair.top.id, false)}
                disabled={busy || !voteReady}
                type="button"
              >
                {pair.bottom.content}
              </button>
            </div>
          </div>
          <button
            className={css.skipBtn}
            onClick={() => void skipPair(pair.top.id, pair.bottom.id)}
            disabled={busy || !voteReady}
            type="button"
          >
            Skip this pair
          </button>
          {/* Repository mode carries no note — the duel is the whole message.
              (Phase-gated chats still need their deadline.) */}
          {!onExit && (
            <div className={css.deadlineNote}>
              ⏳ Voting ends in {flutterClock(remainingSec)} — then the order
              locks and the next round begins.
            </div>
          )}
        </>
      )}

      {(myVotes == null || (!pair && !exhausted)) && (
        <div className={css.boot}>
          <div className={css.spinner} />
        </div>
      )}

      {/* The queue is empty. CRITICAL: only claim credit if they actually voted
          THIS visit (`acted`) — arriving at an already-cleared node and being
          told "you've been heard / your take shaped this ranking" is a flat lie
          and cheapens the real thing. The auto-exit was always gated on acted;
          the copy wasn't. */}
      {exhausted && (
        <div className={css.doneBox}>
          <div className={css.doneBig}>
            {!onExit
              ? "✓ Your votes are in"
              : acted.current
                ? "🎉 You've been heard"
                : "Nothing to weigh in on here"}
          </div>
          {onExit && acted.current && ranked.length > 0 && (
            <div className={css.doneTop}>
              <span className={css.doneTopLabel}>NOW #1</span>
              <span className={css.doneTopText}>{ranked[0].content}</span>
            </div>
          )}
          <div className={css.doneSmall}>
            {!onExit
              ? `This round ends in ${flutterClock(remainingSec)} — the list below keeps sorting as others vote.`
              : acted.current
                ? "Your take helped shape this ranking. Weigh in on more whenever you like."
                : "You've already weighed in on everything here — new opinions will show up as people add them."}
          </div>
          {onExit && (
            <button
              className={css.placeBackBtn}
              onClick={onExit}
              type="button"
            >
              Back to browsing
            </button>
          )}
        </div>
      )}

      {showVoterCount && (
        <div className={css.voterCount}>
          👥 {voterCount} people have voted on these
        </div>
      )}

      {/* The one global list, sorted by everyone together — re-sorts on
          every vote (yours instantly; others on refresh). Hidden while PLACING
          (repository mode): showing the current order anchors the voter toward
          it — honest judgment needs a blind comparison. */}
      {!onExit && (
        <>
          <div className={css.levelHeader}>
            <span className={css.levelHeaderText}>LIVE RANKING</span>
          </div>
          {ranked.map((r, i) => (
            <div key={r.id} className={css.feedCard}>
              <span className={css.rank}>#{i + 1}</span>
              <span className={css.text}>{r.content}</span>
              {r.participant_id == null && <span className={css.aiTag}>AI</span>}
              {r.participant_id === participantId && (
                <span className={css.youTag}>You</span>
              )}
            </div>
          ))}
        </>
      )}
    </section>
  );
}
