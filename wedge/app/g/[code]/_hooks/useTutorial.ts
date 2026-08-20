"use client";

import { useCallback, useEffect, useState } from "react";
import {
  nextTutStep,
  readTutStep,
  TUT_STORAGE_KEY,
  type TutStep,
} from "@/lib/onemind/tutorial";

/// The shared guided-tutorial controller for the /g screen: one step, lit by
/// whichever surface owns it, advanced forward-only and persisted so it runs
/// once. `advance(to)` never regresses; `restart()` replays from the top.
export function useTutorial() {
  const [step, setStep] = useState<TutStep>("vote");

  // Hydrate from storage after mount (SSR renders the default "vote").
  useEffect(() => {
    setStep(readTutStep());
  }, []);

  const advance = useCallback((to: TutStep) => {
    setStep((cur) => {
      const next = nextTutStep(cur, to);
      if (next !== cur) {
        try {
          localStorage.setItem(TUT_STORAGE_KEY, next);
        } catch {
          /* private mode — worst case it replays next session */
        }
      }
      return next;
    });
  }, []);

  const restart = useCallback(() => {
    try {
      localStorage.setItem(TUT_STORAGE_KEY, "vote");
    } catch {
      /* private mode */
    }
    setStep("vote");
  }, []);

  return { step, advance, restart };
}
