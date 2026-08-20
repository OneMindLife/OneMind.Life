"use client";

import { useEffect } from "react";

/// Keep a `--kb-bottom` CSS var on <html> equal to the on-screen keyboard's
/// height, so the fixed composer sits above it (and never scrolls behind it).
/// `interactive-widget=resizes-content` handles Android; this visualViewport
/// offset covers iOS / in-app webviews where the layout viewport doesn't shrink.
///
/// Writes only when the value actually changes, and listens to `resize` ONLY
/// (no `scroll`) — otherwise the fixed composer's position thrashes, which shows
/// up as the list jittering on every keystroke. Keyboard show/hide fires
/// `resize`, which is all we need.
export function useKeyboardInset() {
  useEffect(() => {
    const vv = typeof window !== "undefined" ? window.visualViewport : null;
    if (!vv) return;
    const apply = () => {
      const inset = Math.max(0, Math.round(window.innerHeight - vv.height));
      const next = `${inset}px`;
      if (
        document.documentElement.style.getPropertyValue("--kb-bottom") !== next
      )
        document.documentElement.style.setProperty("--kb-bottom", next);
    };
    apply();
    vv.addEventListener("resize", apply);
    return () => {
      vv.removeEventListener("resize", apply);
      document.documentElement.style.removeProperty("--kb-bottom");
    };
  }, []);
}
