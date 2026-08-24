"use client";

import { useState } from "react";
import {
  submitProposition,
  advanceToRating,
  hostEndVoting,
  affirmRound,
  loadRoundHistory,
  chatQuestion,
  propContent,
  DuplicatePropositionError,
  type Bootstrap,
  type RoundHistoryEntry,
} from "@/lib/onemind/chat";
import { track } from "@/lib/onemind/analytics";
import { useI18n } from "@/lib/i18n";
import {
  AppShell,
  Rail,
  ChatQuestion,
  Arrow,
  Check,
} from "../../components/ui";
import RoundRanking from "./RoundRanking";
import PresenceBadge from "./PresenceBadge";
import GameStatus from "./GameStatus";
import RailInvite from "../../components/RailInvite";
import LangToggle from "../../components/LangToggle";

type Step = "gate" | "write" | "list";

const NEED_RESPONSES = 2;

/// Round 2+ proposing — the convergence on-ramp. The round-1 winner is carried
/// forward as the "current leader"; the group can challenge it. If it wins
/// again it locks in (converges). Three sub-steps:
///   gate  — leader + "Can you think of something better?" (Yes → write, No → list)
///   write — type a challenger
///   list  — challengers so far + host advance to ranking
export default function LeaderChallenge({
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
  const question = chatQuestion(data.chat);
  const roundNo = (round.custom_id as number) || 2;

  const allProps = data.propositions ?? [];
  const carried = allProps.find((p) => p.carried_from_id);
  const leader = carried ? propContent(carried) : (allProps[0] ? propContent(allProps[0]) : t("lc.theCurrentAnswer"));
  const challengers = allProps.filter((p) => !p.carried_from_id);
  const myChallenger = (data.my_propositions ?? []).find((p) => !p.carried_from_id);
  const hasChallenged = !!myChallenger;
  // A "response" = any act of participating this round: a challenge OR a
  // no-challenge ("this is the one", recorded as an affirmation).
  const affirmCount = data.affirmation_count ?? 0;
  const responses = challengers.length + affirmCount;
  // Everyone currently in the chat — auto-advance fires once they've all
  // responded (challenged or kept the leader).
  const activeCount = (data.participants ?? []).filter(
    (p) => p.status === "active",
  ).length;

  // Start on the list if I've already challenged (or chosen to keep); otherwise
  // the gate. Hosts who've decided still see the advance control on the list.
  const [step, setStep] = useState<Step>(hasChallenged ? "list" : "gate");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // "See ranking" on the leader card → the previous (leading) round's results.
  const [prevRanking, setPrevRanking] = useState<RoundHistoryEntry | null>(null);

  async function seePrevRanking() {
    if (busy) return;
    setBusy(true);
    try {
      const hist = await loadRoundHistory(data.chat.id);
      const prev = hist.find((h) => h.customId === roundNo - 1);
      if (prev) setPrevRanking(prev);
    } catch {
      /* ignore — the link just won't open */
    } finally {
      setBusy(false);
    }
  }

  if (prevRanking) {
    return (
      <RoundRanking
        roundId={prevRanking.id}
        roundNumber={prevRanking.customId}
        question={question}
        voters={prevRanking.voters}
        locked={false}
        onBack={() => setPrevRanking(null)}
      />
    );
  }

  async function submitChallenger() {
    const content = text.trim();
    if (!content || busy) return;
    setBusy(true);
    setErr(null);
    try {
      await submitProposition(round.id, me.id, content);
      track("proposition_submitted", {
        chat_id: String(data.chat.id),
        round_number: roundNo,
        content_length: content.length,
      });
      setText("");
      await onChanged();
      setStep("list");
    } catch (e) {
      setErr(
        e instanceof DuplicatePropositionError
          ? t("lc.errDuplicate")
          : t("lc.errSubmit"),
      );
    } finally {
      setBusy(false);
    }
  }

  // "No, this is the one" — record a no-challenge as a real, counted response
  // (an affirmation), so the host sees engagement instead of a misleading 0.
  // In a quick room this never auto-resolves (host-controlled); it just counts.
  async function keepLeader() {
    if (busy) return;
    setBusy(true);
    setErr(null);
    try {
      await affirmRound(round.id);
      await onChanged();
      setStep("list");
    } catch {
      setErr(t("lc.errRecord"));
    } finally {
      setBusy(false);
    }
  }

  // Host advances the round. Same "Start voting" action as round 1, gated on
  // responses (≥2). If NOBODY challenged (every response was an affirmation),
  // there's nothing to vote on — advance then immediately end voting so it
  // skips straight to the result (one tap).
  const canAdvance = responses >= NEED_RESPONSES;
  async function startVoting() {
    if (busy || !canAdvance) return;
    setBusy(true);
    setErr(null);
    try {
      await advanceToRating(round.id);
      if (challengers.length === 0) {
        await hostEndVoting(data.chat.id); // all affirmed → skip voting, lock in
      }
      await onChanged();
    } catch {
      setErr(t("lc.errAdvance"));
      setBusy(false);
    }
  }

  // R2+ proposing auto-advance is now a BACKEND trigger
  // (maybe_auto_advance_quick_proposing, migration 20260624030000): once everyone
  // present has responded it converges (no challenger) or opens rating, server-
  // side — so it fires even if the host's tab is closed. The manual "Start voting"
  // button stays as a host override. (R1 stays host-paced either way.)

  const hostFoot = isHost ? (
    <div className="foot-bar">
      <button
        className={`btn ${canAdvance ? "ready" : "idle"}`}
        onClick={canAdvance ? startVoting : undefined}
        disabled={!canAdvance || busy}
        type="button"
      >
        {busy ? t("lc.working") : t("lc.startVoting")} {canAdvance && <Check />}
      </button>
      {/* Decision metric coupled under the button — total responses. */}
      <div className="host-note">
        {canAdvance
          ? challengers.length === 0
            ? t("lc.lockNote", { n: responses })
            : t("lc.readyNote", { n: responses })
          : t("lc.needNote", { n: responses, need: NEED_RESPONSES })}
      </div>
    </div>
  ) : (
    <div className="foot-bar">
      <div className="wait-box">
        <div className="wait-note">{t("lc.waitHost")}</div>
      </div>
    </div>
  );

  // ── gate ──
  if (step === "gate") {
    return (
      <AppShell>
        <Rail right={<span className="rail-actions"><LangToggle />{isHost && <RailInvite code={code} />}{isGame ? <GameStatus data={data} presence={presence} /> : <PresenceBadge count={presence} />}</span>} />
        <ChatQuestion q={question} plain />
        <div className="result gate">
          <div className="leader">
            <div className="ll">
              <span className="seal" />
              {t("lc.roundResult", { round: roundNo - 1 })}
            </div>
            <div className="la">{leader}</div>
            <div className="lmeta" style={{ justifyContent: "center" }}>
              <button
                className="see"
                onClick={seePrevRanking}
                disabled={busy}
                type="button"
              >
                {t("lc.seeRanking")}
              </button>
            </div>
          </div>
          <div className="challenge-q">{t("lc.keepOrReplace")}</div>
          <div className="yesno">
            <button
              className="yes beckon-w"
              onClick={keepLeader}
              disabled={busy}
              type="button"
            >
              {busy ? (
                <>
                  <span className="spin" /> {t("lc.keeping")}
                </>
              ) : (
                t("lc.keepIt")
              )}
            </button>
            <button
              className="no beckon-w"
              onClick={() => setStep("write")}
              disabled={busy}
              type="button"
            >
              {t("lc.replaceIt")} <Arrow />
            </button>
          </div>
          <div className="cnote">{t("lc.cnote")}</div>
        </div>
        {isHost && hostFoot}
      </AppShell>
    );
  }

  // ── write ──
  if (step === "write") {
    return (
      <AppShell>
        <Rail back={t("common.back")} onBack={() => setStep("gate")} />
        <ChatQuestion q={question} />
        <div className="phase-tag">
          <span className="live" />
          {t("lc.replaceTag", { round: roundNo })}
        </div>
        <div className="standing-answer">
          <div className="sa-label">
            <span className="seal" />
            {t("lc.replacing")}
          </div>
          <div className="sa-text">{leader}</div>
        </div>
        <div className="ranked-head" style={{ marginTop: 20 }}>
          {t("lc.yourAlt")}
        </div>
        <div className="propose" style={{ marginTop: 10 }}>
          <div className={`field${text.trim() ? "" : " beckon"}`}>
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder={t("lc.altPlaceholder")}
              rows={2}
              maxLength={600}
              autoFocus
            />
          </div>
          <div className="submit-row">
            <div className="count">{text.length} / 600</div>
            <button
              className={`submit${text.trim() ? " beckon-w" : ""}`}
              onClick={submitChallenger}
              disabled={busy || text.trim().length === 0}
              type="button"
            >
              {busy ? t("lc.submitting") : t("lc.submitAlt")} <Arrow />
            </button>
          </div>
          <div className="idea-note" style={{ marginTop: 11 }}>
            {t("lc.anonNote")}
          </div>
        </div>
        {err && <p className="err-text" style={{ marginTop: 10 }}>{err}</p>}
        <button
          className="keep-instead"
          onClick={keepLeader}
          disabled={busy}
          type="button"
        >
          {busy ? (
            <>
              <span className="spin" /> {t("lc.keeping")}
            </>
          ) : (
            <>{t("lc.keepInstead")}</>
          )}
        </button>
      </AppShell>
    );
  }

  // ── list (affirm) ──
  return (
    <AppShell pinned>
      <Rail right={<span className="rail-actions"><LangToggle />{isHost && <RailInvite code={code} />}{isGame ? <GameStatus data={data} presence={presence} /> : <PresenceBadge count={presence} />}</span>} />
      <ChatQuestion q={question} plain />
      <div className="result">
        <div className="standing-answer">
          <div className="sa-label">
            <span className="seal" />
            {hasChallenged ? t("lc.currentBeingReplaced") : t("lc.currentKeeping")}
          </div>
          <div className="sa-text">{leader}</div>
        </div>
        {hasChallenged && (
          <div
            style={{
              fontFamily: "var(--mono)",
              fontSize: 9,
              letterSpacing: "0.14em",
              textTransform: "uppercase",
              color: "var(--accent)",
              marginTop: 12,
            }}
          >
            {isHost ? t("lc.yourAltInHost") : t("lc.yourAltInGuest")}
          </div>
        )}
        <div className="ranked-head" style={{ marginTop: 18 }}>
          {t("lc.altsThisRound", { n: challengers.length })}
        </div>
        <div className="chall-list">
          {challengers.length === 0 ? (
            <div style={{ fontSize: 13, color: "var(--ink-3)" }}>
              {t("lc.noAltsYet")}
            </div>
          ) : (
            challengers.map((c) => {
              const mine = myChallenger && c.id === myChallenger.id;
              return (
                <div key={c.id} className={`chall-row${mine ? " mine" : ""}`}>
                  {propContent(c)}
                  {mine && <span className="you">{t("lc.you")}</span>}
                </div>
              );
            })
          )}
        </div>
        {/* Reconciles the responses count: responses = challengers + kept. */}
        {affirmCount > 0 && (
          <div className="idea-note" style={{ marginTop: 10 }}>
            {t("lc.keptCount", { n: affirmCount })}
          </div>
        )}
        <div className="idea-note">
          {challengers.length === 0 ? t("lc.noAltsNote") : t("lc.altsNote")}
        </div>
        {err && <p className="err-text" style={{ marginTop: 10 }}>{err}</p>}
      </div>
      {hostFoot}
    </AppShell>
  );
}
