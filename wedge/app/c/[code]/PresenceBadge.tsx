"use client";

import { useEffect, useRef, useState } from "react";
import { useI18n } from "@/lib/i18n";

/// Top-rail "who's here right now" indicator. ≥2 people → a pulsing live dot +
/// "N here" (aliveness / social proof). Solo → a muted "just you" (honest, not
/// alarming; the in-body invite block is the share nudge). The count comes from
/// Realtime Presence (see usePresence) — on mobile it means "actively here".
///
/// Join-bump: when the count goes UP (someone new arrives), the badge gives a
/// one-time pop + brighter glow, on top of the steady breath. Suppressed on your
/// own initial sync (prev count of 0) so it only fires for real arrivals after
/// you've settled in.
export default function PresenceBadge({ count }: { count: number }) {
  const { t } = useI18n();
  const prev = useRef(count);
  const [bump, setBump] = useState(false);

  useEffect(() => {
    const grew = count > prev.current && prev.current >= 1;
    prev.current = count;
    if (!grew) return;
    setBump(true);
    const timer = setTimeout(() => setBump(false), 700);
    return () => clearTimeout(timer);
  }, [count]);

  if (count <= 1) {
    return (
      <div className="presence">
        <span className="pdot" />
        <span>{t("pres.justYou")}</span>
      </div>
    );
  }
  return (
    <div className={`presence live${bump ? " bump" : ""}`}>
      <span className="pdot" />
      <span className="pcount">{count}</span>
      <span>{t("pres.here")}</span>
    </div>
  );
}
