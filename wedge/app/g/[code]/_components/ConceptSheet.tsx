"use client";

import { useEffect } from "react";
import css from "../TreeChat.module.css";

/// "What is OneMind?" — the concept explainer that replaces the old "How it
/// works" tour.
///
/// The tour taught MECHANICS (tap here, type here) — an anti-pattern (NN/G:
/// instructional overlays that label controls are a crutch for an unclear UI),
/// and it left a power user with nothing because its steps were nudges pinned to
/// live surfaces they'd already passed. This teaches the CONCEPT instead: what
/// OneMind is and why head-to-head voting means anything. That is the part a
/// textfield and some cards genuinely cannot make self-evident.
///
/// Available on demand (from the ⋮ menu), never forced — the app teaches the
/// same model just-in-time as you hit each moment (first duel, first branch,
/// convergence). This is the "I want the why, now" surface, and unlike the old
/// tour it works for a brand-new AND a veteran user because it isn't step-gated.
///
/// The numbered beats are a real sequence (opinion -> contest -> outcome), so
/// the numbering encodes the actual flow rather than decorating it.
export function ConceptSheet({ onClose }: { onClose: () => void }) {
  // Escape closes, matching the menu/inbox affordances.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  const beats = [
    {
      lead: "Say what you really think.",
      body: "One chat, open to everyone, everyone anonymous. Drop your honest opinion — no name attached.",
    },
    {
      lead: "Opinions face off, two at a time.",
      body: "You vote on which of two you find stronger. Nobody sets the rule for what “stronger” means — the crowd's votes decide it together.",
    },
    {
      lead: "The best rises, and sticks.",
      body: "The top-voted opinion holds its place in the chat. And any opinion can be opened and taken deeper — a chat inside the chat.",
    },
  ];

  return (
    <div className={css.sheetBackdrop} onClick={onClose}>
      <div
        className={css.sheet}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-label="What is OneMind?"
      >
        <div className={css.sheetHandle} aria-hidden />
        <div className={css.sheetTitle}>What is OneMind?</div>
        <ol className={css.conceptList}>
          {beats.map((b, i) => (
            <li key={i} className={css.conceptBeat}>
              <span className={css.conceptNum} aria-hidden>
                {i + 1}
              </span>
              <span className={css.conceptText}>
                <span className={css.conceptLead}>{b.lead}</span>
                <span className={css.conceptBody}>{b.body}</span>
              </span>
            </li>
          ))}
        </ol>
        <button className={css.conceptDone} onClick={onClose} type="button">
          Got it
        </button>
      </div>
    </div>
  );
}
