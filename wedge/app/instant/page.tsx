import type { Metadata } from "next";
import { AppShell, BrandRail, LegalFooter, Arrow } from "../components/ui";

// Private doorway to the "instant mode, continuous" experience — the deprecated
// Flutter app, deployed standalone at onemind-instant.web.app. Not in the
// sitemap, no ads, noindex (a self-test surface, not a marketing page). The CTA
// drops users on the Flutter app's /home, where the full create wizard makes a
// continuous (max_cycles=null) + instant (confirmation_rounds=1) group chat.
export const metadata: Metadata = {
  title: "OneMind Instant — Continuous Group Chat",
  description:
    "An always-on group chat where ideas come in, get ranked head-to-head, and the winner locks in instantly.",
  robots: { index: false, follow: false },
};

const APP_URL = "https://onemind-instant.web.app/home";

export default function InstantLanding() {
  return (
    <AppShell>
      <BrandRail />
      <div className="land">
        <div>
          <div className="eyebrow">Instant mode · continuous</div>
          <h1>
            One <em>continuous</em> group chat.
          </h1>
        </div>
        <div className="sub">
          An always-on group chat where everyone adds ideas, compares them
          head-to-head, and the winning idea locks in instantly — then the group
          keeps going. Works in English and Spanish. Free, no account.
        </div>
        <a className="btn" href={APP_URL}>
          Open the instant app <Arrow />
        </a>
        <p className="fine">No account · works on any phone</p>
        <LegalFooter />
      </div>
    </AppShell>
  );
}
