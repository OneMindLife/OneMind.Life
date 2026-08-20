"use client";

import { useI18n, LANGS, type Lang } from "@/lib/i18n";

/// Small, quiet EN | ES pill toggle. Styled with `currentColor` + rgba so it
/// reads correctly in BOTH the dark GlobalChat header and the lighter rails it
/// also sits in (Proposing / Voting / Results / create). The active language is
/// filled; the other is muted. Inline styles keep it self-contained.
export default function LangToggle() {
  const { lang, setLang } = useI18n();

  return (
    <div
      role="group"
      aria-label="Language"
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 2,
        padding: 2,
        borderRadius: 999,
        border: "1px solid rgba(128,128,128,0.28)",
        font: "inherit",
        lineHeight: 1,
      }}
    >
      {LANGS.map((l: Lang) => {
        const active = l === lang;
        return (
          <button
            key={l}
            type="button"
            onClick={() => setLang(l)}
            aria-pressed={active}
            style={{
              appearance: "none",
              border: "none",
              cursor: "pointer",
              padding: "3px 8px",
              borderRadius: 999,
              fontSize: 11,
              fontWeight: active ? 700 : 500,
              letterSpacing: "0.04em",
              fontFamily:
                "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
              textTransform: "uppercase",
              color: active ? "inherit" : "currentColor",
              opacity: active ? 1 : 0.55,
              background: active ? "rgba(128,128,128,0.22)" : "transparent",
              transition: "opacity 120ms ease, background 120ms ease",
            }}
          >
            {l}
          </button>
        );
      })}
    </div>
  );
}
