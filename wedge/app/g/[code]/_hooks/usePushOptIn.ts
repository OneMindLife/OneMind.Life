"use client";

import { useCallback, useState } from "react";
import { enablePush, isPushSupported, pushPermission } from "@/lib/onemind/push";

// Push re-engagement opt-in, shared by the proposing + rating surfaces. The away
// user is the whole retention problem: today they only return if they remember
// to. We ask for push at PEAK INTENT — right after they submit an idea or cast a
// vote — once, and only where it can actually work — so the "it's time to come
// back" ping can pull them in.
export function usePushOptIn() {
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [ok, setOk] = useState(false);

  const dismiss = useCallback(() => {
    try {
      localStorage.setItem("om_push_asked", "1");
    } catch {
      /* private mode — worst case we ask again next session */
    }
    setShow(false);
  }, []);

  const maybeOffer = useCallback(() => {
    if (typeof window === "undefined") return;
    try {
      if (localStorage.getItem("om_push_asked")) return;
    } catch {
      return;
    }
    if (isPushSupported() && pushPermission() === "default") setShow(true);
  }, []);

  const accept = useCallback(async () => {
    setBusy(true);
    try {
      const result = await enablePush();
      if (result === "granted") {
        setOk(true);
        setTimeout(() => setShow(false), 2200);
      } else {
        setShow(false);
      }
    } finally {
      setBusy(false);
      try {
        localStorage.setItem("om_push_asked", "1");
      } catch {
        /* best-effort */
      }
    }
  }, []);

  return { show, busy, ok, dismiss, maybeOffer, accept };
}
