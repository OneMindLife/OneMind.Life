"use client";

import { useEffect, useState } from "react";
import {
  loadRanking,
  loadRoundHistory,
  loadCycleLeaderboard,
  startTopicRound,
  getResultMeta,
  chatQuestion,
  type Bootstrap,
  type RankedProp,
  type LeaderRow,
} from "@/lib/onemind/chat";
import { track } from "@/lib/onemind/analytics";
import { getMode } from "@/lib/onemind/mode";
import { useI18n } from "@/lib/i18n";
import { AppShell, Rail, GroupPill } from "../../components/ui";
import LangToggle from "../../components/LangToggle";
import History from "./History";

type Meta = { rounds: number; people: number; comparisons: number };
type State =
  | { kind: "loading" }
  | {
      kind: "ready";
      ranked: RankedProp[];
      meta: Meta;
      unchallenged: boolean;
      leaderboard: LeaderRow[];
    }
  | { kind: "error"; message: string };

/// Ended state. Decision mode: the group's converged decision (winner + idea
/// ranking + "start another"). Game mode: the same converged answer, PLUS the
/// per-game player leaderboard, authorship revealed on each idea, and a host
/// "play again" that reopens the SAME room with a new question.
export default function Results({
  data,
  onReload,
}: {
  data: Bootstrap;
  onReload?: () => void | Promise<void>;
}) {
  const { t, lang } = useI18n();
  const [state, setState] = useState<State>({ kind: "loading" });
  const [showHistory, setShowHistory] = useState(false);
  const [fun, setFun] = useState(false); // H-FUN A/B (set after mount)
  useEffect(() => setFun(getMode() === "fun"), []);
  const question = chatQuestion(data.chat);

  const isGame = data.chat.mode === "game";
  const isHost = !!data.my_participant?.is_host;
  const myId = data.my_participant?.id ?? null;

  // Authorship: participant id → display name (game mode reveals it on results).
  const nameFor = (pid: number | null): string | null => {
    if (pid == null) return null;
    const p = data.participants.find((x) => x.id === pid);
    return p ? p.display_name : null;
  };

  // Play-again (game host).
  const [starting, setStarting] = useState(false);
  const [startErr, setStartErr] = useState<string | null>(null);
  // "Next game" opens a TOPIC vote: the group proposes + picks the next topic,
  // then the answer game runs on it. Host paces *when*; the group picks *what*.
  const nextGame = async () => {
    if (starting) return;
    setStarting(true);
    setStartErr(null);
    try {
      await startTopicRound(data.chat.id, t("game.topicPrompt"));
      track("quick_chat_create_another", {
        from_chat_id: data.chat.id,
        mode: "game",
      });
      if (onReload) await onReload();
      else window.location.reload();
    } catch (e) {
      setStartErr(e instanceof Error ? e.message : "Couldn't start the game.");
      setStarting(false);
    }
  };

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [meta, hist, leaderboard] = await Promise.all([
          getResultMeta(data.chat.id),
          loadRoundHistory(data.chat.id),
          isGame ? loadCycleLeaderboard(data.chat.id) : Promise.resolve([]),
        ]);
        if (!alive) return;
        const latest = hist[hist.length - 1];
        let ranked = latest ? await loadRanking(latest.id, lang) : [];
        // If the final round was unchallenged (just the carried leader), its
        // ranking is a list of 1 — fall back to the previous round's ranking
        // (the actual contest) so "Full ranking" stays meaningful.
        let unchallenged = false;
        if (ranked.length < 2 && hist.length >= 2) {
          unchallenged = true;
          ranked = await loadRanking(hist[hist.length - 2].id, lang);
        }
        if (!alive) return;
        setState({ kind: "ready", ranked, meta, unchallenged, leaderboard });
      } catch (e) {
        if (!alive) return;
        setState({
          kind: "error",
          message: e instanceof Error ? e.message : "Couldn't load results.",
        });
      }
    })();
    return () => {
      alive = false;
    };
  }, [data.chat.id, lang, isGame]);

  if (showHistory) {
    return (
      <History
        chatId={data.chat.id}
        question={question}
        onBack={() => setShowHistory(false)}
      />
    );
  }

  if (state.kind !== "ready") {
    return (
      <AppShell>
        <Rail right={<LangToggle />} />
        <div className="center-status">
          {state.kind === "loading" ? (
            <div className="small">{t("res.tallying")}</div>
          ) : (
            <p className="err-text">{state.message}</p>
          )}
        </div>
      </AppShell>
    );
  }

  const { ranked, meta, unchallenged, leaderboard } = state;
  const ppl = meta.people;

  return (
    <AppShell>
      <Rail
        right={
          <span className="rail-actions">
            <LangToggle />
            <GroupPill value={ppl} label={isGame ? t("game.votedPill") : t("res.decided")} />
          </span>
        }
      />
      <div className="chat-q plain">
        <div className="room-label">
          {isGame
            ? t("game.resultEyebrow", { ppl, cmp: meta.comparisons })
            : t("res.converged", { ppl, cmp: meta.comparisons })}
        </div>
        <div
          className="q"
          style={{
            fontStyle: "normal",
            fontFamily: "var(--sans)",
            fontWeight: 300,
            fontSize: 16,
            color: "var(--ink-1)",
          }}
        >
          {question}
        </div>
      </div>

      <div className="result">
        {ranked.length > 0 && (
          <div className="converged">
            <div className="cl">
              <span className="seal" />
              {isGame ? t("game.pickLabel") : t("res.lockedIn")}
            </div>
            <div className="ca">{ranked[0].content}</div>
            {isGame && nameFor(ranked[0].participantId) && (
              <div className="ca-by">
                {t("game.by", { name: nameFor(ranked[0].participantId) as string })}
              </div>
            )}
          </div>
        )}

        {/* How the group got here — right under the winner, above the standings,
            so the convergence story reads before the leaderboard. Decision mode
            only: a game is a single instant round, so there's no multi-round
            convergence story to tell (and meta.rounds is 1 anyway). */}
        {!isGame && meta.rounds > 1 && (
          <button
            className="convlink"
            onClick={() => setShowHistory(true)}
            type="button"
          >
            {t("res.howConverged", { n: meta.rounds })} <span>›</span>
          </button>
        )}

        {/* Game mode: the per-game player leaderboard — the competitive payoff. */}
        {isGame && leaderboard.length > 0 && (
          <div className="lb">
            <div className="lb-head">{t("game.leaderboard")}</div>
            {leaderboard.map((r, i) => (
              <div
                key={r.participantId}
                className={`lb-row ${i === 0 ? "top" : ""} ${
                  r.participantId === myId ? "me" : ""
                }`}
              >
                <div className="lb-rk">{i + 1}</div>
                <div className="lb-name">
                  {r.participantId === myId ? t("game.you") : r.name}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Decision mode shows the ranked ideas. Game mode shows the PLAYER
            leaderboard instead (above) — the players are the payoff, not a list
            of ideas; the winning idea + its author is already spotlighted. */}
        {!isGame && (
          <>
            <div className="ranked-head" style={{ marginBottom: 4 }}>
              {t("res.fullRanking")}
            </div>
            <div className="rank-list">
              {ranked.map((p, i) => (
                <div key={p.id} className={`rank-row ${i === 0 ? "lead" : ""}`}>
                  <div className="rk">{i + 1}</div>
                  <div>
                    <div className="rt">{p.content}</div>
                  </div>
                </div>
              ))}
              {ranked.length === 0 && (
                <p className="small" style={{ padding: "20px 0", textAlign: "center" }}>
                  {t("res.noneRanked")}
                </p>
              )}
            </div>
          </>
        )}

        {isGame ? (
          // "Next game" (host only) opens a TOPIC vote — the group proposes and
          // picks the next topic, then the answer game runs on it. Non-hosts wait
          // on the result/leaderboard until the host moves on.
          isHost ? (
            <div className="newgame">
              <div className="newgame-note">{t("game.nextGameNote")}</div>
              {startErr && <p className="err-text">{startErr}</p>}
              <button
                className="btn"
                type="button"
                disabled={starting}
                onClick={() => void nextGame()}
              >
                {starting ? <span className="spin" /> : t("game.nextGame")}
              </button>
            </div>
          ) : null
        ) : (
          <div className="actions">
            {/* The retention/loop signal (D19/D22): a host coming back for a
                SECOND decision after finishing one. Fires before navigating. */}
            <a
              href="/create"
              className="btn"
              onClick={() =>
                track("quick_chat_create_another", { from_chat_id: data.chat.id })
              }
            >
              {fun ? t("res.playAgain") : t("res.startAnother")}
            </a>
          </div>
        )}
      </div>
    </AppShell>
  );
}
