"use client";

import { useState } from "react";
import { generateOptions } from "@/lib/onemind/chat";
import { track } from "@/lib/onemind/analytics";
import { useI18n } from "@/lib/i18n";
import { AppShell, Rail, HostPill, ChatQuestion, PeopleIcon } from "../../components/ui";
import LangToggle from "../../components/LangToggle";

// The host's one-time gate on a freshly created quick chat (no cycle yet):
// "How should the ideas come in?" Leads with the group-proposes path (OneMind's
// real value) as the prominent default; the poll/options path is behind a
// deliberate tap. Mirrors the prototype's `seed` + `poll` screens.
export default function SeedDialog({
  question,
  busy,
  onGroup,
  onSeed,
}: {
  question: string;
  busy: boolean;
  onGroup: () => void;
  onSeed: (options: string[]) => void;
}) {
  const { t } = useI18n();
  const [showOptions, setShowOptions] = useState(false);
  // Show the minimum (2) by default — lighter on screen; the host taps "Add
  // option" for more.
  const [options, setOptions] = useState<string[]>(["", ""]);
  // AI-suggested options path: while the edge function runs, and whether the
  // current options came from AI (so the review header reads differently).
  const [aiBusy, setAiBusy] = useState(false);
  const [aiUsed, setAiUsed] = useState(false);

  const filled = options.map((o) => o.trim()).filter((o) => o.length > 0);
  const canSeed = filled.length >= 2 && !busy;

  // "Let AI suggest the options" — calls the generate-options edge function on
  // the chat's question, drops the result into the editable options view. The
  // host still reviews/edits, and the GROUP still votes — AI only seeds the
  // ballot. Falls back silently to the manual editor on any failure.
  async function useAI() {
    if (aiBusy || busy) return;
    setAiBusy(true);
    track("quick_create_options_ai", { source: "dialog" });
    try {
      const opts = await generateOptions(question);
      if (opts.length >= 2) {
        setOptions(opts.slice(0, 6));
        setAiUsed(true);
      } else {
        // Nothing came back — open the manual editor so they're not stuck.
        setAiUsed(false);
      }
    } catch {
      setAiUsed(false);
    } finally {
      setAiBusy(false);
      setShowOptions(true);
    }
  }

  return (
    <AppShell>
      <Rail
        right={
          <span className="rail-actions">
            <LangToggle />
            <HostPill label={t("common.host")} />
          </span>
        }
      />
      <ChatQuestion q={question} roomLabel={t("chat.newRoom")} />

      <div className="scrim">
        <div className="sheet">
          {!showOptions ? (
            <>
              <h3>{t("seed.title")}</h3>
              <div className="sub">{t("seed.sub")}</div>
              <button
                className="primary"
                onClick={onGroup}
                disabled={busy || aiBusy}
                type="button"
              >
                <PeopleIcon />
                {busy ? t("seed.starting") : t("seed.fromGroup")}
              </button>
              <button
                className="secondary"
                onClick={useAI}
                disabled={busy || aiBusy}
                type="button"
              >
                {aiBusy ? t("seed.aiThinking") : <u>{t("seed.ai")}</u>}
              </button>
              <button
                className="secondary"
                onClick={() => {
                  setAiUsed(false);
                  setShowOptions(true);
                }}
                disabled={busy || aiBusy}
                type="button"
              >
                <u>{t("seed.manual")}</u>
              </button>
            </>
          ) : (
            <>
              <h3>{aiUsed ? t("seed.reviewTitle") : t("seed.typeTitle")}</h3>
              <div className="sub">
                {aiUsed ? t("seed.reviewSub") : t("seed.typeSub")}
              </div>
              {options.map((opt, i) => (
                <div className="opt-row" key={i}>
                  <input
                    className="opt-input"
                    value={opt}
                    onChange={(e) => {
                      const next = [...options];
                      next[i] = e.target.value;
                      setOptions(next);
                    }}
                    placeholder={t("seed.option", { n: i + 1 })}
                  />
                </div>
              ))}
              <div className="opt-tools">
                <button
                  className="tool"
                  onClick={() => setOptions([...options, ""])}
                  disabled={busy}
                  type="button"
                >
                  {t("seed.addOption")}
                </button>
              </div>
              <div className="actions-row">
                <button
                  className="ghost"
                  onClick={() => setShowOptions(false)}
                  disabled={busy}
                  type="button"
                >
                  {t("seed.getIdeasInstead")}
                </button>
                <button
                  className="start-voting"
                  onClick={() => onSeed(filled)}
                  disabled={!canSeed}
                  type="button"
                  style={canSeed ? undefined : { opacity: 0.5 }}
                >
                  {busy ? t("seed.starting") : t("seed.startVoting")}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </AppShell>
  );
}
