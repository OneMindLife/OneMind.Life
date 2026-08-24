import type { Metadata } from "next";
import { Logotype, LegalFooter } from "./components/ui";
import { CtaButton, TrackLandingView } from "./components/track";

export const metadata: Metadata = {
  // Root landing — "stuck → decided" arc: OneMind is the group's democratic
  // next-step engine for the moment every group hits (opinions, but no motion).
  title: "OneMind — Stop going in circles. Decide what's next.",
  description:
    "Everyone has an opinion. OneMind turns them into one clear next step — everyone proposes, everyone rates, decided democratically. No loudest-voice-wins, no endless meetings.",
  alternates: { canonical: "https://onemind.life/" },
};

export default function Home() {
  return (
    <main className="collective">
      <TrackLandingView route="/" />
      <div className="wrap">
        <Logotype />

        {/* ── Hero (the "stuck" moment → the "decided" promise) ── */}
        <h1>Everyone has an opinion. No one&apos;s moving.</h1>
        <p className="sub">
          Your group is stuck in the same debate. OneMind breaks the loop —
          everyone proposes, everyone rates, and one clear next step rises to the
          top. Democratically. No loudest-voice-wins, no endless meetings.
        </p>
        <CtaButton
          label="Decide what's next"
          route="/"
          href="https://app.onemind.life"
        />
        <div className="fine">Free · No account · 30 seconds</div>
        <div className="fine">
          <a href="/c/GLOBAL">Join the global chat →</a>
        </div>

        {/* ── How It Works ── */}
        <section className="section">
          <h2>How It Works</h2>
          <p className="section-sub">From stuck to decided, in three steps</p>
          <div className="steps">
            <div className="step">
              <span className="step-num">1</span>
              <h3>Propose</h3>
              <p>
                Everyone says what should happen next — anonymously. No bias, no
                groupthink — just honest takes.
              </p>
            </div>
            <div className="step">
              <span className="step-num">2</span>
              <h3>Rate</h3>
              <p>
                The group rates every idea fairly. The strongest direction rises
                to the top — transparent and impossible to manipulate.
              </p>
            </div>
            <div className="step">
              <span className="step-num">3</span>
              <h3>Next Step</h3>
              <p>
                One clear next step emerges — your group&apos;s direction, decided
                democratically and ready to act on.
              </p>
            </div>
          </div>
        </section>

        {/* ── See It in Action ── */}
        <section className="section">
          <h2>See It in Action</h2>
          <div className="video">
            <video controls playsInline preload="metadata">
              <source src="/onemind-demo.mp4" type="video/mp4" />
              Your browser does not support the video tag.
            </video>
          </div>
        </section>

        {/* ── Why OneMind? ── */}
        <section className="section">
          <h2>Why groups stop going in circles</h2>
          <div className="steps">
            <div className="step">
              <h3>Anonymous Proposals</h3>
              <p>
                No anchoring, no groupthink — ideas stand on their own merit, not
                on who said them.
              </p>
            </div>
            <div className="step">
              <h3>Structured Rounds</h3>
              <p>
                Timed proposing and rating keep it moving — no facilitator bias,
                no endless discussion, no decision fatigue.
              </p>
            </div>
            <div className="step">
              <h3>Fast Results</h3>
              <p>
                One quick round and you have your next step — no meetings, no
                back-and-forth.
              </p>
            </div>
          </div>
        </section>

        {/* ── Social Proof (placeholder — replace with a real quote) ── */}
        <section className="section">
          <h2>Groups use OneMind to decide</h2>
          <div className="quote">
            <p className="quote-text">
              &ldquo;[Customer quote — who used OneMind, for what, and the
              outcome.]&rdquo;
            </p>
            <p className="quote-attrib">— Name, Role</p>
          </div>
        </section>

        {/* ── Closing CTA ── */}
        <section className="section closing">
          <h2>Ready to stop going in circles?</h2>
          <p className="section-sub">
            Try OneMind free — no account, a clear next step in 30 seconds.
          </p>
          <CtaButton
            label="Decide what's next"
            route="/"
            href="https://app.onemind.life"
          />
        </section>

        <LegalFooter />
      </div>
    </main>
  );
}
