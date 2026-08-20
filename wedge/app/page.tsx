import type { Metadata } from "next";
import { AppShell, BrandRail, LegalFooter } from "./components/ui";
import { CtaButton, TrackLandingView } from "./components/track";

export const metadata: Metadata = {
  // Overrides the layout default for "/" — keep the two in step. Since "/" is
  // now the only indexed page on the domain, this string IS the Google result.
  title: "OneMind — uniting the world",
  description:
    "The world's group chat: one room the whole world is in. Post what's on your mind, see what everyone else is saying, and vote the best lines up — every round the room's top line rises to the top. Join the world's conversation, free.",
  // Self-referencing canonical — without it Search Console flagged "/" (and its
  // /index.html twin + the app-shell routes) as "Duplicate without user-selected
  // canonical". Next normalizes to the trailing-slash form on output.
  alternates: { canonical: "https://onemind.life/" },
};

// The brand home is the GLOBAL doorway. OneMind is one thing now (2026-07-20
// revert to the phased group chat): a single anonymous room where everyone says
// what they think, votes head-to-head on what others said, and every 12 hours
// the room's best line wins and is kept. The personal hook is safety ("say what
// you really think — no name attached"); the wonder hook is watching the room
// converge on what it actually believes. No create flows, no /home: landing →
// /c/GLOBAL, that's the product.
export default function Home() {
  return (
    <AppShell className="landing">
      <TrackLandingView route="/" />
      <BrandRail />
      <div className="land">
        <div>
          <div className="eyebrow">The world&apos;s group chat</div>
          <h1>
            One room. <em>The whole world.</em>
          </h1>
        </div>
        <div className="sub">
          One chat the whole world is in. Post what&apos;s actually on your mind,
          see what everyone else is saying, and vote the best lines up. No
          followers, no algorithm — every round the room picks its best line and
          keeps it.
        </div>
        {/* The mission, stated plainly and sitting immediately before the CTA:
            the product pitch above earns it, and it's the last thing read before
            the click, so joining means something. Dropped the sub's old closing
            line ("The world, talking as one.") — it was gesturing at this, and
            saying it twice weakened both. */}
        <p className="mission">
          The goal of OneMind is to <em>unite the world.</em>
        </p>
        <CtaButton label="Join the chat" route="/" href="/c/GLOBAL" />
        <p className="fine">Free · no account · 30 seconds to your first message</p>
        {/* Lower-commitment entry + crawlable internal link into the content
            SEO surface (docs/SEO_CONTENT_STRATEGY.md). */}
        <p className="fine">
          <a href="/c/GLOBAL">Or just read the room →</a>
        </p>
        <LegalFooter />
      </div>
    </AppShell>
  );
}
