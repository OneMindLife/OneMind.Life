"use client";

import css from "../TreeChat.module.css";

/// A just-in-time concept reveal: a small, dismissible card that teaches ONE
/// idea at the moment it becomes real (first duel, first branch). Not a tooltip
/// pointing at a control — a plain sentence about how OneMind works, shown once.
///
/// Sits pinned near the bottom (above the vote dock / composer), so it's in the
/// thumb's path and reads as "here's what just happened" rather than chrome.
export function ConceptReveal({
  text,
  onDismiss,
}: {
  text: string;
  onDismiss: () => void;
}) {
  return (
    <div className={css.revealWrap} role="status">
      <div className={css.revealCard}>
        <p className={css.revealText}>{text}</p>
        <button
          className={css.revealDismiss}
          onClick={onDismiss}
          type="button"
        >
          Got it
        </button>
      </div>
    </div>
  );
}
