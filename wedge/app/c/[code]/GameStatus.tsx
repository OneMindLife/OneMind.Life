"use client";

import { useState } from "react";
import { useI18n } from "@/lib/i18n";
import {
  loadCycleLeaderboard,
  type Bootstrap,
  type LeaderRow,
} from "@/lib/onemind/chat";
import PresenceBadge from "./PresenceBadge";

/// Game-mode rail cluster: a tappable presence badge (→ who's in the room) and a
/// standings button (→ the live leaderboard mid-game). Both open a lightweight
/// bottom sheet. The leaderboard reads the latest ANSWER cycle (topic rounds are
/// excluded server/client-side), so it shows the current game's standings.
export default function GameStatus({
  data,
  presence,
}: {
  data: Bootstrap;
  presence: number;
}) {
  const { t } = useI18n();
  const [panel, setPanel] = useState<null | "roster" | "standings">(null);
  const [board, setBoard] = useState<LeaderRow[]>([]);
  const [loading, setLoading] = useState(false);
  const myId = data.my_participant?.id;
  const players = (data.participants ?? []).filter((p) => p.status === "active");

  async function openStandings() {
    setPanel("standings");
    setLoading(true);
    try {
      setBoard(await loadCycleLeaderboard(data.chat.id));
    } catch {
      setBoard([]);
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <button
        className="gs-trophy"
        type="button"
        onClick={() => void openStandings()}
        aria-label={t("game.leaderboard")}
        title={t("game.leaderboard")}
      >
        <svg
          width="14"
          height="14"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2.2"
          strokeLinecap="round"
          aria-hidden="true"
        >
          <line x1="6" y1="20" x2="6" y2="11" />
          <line x1="12" y1="20" x2="12" y2="5" />
          <line x1="18" y1="20" x2="18" y2="14" />
        </svg>
      </button>
      <button
        className="gs-presence"
        type="button"
        onClick={() => setPanel("roster")}
        aria-label={t("game.whosHere")}
      >
        <PresenceBadge count={presence} />
      </button>

      {panel && (
        <div className="gs-overlay" onClick={() => setPanel(null)}>
          <div className="gs-sheet" onClick={(e) => e.stopPropagation()}>
            <div className="gs-head">
              {panel === "roster" ? t("game.whosHere") : t("game.leaderboard")}
              <button
                className="gs-close"
                type="button"
                onClick={() => setPanel(null)}
                aria-label={t("common.close")}
              >
                ✕
              </button>
            </div>

            {panel === "roster" ? (
              <div className="gs-roster">
                {players.map((p) => (
                  <div
                    key={p.id}
                    className={`gs-row${p.id === myId ? " me" : ""}`}
                  >
                    <span className="gs-name">
                      {p.id === myId ? t("game.you") : p.display_name}
                    </span>
                    {p.is_host && <span className="gs-host">{t("game.host")}</span>}
                  </div>
                ))}
              </div>
            ) : loading ? (
              <div className="gs-empty">…</div>
            ) : board.length === 0 ? (
              <div className="gs-empty">{t("game.noStandings")}</div>
            ) : (
              <div className="lb" style={{ margin: 0 }}>
                {board.map((r, i) => (
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
                    <div className="lb-score">{Math.round(r.avgRank)}</div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}
