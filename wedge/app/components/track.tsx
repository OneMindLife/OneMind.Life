"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { track } from "@/lib/onemind/analytics";
import { getMode, FUN_SEEDS } from "@/lib/onemind/mode";
import { Arrow } from "./ui";

// Landing pages are server components; analytics needs the client. These two
// tiny client pieces let a server-rendered landing fire the funnel events with
// the same names/params the live Flutter app uses, so GA4/PostHog reads stay
// continuous after the cutover.

// Fires landing_viewed once on mount. Renders nothing. `route` = the keyword
// landing path so we can break conversions down per SEO page.
export function TrackLandingView({ route }: { route: string }) {
  const fired = useRef(false);
  useEffect(() => {
    if (fired.current) return;
    fired.current = true;
    track("landing_viewed", { variant: "wedge", landing_route: route });
  }, [route]);
  return null;
}

// Tappable example chips in the hero. Each seeds /create with a starting
// question (editable there) and fires landing_cta_clicked — so a seeded entry
// still counts as the conversion AND is segmentable by which seed (variant
// "wedge_seed" + the seed text). Examples-first: shows the range (sparks
// later-use imagination) while being one tap into the product, not a gate.
export function SeedChips({
  questions,
  route,
  game = false,
}: {
  questions: string[];
  route: string;
  game?: boolean;
}) {
  // In fun mode (H-FUN A/B), swap the decision seeds for playful ones. Set after
  // mount to avoid a hydration mismatch (mode lives in sessionStorage). Game-mode
  // chips keep their own seeds (no swap) and carry game=1 to /create.
  const [qs, setQs] = useState(questions);
  useEffect(() => {
    if (!game && getMode() === "fun") setQs(FUN_SEEDS);
  }, [game]);
  const prefix = game ? "/create?game=1&q=" : "/create?q=";
  return (
    <div className="seed-chips">
      {qs.map((q) => (
        <Link
          key={q}
          href={`${prefix}${encodeURIComponent(q)}`}
          className="seed-chip"
          onClick={() =>
            track("landing_cta_clicked", {
              variant: game ? "wedge_game_seed" : "wedge_seed",
              landing_route: route,
              seed: q,
            })
          }
        >
          {q}
        </Link>
      ))}
    </div>
  );
}

// The landing CTA. Fires landing_cta_clicked (the Google Ads conversion proxy)
// then navigates to /create. Visually identical to the static <Link className=
// "btn"> CTAs.
export function CtaButton({
  label,
  route,
  href = "/create",
}: {
  label: string;
  route: string;
  href?: string;
}) {
  return (
    <Link
      href={href}
      className="btn"
      onClick={() =>
        track("landing_cta_clicked", { variant: "wedge", landing_route: route })
      }
    >
      {label} <Arrow />
    </Link>
  );
}

// Detects when a visitor arrived from an AI answer-engine and fires
// `ai_referral` — our first (nearly free) demand signal for the
// preference-oracle-for-AI thesis: are AIs actually sending humans to our
// opinion content? Referrer-based, so it undercounts (many engines strip the
// referrer or users paste links) — a floor, not a full count. See
// docs/ONEMIND_CONCEPT.md. Renders nothing.
const AI_ENGINES: { host: RegExp; name: string }[] = [
  { host: /(^|\.)chatgpt\.com$/, name: "chatgpt" },
  { host: /(^|\.)chat\.openai\.com$/, name: "chatgpt" },
  { host: /(^|\.)openai\.com$/, name: "openai" },
  { host: /(^|\.)perplexity\.ai$/, name: "perplexity" },
  { host: /(^|\.)claude\.ai$/, name: "claude" },
  { host: /(^|\.)gemini\.google\.com$/, name: "gemini" },
  { host: /(^|\.)bard\.google\.com$/, name: "gemini" },
  { host: /(^|\.)copilot\.microsoft\.com$/, name: "copilot" },
  { host: /(^|\.)you\.com$/, name: "you" },
  { host: /(^|\.)poe\.com$/, name: "poe" },
  { host: /(^|\.)phind\.com$/, name: "phind" },
];

export function TrackAiReferral({ route }: { route: string }) {
  const fired = useRef(false);
  useEffect(() => {
    if (fired.current) return;
    fired.current = true;
    let host = "";
    try {
      host = document.referrer ? new URL(document.referrer).hostname : "";
    } catch {
      return;
    }
    if (!host) return;
    const hit = AI_ENGINES.find((e) => e.host.test(host));
    if (hit) {
      track("ai_referral", {
        variant: "wedge",
        landing_route: route,
        ai_source: hit.name,
        referrer_host: host,
      });
    }
  }, [route]);
  return null;
}
