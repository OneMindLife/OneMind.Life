"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  getPriorPairwiseVotes,
  submitPairwiseComparison,
  submitPairwiseSkip,
  markRatingComplete,
  hostEndVoting,
  getMatchesDoneCount,
  getMatchesVoteCount,
  chatQuestion,
  propContent,
  type Bootstrap,
  type PriorVote,
} from "@/lib/onemind/chat";
import {
  nextPair,
  type MatchObjective,
  type MatchPair,
  type Rateable,
} from "@/lib/onemind/matchPairSelector";
import { useI18n } from "@/lib/i18n";
import {
  AppShell,
  Rail,
  ChatQuestion,
  Check,
} from "../../components/ui";
import PresenceBadge from "./PresenceBadge";
import GameStatus from "./GameStatus";
import RailInvite from "../../components/RailInvite";
import LangToggle from "../../components/LangToggle";

type Phase =
  | { kind: "loading" }
  | { kind: "pair"; pair: MatchPair }
  // No pair can form for this rater — the only idea(s) available are their own /
  // too few others'. They CAN'T vote (you don't rate your own), so we show an
  // honest "invite others" empty-state instead of falsely marking them done.
  | { kind: "nothing_to_vote" }
  | { kind: "done" }
  | { kind: "error"; message: string };

const NEED_RATERS = 2;

