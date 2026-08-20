"use client";

import type React from "react";
import css from "../TreeChat.module.css";

// A tutorial pointer that starts near screen CENTER (where the eye already is)
// and travels to an off-focus target, then holds there tapping. Solves the "the
// nudge is at the bottom but I was looking at the top" problem. Re-mounting it
// (a new step) replays the journey from center.
// fromX/fromY = the small offset it STARTS at, relative to the target — set
// these toward the center so the finger always moves outward-onto the target
// (e.g. a bottom target starts a bit above; a top target a bit below).
export function TutorialFinger({
  toX,
  toY,
  fromX = "0px",
  fromY = "-54px",
}: {
  toX: string;
  toY: string;
  fromX?: string;
  fromY?: string;
}) {
  return (
    <div
      className={css.tutFinger}
      style={
        {
          "--to-x": toX,
          "--to-y": toY,
          "--fx": fromX,
          "--fy": fromY,
        } as React.CSSProperties
      }
      aria-hidden
    >
      <span className={css.tutFingerTip}>👆</span>
    </div>
  );
}
