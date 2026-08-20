"use client";

import type { usePushOptIn } from "../_hooks/usePushOptIn";
import css from "../TreeChat.module.css";

/// The opt-in prompt driven by usePushOptIn — renders nothing until an offer is
/// live, then a one-tap "Notify me / No thanks", and a confirmation on grant.
export function PushOptInCard({
  s,
  prompt,
}: {
  s: ReturnType<typeof usePushOptIn>;
  prompt: string;
}) {
  if (!s.show) return null;
  return (
    <div className={css.pushCard}>
      {s.ok ? (
        <div className={css.pushDone}>
          🔔 You&apos;re set — we&apos;ll ping you when there&apos;s something
          new.
        </div>
      ) : (
        <>
          <div className={css.pushText}>🔔 {prompt}</div>
          <div className={css.pushBtns}>
            <button
              className={css.pushYes}
              onClick={() => void s.accept()}
              disabled={s.busy}
              type="button"
            >
              {s.busy ? "…" : "Notify me"}
            </button>
            <button
              className={css.pushNo}
              onClick={s.dismiss}
              disabled={s.busy}
              type="button"
            >
              No thanks
            </button>
          </div>
        </>
      )}
    </div>
  );
}
