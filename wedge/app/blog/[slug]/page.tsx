import Link from "next/link";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { blogPosts, getPost, type BlogSection } from "@/lib/blog";
import { AppShell, BrandRail, Arrow } from "../../components/ui";
import { CtaButton, TrackLandingView } from "../../components/track";

export const dynamicParams = false;

export function generateStaticParams() {
  return blogPosts.map((p) => ({ slug: p.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const p = getPost(slug);
  if (!p) return {};
  return {
    title: `${p.title} — OneMind`,
    description: p.metaDescription,
    keywords: p.keywords,
    alternates: { canonical: `https://onemind.life/blog/${slug}` },
    openGraph: {
      title: p.title,
      description: p.metaDescription,
      url: `https://onemind.life/blog/${slug}`,
      type: "article",
    },
    // noindex (2026-07-25) — see app/blog/page.tsx. Posts stay live and
    // shareable (OG tags intact, so link previews still work); they're just
    // not search destinations. `follow: true` keeps links to "/" flowing.
    robots: { index: false, follow: true },
  };
}

function fmtDate(d: string): string {
  const [y, m, day] = d.split("-").map(Number);
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  return `${months[(m || 1) - 1]} ${day}, ${y}`;
}

function Section({ s, route }: { s: BlogSection; route: string }) {
  switch (s.type) {
    case "heading":
      return <h2 className="blog-h2">{s.text}</h2>;
    case "subheading":
      return <h3 className="blog-h3">{s.text}</h3>;
    case "paragraph":
      return <p className="blog-p">{s.text}</p>;
    case "bullets":
      return (
        <ul className="blog-ul">
          {s.items.map((it, i) => (
            <li key={i}>{it}</li>
          ))}
        </ul>
      );
    case "divider":
      return <hr className="blog-hr" />;
    case "diagram":
      // The Flutter app rendered an inline convergence diagram here; in the
      // wedge it's a lightweight visual cue, not load-bearing for the prose.
      return <div className="blog-diagram" aria-hidden />;
    case "cta":
      // All blog CTAs route to /create (the one shared experience).
      return (
        <div className="blog-cta">
          <p className="blog-p">{s.text}</p>
          <CtaButton label={s.buttonLabel} route={route} />
        </div>
      );
    default:
      return null;
  }
}

export default async function BlogPost({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const p = getPost(slug);
  if (!p) notFound();

  const route = `/blog/${slug}`;
  const ld = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: p.title,
    description: p.metaDescription,
    datePublished: p.date,
    author: { "@type": "Person", name: p.author },
    keywords: p.keywords.join(", "),
    mainEntityOfPage: `https://onemind.life/blog/${slug}`,
  };

  return (
    <AppShell>
      <TrackLandingView route={route} />
      <BrandRail />
      <article className="blog-post">
        <Link href="/blog" className="blog-back">
          ← All posts
        </Link>
        <h1 className="blog-title">{p.title}</h1>
        <div className="blog-byline">
          {p.author} · {fmtDate(p.date)}
        </div>
        {p.sections.map((s, i) => (
          <Section key={i} s={s} route={route} />
        ))}
        <div className="blog-foot">
          <Link href="/create" className="btn">
            Start a decision <Arrow />
          </Link>
        </div>
      </article>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(ld) }}
      />
    </AppShell>
  );
}
