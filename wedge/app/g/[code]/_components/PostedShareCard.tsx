"use client";

import { useState } from "react";
import { shareRoom } from "@/lib/onemind/shareRoom";
import { isPushSupported, pushPermission } from "@/lib/onemind/push";
import type { usePushOptIn } from "../_hooks/usePushOptIn";
import { ShareIcon, CheckIcon } from "./icons";
import css from "../TreeChat.module.css";

/// Shown right after you post an opinion — you've been dropped INTO your own
/// take (the empty thread you just created), and this is the hero of that
/// screen: your take is live, so SHARE it (the peak-intent moment for the growth
/// loop) and optionally get pinged when people weigh in. The share hands out the
/// APP link (`/g/<code>?take=<id>`) so a recipient lands straight in the live
/// product. Honest framing: you can't "vote for" one opinion (voting is
/// head-to-head), so the pitch is "see where the crowd ranks it", not "get votes".
export function PostedShareCard({
  code,
  propId,
  pushOptIn,
}: {
  code: string;
  propId: number;
  pushOptIn: ReturnType<typeof usePushOptIn>;
}) {
  const [copied, setCopied] = useState(false);
  // Only offer notify where it can actually work + hasn't been answered.
  const canNotify =
    isPushSupported() && pushPermission() === "default" && !pushOptIn.ok;

  return (
    <div className={css.postedCard}>
      <div className={css.postedTitle}>Your take is live.</div>
      <div className={css.postedSub}>
        It&rsquo;ll climb as people vote on it head-to-head. Share it and see
        where the crowd ranks it.
      </div>
      <button
        className={css.postedShare}
        type="button"
        onClick={async () => {
          const r = await shareRoom(code, "OneMind", propId);
          if (r === "copied") {
            setCopied(true);
            setTimeout(() => setCopied(false), 1800);
          }
        }}
      >
        {copied ? <CheckIcon /> : <ShareIcon />}
        <span>{copied ? "Link copied" : "Share your take"}</span>
      </button>
      {canNotify && (
        <button
          className={css.postedNotify}
          type="button"
          disabled={pushOptIn.busy}
          onClick={() => void pushOptIn.accept()}
        >
          {pushOptIn.busy ? "…" : "🔔 Tell me when people weigh in"}
        </button>
      )}
      {pushOptIn.ok && (
        <div className={css.postedNotifyDone}>
          🔔 You&rsquo;re set — we&rsquo;ll ping you when it moves.
        </div>
      )}
    </div>
  );
}
