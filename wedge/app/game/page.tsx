import type { Metadata } from "next";
import { AppShell, BrandRail, LegalFooter } from "../components/ui";
import { CtaButton, TrackLandingView } from "../components/track";

// noindex (2026-07-25). "/" is the only page we want in Google's index.
//
// This used to carry `alternates: { canonical: "https://onemind.life/" }` on the
// grounds that /game was "a near-exact duplicate of the homepage doorway (same
// title, H1 and content)". That stopped being true when "/" was repositioned to
// "the world's group chat" — /game now has its own title, H1 and body copy, and
// Google honors a canonical less the more two pages differ. The canonical is
// REMOVED rather than kept alongside the noindex: `noindex` plus a canonical
// pointing at a *different* URL is a conflicting signal, and Google can
// propagate the noindex to the canonical target — which here would be "/".
//
// Paid traffic is unaffected; this is an ad landing page and robots metadata
// does not gate ad serving.
export const metadata: Metadata = {
  title: "OneMind — the group idea game",
  description:
    "A game for your group: everyone drops an idea, you vote head-to-head, and the best idea climbs the leaderboard. There's even an AI player to beat. Free, no account.",
  robots: { index: false, follow: true },
};

// The GAME doorway (option A): a distinct entry whose CTA opens game mode
// (/create?game=1) — the social "best ideas win" framing (leaderboard, authorship
// reveal, AI player, play-again). Decision-mode landings are untouched; this is
// the only page that points at game mode. No seed chips here — the create page
// shows the question presets, so we don't duplicate them.
export default function GameLanding() {
  return (
    <AppShell>
      <TrackLandingView route="/game" />
      <BrandRail />
      <div className="land">
        <div>
          <div className="eyebrow">The group idea game</div>
          <h1>
            Whose idea <em>wins?</em>
          </h1>
        </div>
        <div className="sub">
          Everyone drops an idea, you vote head-to-head, and the best one climbs
          the leaderboard. An AI player joins every game and submits its own idea
          — so you've got something to beat. Win, then pick what to settle next.
        </div>
        <CtaButton label="Start a game" route="/game" href="/create?game=1" />
        <p className="fine">No account · 30 seconds · play on any phone</p>
        <LegalFooter />
      </div>
    </AppShell>
  );
}