/// Matches (pairwise) voting: show two ideas, pick the better one. Repeats until
/// the pair selector is exhausted (equal-exposure invariant, winner_only =
/// losers drop). When done, the rater is marked complete; the host ends voting
/// to lock in the winner. Round 2+ marks the carried-forward leader specially.
export default function Voting({
  data,
  code,
  presence,
  onChanged,
}: {
  data: Bootstrap;
  code: string;
  presence: number;
  onChanged: () => Promise<void> | void;
}) {
  const { t } = useI18n();
  const round = data.current_round!;
  const me = data.my_participant!;
  const isHost = me.is_host;
  const isGame = data.chat.mode === "game";
  const roundNo = (round.custom_id as number) || 1;
  const objective = ((data.chat.match_objective as string) ||
    "winner_only") as MatchObjective;
  const question = chatQuestion(data.chat);
  // Everyone currently in the chat. Auto-advance fires once they're all done.
  const activeCount = (data.participants ?? []).filter(
    (p) => p.status === "active",
  ).length;

  const rateable: Rateable[] = useMemo(() => {
    const props = data.propositions ?? [];
    const nonOwn = props.filter((p) => p.participant_id !== me.id);
    // Conditional self-inclusion: you never vote on your own idea — unless
    // excluding it leaves you under 2 (e.g. a 2-person leader-vs-challenger
    // round), in which case the pair includes your own and voting for the
    // other idea is an explicit concession. Keeps 2-person chats functional.
    const votable = nonOwn.length >= 2 ? nonOwn : props;
    return votable.map((p) => ({ id: p.id, content: propContent(p) }));
  }, [data.propositions, me.id]);

  // id → current (translated) text. The displayed pair lives in `phase` state
  // with its text captured when the pair was built, so it WON'T update when the
  // language changes mid-vote. Resolving the card text by id from the live data
  // at render time keeps the options in sync with the chosen language (and with
  // any late-arriving translation), without disturbing the user's place in the
  // pair sequence.
  const contentById = useMemo(() => {
    const m = new Map<number, string>();
    (data.propositions ?? []).forEach((p) => m.set(p.id, propContent(p)));
    return m;
  }, [data.propositions]);

  const [votes, setVotes] = useState<PriorVote[]>([]);
  const [phase, setPhase] = useState<Phase>({ kind: "loading" });
  const [busy, setBusy] = useState(false);
  // Which control is mid-submit, so the tapped button shows a loading state
  // (otherwise a slow network looks unresponsive and people double-tap).
  const [pending, setPending] = useState<number | "equal" | "skip" | null>(null);
  const [endingVote, setEndingVote] = useState(false);
  const [ratersDone, setRatersDone] = useState(0);
  // Real (non-skip) votes cast in the round. The host can only end once there's
  // at least one — otherwise a round where everyone could only see their own
  // idea (0 votes) would finalize into a meaningless winner.
  const [voteCount, setVoteCount] = useState(0);

  // Live "others done voting" + "real votes" counts (matches mode). Re-fetched
  // whenever the chat reloads (new `data`) or our phase changes, so the host's
  // gate reflects reality.
  useEffect(() => {
    let alive = true;
    Promise.all([getMatchesDoneCount(round.id), getMatchesVoteCount(round.id)])
      .then(([done, votes]) => {
        if (!alive) return;
        setRatersDone(done);
        setVoteCount(votes);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [round.id, data, phase]);

  // Rating auto-finalize is now a BACKEND trigger (matches_preview_maybe_finalize,
  // migration 20260624030000): the round finalizes when everyone present has
  // voted (≥1 real vote), server-side — so it fires even if the host's tab is
  // closed. The manual "End voting now" button below stays as a host override.

  const advance = useCallback(
    async (current: PriorVote[]) => {
      const p = nextPair(rateable, current, objective);
      if (p) {
        setPhase({ kind: "pair", pair: p });
        return;
      }
      // No pair to show: either they finished their pairs, OR the round has
      // fewer than 2 propositions total (with conditional self-inclusion, own
      // ideas join the pool when needed, so "can't form a pair" now only means
      // the board itself is short). Either way they're done with what they can
      // do — mark complete so the host's end-gate still works once the real
      // voters finish. But when they never had anything to vote on, show the
      // honest "invite others" empty-state, NOT a false "your votes are in".
      try {
        await markRatingComplete(round.id, me.id);
      } catch {
        /* idempotent */
      }
      setPhase(
        rateable.length < 2 ? { kind: "nothing_to_vote" } : { kind: "done" },
      );
      await onChanged();
    },
    [rateable, objective, round.id, me.id, onChanged],
  );

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const prior = await getPriorPairwiseVotes(round.id, me.id);
        if (!alive) return;
        setVotes(prior);
        await advance(prior);
      } catch (e) {
        if (!alive) return;
        setPhase({
          kind: "error",
          message: e instanceof Error ? e.message : t("vote.errLoad"),
        });
      }
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function vote(winnerId: number, loserId: number, isTie: boolean) {
    if (busy || phase.kind !== "pair") return;
    setBusy(true);
    try {
      await submitPairwiseComparison(round.id, me.id, winnerId, loserId, isTie);
      const next = [...votes, { winnerId, loserId, isTie, isSkip: false }];
      setVotes(next);
      await advance(next);
    } catch {
      setPhase({ kind: "error", message: t("vote.errVote") });
    } finally {
      setBusy(false);
      setPending(null);
    }
  }

  async function endVoting() {
    if (endingVote) return;
    setEndingVote(true);
    try {
      await hostEndVoting(data.chat.id);
      await onChanged();
    } catch {
      setPhase({ kind: "error", message: t("vote.errEnd") });
      setEndingVote(false);
    }
  }

  // Host can end once enough people are done AND at least one real vote exists —
  // the latter stops a 0-vote round (everyone only saw their own idea) from
  // being finalized into a meaningless winner.
  const canEnd = ratersDone >= NEED_RATERS && voteCount >= 1;

  // Host's gated "End voting now" (rating → result), shown in the done state.
  const hostEndFoot = (
    <div className="foot-bar">
      {isHost ? (
        <>
          <button
            className={`btn ${canEnd ? "ready" : "idle"}`}
            onClick={canEnd ? endVoting : undefined}
            disabled={!canEnd || endingVote}
            type="button"
          >
            {endingVote ? t("vote.tallying") : t("vote.endNow")} {canEnd && <Check />}
          </button>
          {/* The decision metric, coupled directly under the button. */}
          <div className="host-note">
            {voteCount < 1
              ? t("vote.noVotesYet")
              : ratersDone >= NEED_RATERS
                ? t("vote.doneCountReady", { n: ratersDone })
                : t("vote.doneCountNeed", { n: ratersDone, need: NEED_RATERS })}
          </div>
        </>
      ) : (
        <div className="wait-box">
          <div className="wait-note">{t("vote.waitHostEnds")}</div>
        </div>
      )}
    </div>
  );

  // Render one duel card. A plain render helper (not a nested component) so it
  // closes over vote/busy/roundNo without tripping react-hooks/static-components.
  const renderProp = (
    p: { id: number; content: string },
    other: { id: number; content: string },
  ) => {
    // Voting is blind: both options are shown neutrally — we never reveal which
    // is the carried "current answer" (no special card, label, or "keep it"),
    // so the vote isn't biased toward the incumbent.
    return (
      <button
        className="prop"
        onClick={() => {
          setPending(p.id);
          vote(p.id, other.id, false);
        }}
        disabled={busy}
        type="button"
      >
        <div className="text">{contentById.get(p.id) ?? p.content}</div>
        {pending === p.id && (
          <div className="pick">
            <span className="spin" /> {t("vote.recording")}
          </div>
        )}
      </button>
    );
  };

  return (
    <AppShell>
      <Rail right={<span className="rail-actions"><LangToggle />{isHost && <RailInvite code={code} />}{isGame ? <GameStatus data={data} presence={presence} /> : <PresenceBadge count={presence} />}</span>} />
      <ChatQuestion q={question} plain />

      {phase.kind === "loading" && (
        <div className="center-status">
          <div className="small">{t("common.loading")}</div>
        </div>
      )}

      {phase.kind === "error" && (
        <div className="center-status">
          <p className="err-text">{phase.message}</p>
        </div>
      )}

      {phase.kind === "pair" && (
        <>
          <div className="prompt">
            {t("vote.prompt", { round: roundNo })}
          </div>
          <div className="duel">
            {renderProp(phase.pair.top, phase.pair.bottom)}
            {renderProp(phase.pair.bottom, phase.pair.top)}
          </div>
          <button
            className="equal"
            onClick={() => {
              setPending("equal");
              vote(phase.pair.top.id, phase.pair.bottom.id, true);
            }}
            disabled={busy}
            type="button"
          >
            {pending === "equal" ? t("vote.recording") : t("vote.equal")}
          </button>
          <div style={{ marginTop: 8, textAlign: "center" }}>
            <button
              className="again"
              onClick={() => {
                setPending("skip");
                skip(phase.pair.top.id, phase.pair.bottom.id);
              }}
              disabled={busy}
              type="button"
            >
              {pending === "skip" ? t("vote.skipping") : t("vote.skipPair")}
            </button>
          </div>
        </>
      )}

      {phase.kind === "nothing_to_vote" && (
        <div className="result">
          <div className="center-status">
            <div className="big">{t("vote.nothingTitle")}</div>
            <div className="small">
              {t("vote.nothingBody")}
              {isHost ? t("vote.nothingHost") : t("vote.nothingGuest")}
            </div>
          </div>
          {/* The host can't vote here either, but still needs to end the round
              once the people who CAN vote have finished. */}
          {hostEndFoot}
        </div>
      )}

      {phase.kind === "done" && (
        <div className="result">
          <div className="center-status">
            <span className="seal" style={{ width: 20, height: 20 }} />
            <div className="big">{t("vote.doneTitle")}</div>
            <div className="small">
              {isHost ? t("vote.doneHost") : t("vote.doneGuest")}
            </div>
          </div>
          {hostEndFoot}
        </div>
      )}
    </AppShell>
  );

  async function skip(aId: number, bId: number) {
    if (busy || phase.kind !== "pair") return;
    setBusy(true);
    try {
      await submitPairwiseSkip(round.id, me.id, aId, bId);
      const next = [
        ...votes,
        { winnerId: aId, loserId: bId, isTie: false, isSkip: true },
      ];
      setVotes(next);
      await advance(next);
    } catch {
      setPhase({ kind: "error", message: t("vote.errSkip") });
    } finally {
      setBusy(false);
      setPending(null);
    }
  }
}
