import Link from "next/link";
import type { Metadata } from "next";
import { blogPosts } from "@/lib/blog";
import { AppShell, BrandRail, ChevR } from "../components/ui";
import { TrackLandingView } from "../components/track";

// noindex (2026-07-25). Product decision: "/" is the only page we want in
// Google's index. The posts stay live and shareable — they're just not search
// destinations any more. `follow: true` so the links out to "/" still pass
// signal while Google re-crawls and drops these.
export const metadata: Metadata = {
  title: "Blog — OneMind",
  description:
    "Essays on group decision-making, consensus, collective intelligence, and how groups converge on the answers they stand behind.",
  alternates: { canonical: "https://onemind.life/blog" },
  robots: { index: false, follow: true },
};

function fmtDate(d: string): string {
  const [y, m, day] = d.split("-").map(Number);
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  return `${months[(m || 1) - 1]} ${day}, ${y}`;
}

export default function BlogIndex() {
  return (
    <AppShell>
      <TrackLandingView route="/blog" />
      <BrandRail />
      <header className="seo-hero">
        <div className="eyebrow">OneMind blog</div>
        <h1 className="seo-h1">How groups decide</h1>
        <p className="seo-sub">
          Essays on consensus, collective intelligence, and the mechanics of
          converging on an answer everyone stands behind.
        </p>
        <p className="fine">
          Or skip the theory —{" "}
          <a href="/opinions/GLOBAL/">read what people actually think, ranked →</a>
        </p>
      </header>

      <section className="seo-section">
        <div className="blog-list">
          {blogPosts.map((p) => (
            <Link key={p.slug} href={`/blog/${p.slug}`} className="blog-row">
              <div className="blog-row-main">
                <div className="blog-row-title">{p.title}</div>
                <div className="blog-row-desc">{p.metaDescription}</div>
                <div className="blog-row-meta">{fmtDate(p.date)}</div>
              </div>
              <ChevR />
            </Link>
          ))}
        </div>
      </section>
    </AppShell>
  );
}
