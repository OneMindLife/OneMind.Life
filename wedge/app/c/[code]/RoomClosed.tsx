"use client";

import { useEffect, useState } from "react";
import {
  countdown,
  roomTimeLabel,
  subscribeToRoomOpen,
  viewerTimeLabel,
  windowLength,
  type ScheduleState,
} from "@/lib/onemind/schedule";
import { enablePush, pushPermission } from "@/lib/onemind/push";
import { isTelegramContext, telegramWebApp } from "@/lib/telegram";
import { track } from "@/lib/onemind/analytics";
import { useI18n } from "@/lib/i18n";
import s from "./RoomClosed.module.css";

// Shown INSTEAD of the room when a scheduled chat is outside its window. Two
// deliberate properties (docs/RETENTION_EXPERIMENT.md):
//
//  * The visitor is NOT joined. ChatClient checks the schedule before
//    ensureParticipant, so drive-by arrivals outside the event no longer land a
//    participant row — the cohort we measure is the people who actually showed
//    up to the event, not everyone who ever touched the URL.
//  * The only action offered is "come back when it's open". Being summoned is
//    the mechanism the experiment is testing; this is where that opt-in lives
//    for people who arrive between events.

const TELEGRAM_CHANNEL = "https://t.me/onemind_life";

export default function RoomClosed({
  chatId,
  state,
  lastWinner,
  onOpen,
}: {
  chatId: number;
  state: ScheduleState;
  lastWinner: string | null;
  /// Called once the countdown reaches the opening boundary, so the parent can
  /// re-check with the server and swap in the live room without a reload.
  onOpen: () => void;
}) {
  const { t, lang } = useI18n();
  const [now, setNow] = useState(() => Date.now());
  const [notified, setNotified] = useState(false);
  const [notifyBusy, setNotifyBusy] = useState(false);

  // One-second tick for the countdown. When it crosses the boundary we hand off
  // to the parent rather than flipping ourselves open — the server stays the
  // authority on whether the room is really live. The already-granted check
  // rides along here rather than in an effect body: Notification.permission is
  // browser-only, so reading it during render or mount would diverge from the
  // statically exported HTML (same reason usePushOptIn reads it in a callback).
  useEffect(() => {
    const iv = setInterval(() => {
      const t = Date.now();
      setNow(t);
      setNotified((was) => was || pushPermission() === "granted");
      if (state.opensAt && t >= new Date(state.opensAt).getTime()) onOpen();
    }, 1000);
    return () => clearInterval(iv);
  }, [state.opensAt, onOpen]);

  const remainingRaw = countdown(now, state.opensAt);
  // countdown() returns the language-free "now" sentinel when the boundary has
  // just passed (shown for a beat before onOpen swaps the room in) — localize it.
  const remaining = remainingRaw === "now" ? t("room.now") : remainingRaw;
  const roomTime = roomTimeLabel(state.opensAt, state.timezone, lang);
  const viewerTime = viewerTimeLabel(state.opensAt);
  const len = windowLength(state.opensAt, state.closesAt);
  const lengthLabel = !len
    ? ""
    : len.kind === "mins"
      ? t("room.lenMinutes", { n: len.n })
      : len.kind === "hours"
        ? `${len.h}h`
        : `${len.h}h ${len.m}m`;

  async function notifyMe() {
    setNotifyBusy(true);
    track("room_closed_notify_tapped", {
      channel: isTelegramContext() ? "telegram" : "web_push",
    });
    try {
      // Inside Telegram the channel is the summon path (and web push is not
      // available in the Mini App webview); in a browser it's FCM.
      if (isTelegramContext()) {
        const app = telegramWebApp();
        if (app?.openTelegramLink) app.openTelegramLink(TELEGRAM_CHANNEL);
        else window.open(TELEGRAM_CHANNEL, "_blank", "noopener");
        setNotified(true);
      } else {
        const result = await enablePush();
        // The token alone reaches nobody — the summon fans out to
        // room_open_subscribers, so record the subscription too. Only after a
        // real grant: a denied prompt must not leave a promise on file.
        if (result === "granted") await subscribeToRoomOpen(chatId);
        setNotified(result === "granted");
      }
    } finally {
      setNotifyBusy(false);
    }
  }

  return (
    <div className={s.wrap}>
      <div className={s.brand}>OneMind</div>

      <h1 className={s.headline}>{t("room.closedTitle")}</h1>

      {state.opensAt && (
        <div className={s.countdown}>
          <div className={s.countdownValue}>{remaining}</div>
          <div className={s.countdownLabel}>{t("room.untilOpens")}</div>
        </div>
      )}

      <div className={s.schedule}>
        {roomTime && <div>{t("room.everyDayAt", { time: roomTime })}</div>}
        {viewerTime && (
          <div className={s.scheduleMuted}>
            {t("room.yourTime", { time: viewerTime })}
          </div>
        )}
        {lengthLabel && (
          <div className={s.scheduleMuted}>
            {t("room.openFor", { len: lengthLabel })}
          </div>
        )}
      </div>

      {notified ? (
        <div className={s.notifyDone}>
          {isTelegramContext()
            ? t("room.notifyDoneTg")
            : t("room.notifyDoneWeb")}
        </div>
      ) : (
        <button
          className={s.notify}
          onClick={notifyMe}
          disabled={notifyBusy}
          type="button"
        >
          {notifyBusy ? "…" : t("room.notifyMe")}
        </button>
      )}

      {lastWinner && (
        <div className={s.winner}>
          <div className={s.winnerLabel}>{t("room.lastWinningTake")}</div>
          <div className={s.winnerText}>{lastWinner}</div>
        </div>
      )}
    </div>
  );
}
