"use client";

import { useState } from "react";
import {
  submitProposition,
  advanceToRating,
  chatQuestion,
  propContent,
  DuplicatePropositionError,
  type Bootstrap,
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
import PresenceBadge from "./PresenceBadge";
import GameStatus from "./GameStatus";
import InviteBlock from "./InviteBlock";
import RailInvite from "../../components/RailInvite";
import LangToggle from "../../components/LangToggle";

const NEED_IDEAS = 2;

/// Proposing phase: everyone adds one idea, then the host opens ranking.
/// Others' ideas stay blurred until you've added yours — so nobody can copy
/// before they commit. Anonymous throughout (no author names).
export default function Proposing({
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
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const round = data.current_round!;
  const me = data.my_participant!;
  const isHost = me.is_host;
  const isGame = data.chat.mode === "game";
  const mine = data.my_propositions ?? [];
  const hasSubmitted = mine.length > 0;
  const allProps = data.propositions ?? [];
  // After submitting, show the voter's own idea at the TOP of the list (so they
  // see it among the submissions — no separate "your idea is in" card needed).
  const orderedProps = [
    ...allProps.filter((p) => p.participant_id === me.id),
    ...allProps.filter((p) => p.participant_id !== me.id),
  ];
  const newCount = allProps.filter((p) => !p.carried_from_id).length;
  const ideaCount = allProps.length;
  const canRank = newCount >= NEED_IDEAS;
  const question = chatQuestion(data.chat);

  async function add() {
    const content = text.trim();
    if (!content || busy) return;
    setBusy(true);
    setErr(null);
    try {
      await submitProposition(round.id, me.id, content);
      track("proposition_submitted", {
        chat_id: String(data.chat.id),
        round_number: (round.custom_id as number) || 1,
        content_length: content.length,
      });
      setText("");
      await onChanged();
    } catch (e) {
      setErr(
        e instanceof DuplicatePropositionError
          ? t("prop.errDuplicate")
          : t("prop.errAdd"),
      );
    } finally {
      setBusy(false);
    }
  }

  async function startRanking() {
    if (busy) return;
    setBusy(true);
    setErr(null);
    try {
      await advanceToRating(round.id);
      await onChanged();
    } catch {
      setErr(t("prop.errStartVoting"));
      setBusy(false);
    }
  }

  return (
    <AppShell pinned>
      <Rail right={<span className="rail-actions"><LangToggle />{isHost && <RailInvite code={code} />}{isGame ? <GameStatus data={data} presence={presence} /> : <PresenceBadge count={presence} />}</span>} />
      <ChatQuestion q={question} />

      {!hasSubmitted && (
        <div className="phase-tag">
          <span className="live" />
          {isHost ? t("prop.tagHost") : t("prop.tagGuest")}
        </div>
      )}

      {!hasSubmitted && (
        <div className="propose">
          <div className={`field${text.trim() ? "" : " beckon"}`}>
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder={t("prop.placeholder")}
              rows={2}
              disabled={busy}
              maxLength={300}
            />
          </div>
          <div className="submit-row">
            <div className="count">{text.length} / 300</div>
            <button
              className={`submit${text.trim() ? " beckon-w" : ""}`}
              onClick={add}
              disabled={busy || text.trim().length === 0}
              type="button"
            >
              {busy ? t("prop.adding") : t("prop.addIdea")} <Arrow />
            </button>
          </div>
        </div>
      )}

      {err && <p className="err-text" style={{ marginTop: 10 }}>{err}</p>}

      {ideaCount > 0 && (
        <div className="ticker">
          <div className="head">
            <span>{t("prop.responses", { n: ideaCount })}</span>
          </div>
          <div className="locked-list">
            {orderedProps.map((p) => (
              <div
                key={p.id}
                className={`peek ${hasSubmitted ? "revealed" : "masked"}${
                  p.participant_id === me.id ? " mine" : ""
                }`}
              >
                {propContent(p)}
                {p.participant_id === me.id && (
                  <span className="you-tag">{t("prop.you")}</span>
                )}
              </div>
            ))}
          </div>
          {!hasSubmitted && (
            <div className="ticker-note">{t("prop.hiddenNote")}</div>
          )}
        </div>
      )}

      <HostAdvance
        isHost={isHost}
        code={code}
        ok={canRank}
        ideaCount={newCount}
        busy={busy}
        onAdvance={startRanking}
        t={t}
      />
    </AppShell>
  );
}

/// Gated host control (proposing → rating). Participants see a passive note.
function HostAdvance({
  isHost,
  code,
  ok,
  ideaCount,
  busy,
  onAdvance,
  t,
}: {
  isHost: boolean;
  code: string;
  ok: boolean;
  ideaCount: number;
  busy: boolean;
  onAdvance: () => void;
  t: (key: string, params?: Record<string, string | number>) => string;
}) {
  if (!isHost) {
    return (
      <div className="foot-bar">
        <div className="wait-box">
          <div className="wait-note">{t("prop.waitHost")}</div>
        </div>
      </div>
    );
  }
  return (
    <div className="foot-bar">
      {/* Solo-stall fix: invite sits directly above the advance button —
          inside the bottom bar so it's pinned right there, not floating up in
          the content. */}
      <InviteBlock code={code} />
      <button
        className={`btn ${ok ? "ready" : "idle"}`}
        onClick={ok ? onAdvance : undefined}
        disabled={!ok || busy}
        type="button"
      >
        {busy ? t("prop.starting") : t("prop.startVoting")} {ok && <Check />}
      </button>
      {/* The decision metric, coupled directly under the button. */}
      <div className="host-note">
        {ok
          ? t("prop.readyNote", { n: ideaCount })
          : t("prop.needNote", { n: ideaCount, need: NEED_IDEAS })}
      </div>
    </div>
  );
}
