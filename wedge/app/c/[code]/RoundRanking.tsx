"use client";

import { useEffect, useState } from "react";
import { loadRanking, type RankedProp } from "@/lib/onemind/chat";
import { useI18n } from "@/lib/i18n";
import { AppShell, Rail, GroupPill } from "../../components/ui";

type State =
  | { kind: "loading" }
  | { kind: "ready"; ranked: RankedProp[] }
  | { kind: "error"; message: string };

/// A single completed round's full ranking (winner + everything it beat).
/// Opened from "See ranking ›" on the leader card and the history timeline.
export default function RoundRanking({
  roundId,
  roundNumber,
  question,
  voters,
  locked,
  onBack,
}: {
  roundId: number;
  roundNumber: number;
  question: string;
  voters: number;
  /// True when this round is the one that locked the answer in (converged).
  locked?: boolean;
  onBack: () => void;
}) {
  const { t, lang } = useI18n();
  const [state, setState] = useState<State>({ kind: "loading" });

  useEffect(() => {
    let alive = true;
    loadRanking(roundId, lang)
      .then((ranked) => alive && setState({ kind: "ready", ranked }))
      .catch(
        (e) =>
          alive &&
          setState({
            kind: "error",
            message: e instanceof Error ? e.message : t("rr.errLoad"),
          }),
      );
    return () => {
      alive = false;
    };
  }, [roundId, lang, t]);

  return (
    <AppShell>
      <Rail
        back={t("common.back")}
        onBack={onBack}
        right={<GroupPill value={voters} label={voters === 1 ? t("rr.voter") : t("rr.voters")} />}
      />
      <div className="chat-q plain">
        <div className="q" style={{ fontSize: 16 }}>
          &ldquo;{question}&rdquo;
        </div>
      </div>
      <div className="round-chip">
        {t("rr.rankingChip", { n: roundNumber, locked: locked ? 1 : 0 })}
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
        <>
          <div
            className="ranked-head"
            style={{ margin: "-6px 0 12px 2px", color: "var(--ink-3)" }}
          >
            {t("rr.decidedBy", { n: voters })}
          </div>
          <div className="rank-list">
            {state.ranked.map((p, i) => (
              <div key={p.id} className={`rank-row ${i === 0 ? "lead" : ""}`}>
                <div className="rk">{i + 1}</div>
                <div>
                  {i === 0 && (
                    <div className="sa-label" style={{ marginBottom: 6 }}>
                      <span className="seal" />
                      {locked ? t("rr.lockedIn") : t("rr.leadsSoFar")}
                    </div>
                  )}
                  <div className="rt">{p.content}</div>
                </div>
              </div>
            ))}
            {state.ranked.length === 0 && (
              <p
                className="small"
                style={{ padding: "20px 0", textAlign: "center" }}
              >
                {t("rr.nothingRanked")}
              </p>
            )}
          </div>
        </>
      )}
    </AppShell>
  );
}
