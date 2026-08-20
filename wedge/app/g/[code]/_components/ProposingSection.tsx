"use client";

import { useEffect, useState, type ReactNode } from "react";
import {
  DuplicatePropositionError,
  getMatchesVoteCount,
  getSubtreePendingMatches,
  getUnplacedCount,
  recordThreadOpen,
  submitProposition,
  type WalkProp,
} from "@/lib/onemind/chat";
import {
  highlightSegments,
  pendingMatches,
  similarProps,
} from "@/lib/onemind/treeChat";
import { flutterClock } from "@/lib/onemind/globalChat";
import type { TutStep } from "@/lib/onemind/tutorial";
import { AutoGrowTextarea } from "./AutoGrowTextarea";
import { TutorialFinger } from "./TutorialFinger";
import { CloseIcon, SearchIcon, VoteIcon } from "./icons";
import { SendButton } from "./SendButton";
import css from "../TreeChat.module.css";

// Proposing (live round): a Twitter-style feed. Composer on top; EVERYTHING
// below is the full realtime feed, oldest-first (newest right above the
// composer). Typing fuzzy-filters the whole list to similar takes (best match
// first, overlap highlighted) — duplicate awareness across the entire board.
export function ProposingSection({
  roundId,
  board,
  participantId,
  remainingSec,
  onChanged,
  onOpen,
  repository = false,
  onPlace,
  isReply = false,
  tutStep,
  advanceTut,
  footer,
  listOnly = false,
}: {
  roundId: number;
  board: WalkProp[];
  participantId: number;
  remainingSec: number;
  onChanged: () => Promise<void> | void;
  onOpen: (propId: number) => void;
  repository?: boolean;
  onPlace?: () => void;
  isReply?: boolean;
  tutStep?: TutStep;
  advanceTut?: (to: TutStep) => void;
  footer?: ReactNode; // the Vote toggle, pinned under the composer (repository)
  // FAB mode (repository): render ONLY the list — no inline composer, no search,
  // no place-pull. Posting + voting move to the stacked FABs. Non-repo chats
  // leave this false and keep the inline composer.
  listOnly?: boolean;
}) {
  // Contextual language teaches the tree: top-level = "opinions", but once
  // you've descended into an opinion, what you see/add are "replies" to it.
  // Everything is an "opinion" — a reply is itself a merit-ranked opinion, so we
  // use one consistent noun at every depth (the thread context conveys "in reply
  // to").
  const noun = "opinion";
  // Repository mode: "N to place" pull — opinions this user hasn't ranked yet.
  const [unplaced, setUnplaced] = useState(0);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [justSent, setJustSent] = useState<string | null>(null);
  // Total votes in this round — the status line's evidence ("N votes · N
  // opinions"). Only fetched for the ranked browse list.
  const [roundVotes, setRoundVotes] = useState<number | null>(null);
  useEffect(() => {
    if (!listOnly) return;
    let alive = true;
    getMatchesVoteCount(roundId)
      .then((n) => alive && setRoundVotes(n))
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [listOnly, roundId, board.length, justSent]);

  // The list is no longer remounted on level navigation (the fixed composer dock
  // must persist across levels, or it jitters), so this same instance is reused
  // when you descend/go back. Clear per-level composer state when the round
  // changes — else a just-sent optimistic card or half-typed draft would bleed
  // into the next thread.
  useEffect(() => {
    setDraft("");
    setErr(null);
    setJustSent(null);
  }, [roundId]);

  // Refetch the "to place" count on mount, when the board grows, and after the
  // user adds one (justSent). Only matters in repository mode.
  useEffect(() => {
    if (!repository || listOnly) return; // FAB mode: the Vote FAB owns this count
    let alive = true;
    getUnplacedCount(roundId, participantId)
      .then((n) => {
        if (alive) setUnplaced(n);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [repository, listOnly, roundId, participantId, board.length, justSent]);

  // Per-option "votes waiting below" — pending pairwise MATCHES this user owes
  // across the WHOLE subtree beneath each opinion. Drives the votes-waiting slot
  // on every card, so people can pick the branches they actually want to clear.
  // Match-counted server-side; per-user, and depletes as they vote. Refreshed
  // when the board changes or the user adds one.
  const [voteCounts, setVoteCounts] = useState<Map<number, number>>(
    () => new Map(),
  );
  useEffect(() => {
    let alive = true;
    getSubtreePendingMatches(roundId, participantId)
      .then((votes) => {
        if (alive) setVoteCounts(votes);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [roundId, participantId, board.length, justSent]);

  // Explicit, opt-in search (FAB/listOnly mode). The default action is to
  // SCROLL — searching is a deliberate act for when you're after something
  // particular, so it hides behind a 🔍 on the ranking header instead of
  // hijacking the composer. Scope is this node's DIRECT CHILDREN (`board`)
  // only — that's the list you're looking at.
  const [search, setSearch] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  // Legacy (non-listOnly) chats kept the old behaviour: typing in the inline
  // composer doubles as a filter.
  const query = (listOnly ? search : draft).trim();
  const searching = query.length > 0;

  // Which tutorial nudge lights up on THIS surface (driven by the shared step):
  //  tap   → pulse the first idea at the root  ("tap into a thread")
  //  reply → pulse the composer inside a thread ("leave a reply")
  //  vote  → pulse the "N to place" pull        ("vote a match")
  const showTapHint = tutStep === "tap" && !isReply && !searching;
  const showReplyHint =
    tutStep === "reply" && isReply && !searching && query.length === 0;
  const showVoteHint = tutStep === "vote" && repository;

  const optimistic =
    justSent != null && !board.some((p) => p.content === justSent)
      ? [
          ...board,
          { id: -1, content: justSent, participant_id: participantId },
        ]
      : board;
  // Chat order at rest: oldest at top, newest (incl. the just-sent reply) at the
  // bottom — right above the composer. While typing, show ALL similar matches
  // (best first).
  const items = listOnly
    ? searching
      ? similarProps(board, query) // direct children of this node only
      : board
    : searching
      ? similarProps(optimistic, query)
      : optimistic;

  async function send() {
    const content = draft.trim();
    if (!content || sending) return;
    setSending(true);
    setErr(null);
    try {
      await submitProposition(roundId, participantId, content);
      setJustSent(content);
      setDraft("");
      if (isReply) advanceTut?.("back"); // replied → next: tap back up to the root
      await onChanged();
    } catch (e) {
      setErr(
        e instanceof DuplicatePropositionError
          ? "That proposition already exists in this round."
          : "Could not submit — try again.",
      );
    } finally {
      setSending(false);
    }
  }

  return (
    <section>
      {/* The pull: head-to-head MATCHES this user still owes here. Like unread
          notifications — the count tugs; voting clears it. Counts taps (pairs),
          not raw opinions, so "one tap each" is literal. */}
      {!listOnly &&
        repository &&
        onPlace &&
        pendingMatches(unplaced) > 0 &&
        !searching && (
        <button
          className={`${css.placePull} ${showVoteHint ? css.pulseCard : ""}`}
          onClick={onPlace}
          type="button"
        >
          <span className={css.placeBadge}>
            {pendingMatches(unplaced) > 99 ? "99+" : pendingMatches(unplaced)}
          </span>
          <span className={css.placeText}>
            <b>
              {showVoteHint
                ? "Vote a match — tap to try"
                : pendingMatches(unplaced) === 1
                  ? "1 match to vote"
                  : `${pendingMatches(unplaced)} matches to vote`}
            </b>
            <small>Two ideas per match — pick the stronger.</small>
          </span>
          <span className={css.placeGo} aria-hidden>
            ›
          </span>
          {showVoteHint && (
            <span className={css.tapDemoFinger} aria-hidden>
              👆
            </span>
          )}
        </button>
      )}

      {showTapHint && items.length > 0 && (
        <div className={css.tapHint} aria-hidden>
          Tap an opinion to open its thread
        </div>
      )}

      {/* NOTE: the "N more to weigh in on across this chat" banner used to sit
          here. Removed — it was the 4th voting signal on the screen (banner +
          this header + a green count on every card + the "Vote N" FAB), for the
          one behaviour that was never broken (~26% vote). It also cost a
          chat-wide RPC per node view. The slots and the FAB carry the pull. */}

      {/* Say out loud that this is a RANKING, not a feed — otherwise the order
          is invisible and "why would I vote?" has no answer. The 🔍 sits HERE
          (not the appbar) because it only filters THIS list; an appbar search
          would promise chat-wide and under-deliver. */}
      {/* Provenance — why this ranking is worth trusting, in the newcomer's
          first impression (root only; not while searching). */}
      {listOnly && !isReply && !searching && board.length > 1 && (
        <p className={css.rankProvenance}>
          Ranked by real people voting head-to-head — no algorithm decides what
          rises.
        </p>
      )}
      {/* Status line — the record's live totals. */}
      {listOnly && !searching && board.length > 1 && (
        <div className={css.statusLine}>
          {roundVotes != null ? roundVotes.toLocaleString() : "—"} votes ·{" "}
          {board.length} opinions
        </div>
      )}
      {/* Column header — labels the flat register (Rk · Opinion · Votes) and
          hosts the opt-in 🔍. Aligns with the row columns below. */}
      {listOnly && board.length > 1 && (
        <div className={css.rankHeader}>
          {searchOpen ? (
            <>
              <span className={css.searchGlyph} aria-hidden>
                <SearchIcon />
              </span>
              <input
                className={css.searchInput}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Find in this thread…"
                aria-label="Find in this thread"
                autoFocus
              />
              <button
                className={css.searchBtn}
                onClick={() => {
                  setSearch("");
                  setSearchOpen(false);
                }}
                type="button"
                aria-label="Close search"
                title="Close search"
              >
                <CloseIcon />
              </button>
            </>
          ) : (
            <>
              <span className={css.colOp}>Opinion</span>
              <span className={css.colVotes}>Score</span>
              <button
                className={css.searchBtn}
                onClick={() => setSearchOpen(true)}
                type="button"
                aria-label="Find in this thread"
                title="Find in this thread"
              >
                <SearchIcon />
              </button>
            </>
          )}
        </div>
      )}
      {searching && listOnly && items.length === 0 && (
        <div className={css.emptyNote}>No match in this thread.</div>
      )}

      {items.length === 0 ? (
        <div className={css.emptyNote}>
          {searching
            ? "Nothing similar yet — yours is new."
            : "No opinions yet — be the first."}
        </div>
      ) : (
        items.map((p, i) => {
          const tapDemo = showTapHint && i === 0;
          // #1 in the ranked list is the EARNED consensus — the only card that
          // gets the civic-blue mark, so the accent means "the crowd chose this"
          // instead of decorating every card.
          const isWinner = listOnly && !searching && p.id > 0 && i === 0;
          const pending = p.id > 0 ? voteCounts.get(p.id) ?? 0 : 0;
          return (
          <button
            key={p.id}
            type="button"
            className={`${css.feedCard} ${css.optionCard} ${
              listOnly ? css.recordRow : ""
            } ${isWinner ? css.optionWin : ""} ${
              p.participant_id === participantId ? css.mineCard : ""
            } ${tapDemo ? `${css.pulseCard} ${css.tapDemoCard}` : ""}`}
            onClick={() => {
              if (p.id > 0) {
                // Browse-first: descending is free navigation, not a tutorial
                // step — don't advance (the guided step is tap-Vote-to-weigh-in).
                void recordThreadOpen(p.id, participantId);
                onOpen(p.id);
              }
            }}
            disabled={p.id <= 0}
            title={`Open this ${noun}'s thread`}
          >
            {/* Rank — the list is ALREADY sorted best-first (getRankedProps →
                get_propositions_with_scores); without the number nobody can see
                that, so it reads as an arbitrary pile and voting has no visible
                purpose. Only in the browse list, where the order genuinely IS
                the ranking (a live proposing board isn't ranked yet, and search
                reorders by similarity — a number there would be a lie). */}
            {/* Top line of the record row: rank · opinion · total votes · chev.
                A flex row; the pending pill sits BELOW it, centered. */}
            <span className={css.rowTop}>
              <span className={css.optionMain}>
                <span className={css.text}>
                  {searching
                    ? highlightSegments(p.content, query).map((seg, si) =>
                        seg.hit ? (
                          <span key={si} className={css.hl}>
                            {seg.text}
                          </span>
                        ) : (
                          <span key={si}>{seg.text}</span>
                        ),
                      )
                    : p.content}
                </span>
              </span>
              {p.participant_id == null && <span className={css.aiTag}>AI</span>}
              {/* Score (0–100) — what ORDERS the list and justifies each
                  opinion's position. "—" when unrated (too few matchups yet). */}
              {listOnly && !searching && p.id > 0 && p.score != null && (
                <span className={css.votesTally}>
                  <span className={css.votesNum}>
                    {p.score > 0 ? Math.round(p.score) : "—"}
                  </span>
                </span>
              )}
              {p.id > 0 && (
                <span className={css.openChev} aria-hidden>
                  ›
                </span>
              )}
            </span>
            {/* Pending pill — bottom-CENTER of the row: the functional "votes
                waiting for you here" pull, below the record data. Only when >0. */}
            {pending > 0 && (
              <span
                className={`${css.voteSlot} ${css.voteSlotFull} ${css.pendingBottom}`}
                title={`${pending} to weigh in on below`}
              >
                <VoteIcon />
                <span className={css.voteSlotNum}>
                  {pending > 99 ? "99+" : pending}
                </span>
                <span className={css.pendingLabel}>to vote</span>
              </span>
            )}
            {tapDemo && (
              <>
                <span className={css.tapRipple} aria-hidden />
                <span className={css.tapDemoFinger} aria-hidden>
                  👆
                </span>
              </>
            )}
          </button>
          );
        })
      )}

      {/* Inline composer — only in non-FAB (non-repository) mode. In FAB mode the
          stacked Post FAB + compose sheet replace this. Sticky-bottom dock. */}
      {!listOnly && (
        <>
          {showReplyHint && (
            <TutorialFinger toX="50%" toY="calc(100dvh - 52px)" />
          )}
          <div className={css.composerDock}>
            {showReplyHint && (
              <div className={css.tapHint} aria-hidden>
                Now add your opinion
              </div>
            )}
            <div
              className={`${css.composerCard} ${
                showReplyHint ? css.pulseCard : ""
              }`}
            >
              <AutoGrowTextarea
                value={draft}
                onChange={setDraft}
                onSubmit={() => void send()}
                placeholder="Search or add your opinion…"
                maxLength={300}
                disabled={sending}
              />
              <SendButton
                sending={sending}
                disabled={query.length === 0}
                onSend={() => void send()}
              />
            </div>
            {err && <div className={css.errNote}>{err}</div>}
            {footer}
            {!searching && !repository && (
              <div className={css.deadlineNote}>
                ⏳ Voting starts in {flutterClock(remainingSec)} — add your
                opinion until then.
              </div>
            )}
          </div>
        </>
      )}
    </section>
  );
}
