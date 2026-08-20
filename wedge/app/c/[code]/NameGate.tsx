"use client";

import { useEffect, useState } from "react";
import { setMyName } from "@/lib/onemind/chat";
import { telegramName } from "@/lib/telegram";
import { useI18n } from "@/lib/i18n";
import { AppShell, Rail } from "../../components/ui";
import LangToggle from "../../components/LangToggle";

/// localStorage flag: has THIS user already named themselves in THIS chat?
/// Game mode forces a real name once (host and participant alike) so the
/// leaderboard and authorship reveal are meaningful. Decision mode never gates.
export function hasNamed(chatId: number): boolean {
  if (typeof window === "undefined") return true;
  try {
    return localStorage.getItem(`om_named_${chatId}`) === "1";
  } catch {
    return true;
  }
}

function markNamed(chatId: number) {
  try {
    localStorage.setItem(`om_named_${chatId}`, "1");
  } catch {
    /* private mode — the gate just shows again next load; harmless */
  }
}

/// The in-chat name gate. Same UX for host and participant: on first entry to a
/// game chat you pick a display name before anything else. onDone re-loads the
/// chat (the flag is now set, so the gate won't reappear).
export default function NameGate({
  chatId,
  onDone,
}: {
  chatId: number;
  onDone: () => void | Promise<void>;
}) {
  const { t } = useI18n();
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const join = async (raw: string) => {
    const clean = raw.trim().slice(0, 40);
    if (!clean || busy) return;
    setBusy(true);
    setErr(null);
    try {
      await setMyName(chatId, clean);
      markNamed(chatId);
      await onDone();
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Couldn't save your name.");
      setBusy(false);
    }
  };
  const submit = () => void join(name);

  // Telegram Mini App: prefill + auto-submit the player's Telegram name so the
  // name gate never appears inside Telegram — one less step in the group flow.
  useEffect(() => {
    const tgName = telegramName();
    if (tgName) {
      setName(tgName);
      void join(tgName);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <AppShell>
      <Rail right={<LangToggle />} />
      <div className="center-status">
        <div className="big">{t("game.namePrompt")}</div>
        <div className={`name-field${name.trim() ? "" : " beckon"}`}>
          <input
            className="name-input"
            type="text"
            value={name}
            maxLength={40}
            autoFocus
            placeholder={t("game.namePlaceholder")}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") void submit();
            }}
            aria-label={t("game.namePlaceholder")}
          />
        </div>
        {err && <p className="err-text">{err}</p>}
        <button
          className={`btn${name.trim() ? " ready" : " idle"}`}
          type="button"
          disabled={!name.trim() || busy}
          onClick={() => void submit()}
        >
          {busy ? <span className="spin" /> : t("game.nameCta")}
        </button>
      </div>
    </AppShell>
  );
}
