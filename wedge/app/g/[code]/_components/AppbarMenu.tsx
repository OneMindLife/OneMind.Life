"use client";

import { useEffect, useRef, useState } from "react";
import { GitHubIcon, HelpIcon, MenuIcon } from "./icons";
import css from "../TreeChat.module.css";

/// The appbar overflow menu (⋮, top-right) — app-level odds and ends only:
/// "What is OneMind?" (the concept sheet), Source code. Share deliberately does
/// NOT live here: it's a per-location action, so it sits on the crumb row
/// (CrumbShare) next to the path — "share where I am".
///
/// "How it works" USED to live here and replay the mechanics tour — but the
/// tour taught nothing to anyone who'd already used the app, and labeling your
/// own controls is an anti-pattern. It now opens a concept explainer instead.
// Sun / moon glyphs for the Daylight ↔ Voting Booth toggle. Inline (route-local).
const MoonIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden fill="currentColor">
    <path d="M12.5 3a7 7 0 1 0 8.5 8.5A6 6 0 0 1 12.5 3z" />
  </svg>
);
const SunIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden fill="currentColor">
    <path d="M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10zm0-6 2 3h-4l2-3zm0 22-2-3h4l-2 3zM3.5 5.6 6 7l-1.4 1.4L2 6 3.5 5.6zm15 12.8L21 21l-1.4 1.4-2.5-2.5 1.4-1.5zM1 12l3-2v4l-3-2zm22 0-3 2v-4l3 2zM5.6 20.5 4 18l1.4-1.4L7 19l-1.4 1.5zM18.4 3.5 20 6l-1.4 1.4L17 5l1.4-1.5z" />
  </svg>
);

export function AppbarMenu({
  onExplainConcept,
  theme,
  onToggleTheme,
}: {
  onExplainConcept: () => void;
  theme: "light" | "dark";
  onToggleTheme: () => void;
}) {
  const [openState, setOpenState] = useState(false);
  const open = openState;
  const wrapRef = useRef<HTMLDivElement>(null);

  // Dismiss on outside tap / Escape.
  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node))
        setOpenState(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpenState(false);
    };
    document.addEventListener("pointerdown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div className={css.menuWrap} ref={wrapRef}>
      <button
        className={`${css.ghBtn} ${css.menuBtn}`}
        onClick={() => setOpenState((v) => !v)}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="Menu"
        title="Menu"
      >
        <MenuIcon />
      </button>
      {open && (
        <div className={css.menuSheet} role="menu">
          <button
            className={css.menuItem}
            role="menuitem"
            type="button"
            onClick={() => {
              onExplainConcept();
              setOpenState(false);
            }}
          >
            <HelpIcon />
            <span>What is OneMind?</span>
          </button>
          <button
            className={css.menuItem}
            role="menuitem"
            type="button"
            onClick={() => {
              onToggleTheme();
              setOpenState(false);
            }}
          >
            {theme === "dark" ? <SunIcon /> : <MoonIcon />}
            <span>{theme === "dark" ? "Daylight" : "Night mode"}</span>
          </button>
          <a
            className={css.menuItem}
            role="menuitem"
            href="https://github.com/OneMindLife/OneMind.Life"
            target="_blank"
            rel="noopener noreferrer"
            onClick={() => setOpenState(false)}
          >
            <GitHubIcon />
            <span>Source code</span>
          </a>
        </div>
      )}
    </div>
  );
}
