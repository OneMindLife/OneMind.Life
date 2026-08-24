import type { Metadata } from "next";
import { Logotype, LegalFooter } from "./components/ui";
import { CtaButton, TrackLandingView } from "./components/track";

export const metadata: Metadata = {
  // Root landing — "next step" positioning: OneMind is the group's democratic
  // next-step engine, not a meeting or an idea contest.
  title: "OneMind — What should your group do next?",
  description:
    "OneMind answers the one question every group always has: what do we do next? Everyone proposes, everyone rates, and the next step rises to the top — democratically.",
  alternates: { canonical: "https://onemind.life/" },
};

export default function Home() {
  return (
    <main className="collective">
      <TrackLandingView route="/" />
      <div className="wrap">
        <Logotype />

        {/* ── Hero ── */}
        <h1>What should your group do next?</h1>
        <p className="sub">
          There&apos;s always a next — and OneMind decides it democratically.
          Everyone proposes, everyone rates, and a clear next step rises to the
          top. No loudest-voice-wins, no endless meetings.
        </p>
        <CtaButton
          label="Try It Free"
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
          <p className="section-sub">Three steps to decide what&apos;s next</p>
          <div className="steps">
            <div className="step">
              <span className="step-num">1</span>
              <h3>Propose</h3>
              <p>
                Everyone says what they think should happen next — anonymously.
                No bias, no groupthink — just honest takes.
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
                A clear next step emerges — your group&apos;s direction, decided
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
          <h2>Why OneMind?</h2>
          <div className="steps">
            <div className="step">
              <h3>Anonymous Proposals</h3>
              <p>
                Everyone submits ideas privately. No anchoring, no groupthink, no
                social pressure. Ideas stand on their own merit — not on who said
                them.
              </p>
            </div>
            <div className="step">
              <h3>Structured Rounds</h3>
              <p>
                Timed proposing and rating phases keep things moving. The
                structure does the heavy lifting — no facilitator bias, no endless
                discussion, no decision fatigue.
              </p>
            </div>
            <div className="step">
              <h3>Fast Results</h3>
              <p>
                Run one quick round and lock in a winner in minutes — no meetings,
                no back-and-forth. Go deeper when the decision really matters.
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
          <h2>Ready to decide what&apos;s next?</h2>
          <p className="section-sub">
            Try OneMind free — no account, start in 30 seconds.
          </p>
          <CtaButton
            label="Try It Free"
            route="/"
            href="https://app.onemind.life"
          />
        </section>

        <LegalFooter />
      </div>
    </main>
  );
}
