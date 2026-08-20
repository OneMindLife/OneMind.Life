"use client";

import { useEffect, useState } from "react";
import { loadRoundHistory, type RoundHistoryEntry } from "@/lib/onemind/chat";
import { useI18n } from "@/lib/i18n";
import { AppShell, Rail, GroupPill, ChevR } from "../../components/ui";
import RoundRanking from "./RoundRanking";

type State =
  | { kind: "loading" }
  | { kind: "ready"; entries: RoundHistoryEntry[] }
  | { kind: "error"; message: string };

/// "How it converged" — the round-by-round timeline (oldest → newest), each
/// round's winning answer, with "See ranking ›" into that round's full results.
export default function History({
  chatId,
  question,
  onBack,
}: {
  chatId: number;
  question: string;
  onBack: () => void;
}) {
  const { t } = useI18n();
  const [state, setState] = useState<State>({ kind: "loading" });
  const [ranking, setRanking] = useState<RoundHistoryEntry | null>(null);

  useEffect(() => {
    let alive = true;
    loadRoundHistory(chatId)
      .then((entries) => alive && setState({ kind: "ready", entries }))
      .catch(
        (e) =>
          alive &&
          setState({
            kind: "error",
            message: e instanceof Error ? e.message : t("hist.errLoad"),
          }),
      );
    return () => {
      alive = false;
    };
  }, [chatId]);

  if (ranking) {
    const total = state.kind === "ready" ? state.entries.length : ranking.customId;
    return (
      <RoundRanking
        roundId={ranking.id}
        roundNumber={ranking.customId}
        question={question}
        voters={ranking.voters}
        locked={ranking.customId === total}
        onBack={() => setRanking(null)}
      />
    );
  }

  return (
    <AppShell>
      <Rail
        back={t("hist.result")}
        onBack={onBack}
        right={
          state.kind === "ready" ? (
            <GroupPill value={state.entries.length} label={t("hist.rounds")} />
          ) : undefined
        }
      />
      <div style={{ marginBottom: 18 }}>
        <div className="ask-eyebrow">{t("hist.title")}</div>
        <div
          className="q"
          style={{
            fontFamily: "var(--serif)",
            fontStyle: "italic",
            fontSize: 23,
            lineHeight: 1.14,
            color: "var(--ink-0)",
          }}
        >
          &ldquo;{question}&rdquo;
        </div>
      </div>

      {state.kind === "loading" && (
        <div className="center-status">
          <div className="small">{t("common.loading")}</div>
        </div>
      )}
      {state.kind === "error" && (
        <div className="center-status">
          <p className="err-text">{state.message}</p>
        </div>
      )}
      {state.kind === "ready" && (
        <div style={{ flex: 1, overflowY: "auto" }}>
          {state.entries.map((e, i) => {
            const wonAgain = i > 0 && e.winner === state.entries[i - 1].winner;
            return (
              <div className="tl-item" key={e.id}>
                <div className="node" />
                <div className="tl-head">
                  <span className="tl-round">{t("hist.round", { n: e.customId })}</span>
                  <span className="tl-status">{wonAgain ? t("hist.wonAgain") : t("hist.won")}</span>
                </div>
                <div className="tl-winner">{e.winner ?? t("hist.dash")}</div>
                <div
                  className="tl-meta"
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                  }}
                >
                  <span>
                    {e.voters > 0
                      ? t("hist.voted", { n: e.voters })
                      : e.keeps > 0
                        ? t("hist.keptIt", { n: e.keeps })
                        : t("hist.dash")}
                  </span>
                  {/* Only a voted round has a real ranking to drill into. */}
                  {e.voters > 0 && (
                    <button
                      className="back"
                      style={{ color: "var(--accent)" }}
                      onClick={() => setRanking(e)}
                      type="button"
                    >
                      {t("hist.seeRanking")} <ChevR />
                    </button>
                  )}
                </div>
              </div>
            );
          })}
          <div className="tl-item">
            <div className="node" />
            <div className="tl-conv">{t("hist.convergedNote")}</div>
          </div>
        </div>
      )}
    </AppShell>
  );
}
