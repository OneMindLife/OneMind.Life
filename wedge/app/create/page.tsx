"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createQuickChat } from "@/lib/onemind/createChat";
import { startGroupChat } from "@/lib/onemind/chat";
import { FUN_SEEDS } from "@/lib/onemind/mode";
import { track } from "@/lib/onemind/analytics";
import { useI18n } from "@/lib/i18n";
import { AppShell, Rail, Arrow } from "../components/ui";
import LangToggle from "../components/LangToggle";

export default function CreatePage() {
  const { t } = useI18n();
  const router = useRouter();
  // The question lives in the UNCONTROLLED textarea (read via ref), not React
  // state. This is deliberate: the field is autoFocused, so on a slow connection
  // a user can type BEFORE the JS bundle hydrates. A controlled `value={...}`
  // would discard that pre-hydration text (onChange never fired) and leave the
  // button stuck disabled even though the field shows text. An uncontrolled
  // input keeps whatever the user typed; `hasText` just mirrors it for the
  // button's enabled state and is re-synced on mount to catch pre-hydration input.
  const taRef = useRef<HTMLTextAreaElement>(null);
  const [hasText, setHasText] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isGame, setIsGame] = useState(false);

  function fillQuestion(q: string) {
    if (!taRef.current) return;
    taRef.current.value = q;
    syncHasText();
    taRef.current.focus();
  }

  const canCreate = hasText && !loading;

  function syncHasText() {
    setHasText((taRef.current?.value.trim().length ?? 0) > 0);
  }

  // Quick-create funnel entry point (matches the live app's event).
  useEffect(() => {
    track("quick_create_opened", {});
  }, []);

  // After mount: prefill from a landing-page seed chip (/create?q=…) WITHOUT
  // clobbering anything the user already typed pre-hydration, then sync the
  // button state from whatever the field actually contains.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const q = params.get("q");
    // A seed (?q=…) is an explicit intent to use that question, so it overrides
    // the default below. Without a seed, the default "What should we do next?"
    // stays (and the user can edit it).
    if (taRef.current && q) taRef.current.value = q;
    setIsGame(params.get("game") === "1");
    syncHasText();
  }, []);

  async function handleCreate() {
    const question = taRef.current?.value.trim() ?? "";
    if (!question || loading) return;
    setLoading(true);
    setError(null);
    try {
      // Game mode is opted into via /create?game=1 — the social "best ideas win"
      // mode (persistent room, leaderboard, authorship, play-again). Default is
      // the serious decision quick chat.
      const isGame =
        new URLSearchParams(window.location.search).get("game") === "1";
      const { code, id } = await createQuickChat(question, {
        mode: isGame ? "game" : "decision",
      });
      // Game mode never shows the seed-choice dialog — it always gathers ideas
      // from the group. Start the proposing round now so the host lands straight
      // in the game (no dialog, no waiting spinner).
      if (isGame) await startGroupChat(id);
      // Convergence quick chat created. fork='group' (the wedge always gathers
      // ideas from the group, then the host can seed options at the gate);
      // mode='real' (every wedge chat is shareable, no solo preview).
      // chat_id lets PostHog/GA join an event to its chats row — so real-vs-
      // internal can be labeled per chat (e.g. filtering dev/test chats).
      track("quick_create_chat_created", {
        fork: "group",
        mode: "real",
        game: isGame,
        source: "start",
        chat_id: id,
      });
      router.push(`/c/${code}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("common.tryAgain"));
      setLoading(false);
    }
  }

  return (
    <AppShell>
      <Rail
        back={t("common.back")}
        onBack={() => router.push("/")}
        right={<LangToggle />}
      />
      <div className="center">
        <div>
          <div className="ask-eyebrow">{t(isGame ? "game.createEyebrow" : "create.eyebrow")}</div>
          <div className="ask-q">{t(isGame ? "game.createQ" : "create.q")}</div>
          <div className="ask-help">{t(isGame ? "game.createHelp" : "create.help")}</div>
        </div>
        <div className={`ask${hasText ? "" : " beckon"}`}>
          <textarea
            ref={taRef}
            autoFocus
            defaultValue="What should we do next?"
            onChange={syncHasText}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) handleCreate();
            }}
            placeholder={t(isGame ? "game.createPlaceholder" : "create.placeholder")}
            rows={2}
          />
        </div>
        {/* Game mode: tap a preset to fill the question (reuses the landing seed
            chips). After game 1 the topic is voted, so these only seed game 1. */}
        {isGame && (
          <div className={`seed-collapse${hasText ? " collapsed" : ""}`}>
            <div className="seed-chips">
              {FUN_SEEDS.slice(0, 4).map((q) => (
                <button
                  key={q}
                  type="button"
                  className="seed-chip"
                  onClick={() => fillQuestion(q)}
                >
                  {q}
                </button>
              ))}
            </div>
          </div>
        )}
        {error && <p className="err-text">{error}</p>}
        <button
          className={`btn${canCreate ? " ready" : " idle"}`}
          onClick={handleCreate}
          disabled={!canCreate}
          type="button"
        >
          {loading ? t("create.creating") : t(isGame ? "game.createCta" : "create.cta")} {canCreate && <Arrow />}
        </button>
        {/* Inline consent (sign-in-wrap): no checkbox to reduce friction, but the
            assent is conspicuous and tied to the affirmative Create action —
            far more enforceable than a buried footer browsewrap. */}
        <p className="consent">
          {t("create.consentPre")}
          <a href="/terms" target="_blank" rel="noopener noreferrer">
            {t("create.terms")}
          </a>
          {t("create.consentAmp")}
          <a href="/privacy" target="_blank" rel="noopener noreferrer">
            {t("create.privacy")}
          </a>
          .
        </p>
      </div>
    </AppShell>
  );
}
