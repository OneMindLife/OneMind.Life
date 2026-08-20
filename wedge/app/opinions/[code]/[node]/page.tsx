import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getSeoNode, getSeoNodeIndex } from "@/lib/onemind/seo";
import { AppShell, BrandRail, LegalFooter } from "../../../components/ui";
import {
  CtaButton,
  TrackLandingView,
  TrackAiReferral,
} from "../../../components/track";

// Per-thread SEO page: ONE opinion + its replies ranked head-to-head. The root
// /opinions/<code> page bundles every top-level opinion (dozens of unrelated
// topics) onto one page; this splits each opinion's discussion onto its own
// topically-focused, crawlable page — the headline is the opinion being
// discussed, so the page targets that topic specifically, and the CTA deep-links
// into the live thread (/g/<code>?take=<node>). See docs/SEO_CONTENT_STRATEGY.md.
export const dynamicParams = false;

export async function generateStaticParams() {
  const nodes = await getSeoNodeIndex();
  // output:export rejects a dynamic route that yields ZERO params, so when the
  // index is empty (e.g. the get_seo_node RPCs aren't deployed yet) fall back to
  // a single placeholder that 404s (the page notFound()s on a non-numeric node).
  if (nodes.length === 0) return [{ code: "GLOBAL", node: "_" }];
  return nodes.map((n) => ({ code: n.code, node: String(n.node) }));
}

function truncate(s: string, n: number): string {
  return s.length <= n ? s : s.slice(0, n - 1).trimEnd() + "…";
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ code: string; node: string }>;
}): Promise<Metadata> {
  const { code, node } = await params;
  const data = await getSeoNode(code, Number(node));
  if (!data) return {};
  const canonical = `https://onemind.life/opinions/${data.code}/${data.node}`;
  const topReply = data.opinions[0]?.content ?? null;
  const topic = truncate(data.parent, 70);
  const title = `${topic} — what people say back, ranked | OneMind`;
  const lead = topReply ? `Top reply: “${truncate(topReply, 100)}”. ` : "";
  const description = `${lead}${data.opinions.length} anonymous replies to "${truncate(
    data.parent,
    90,
  )}", ranked head-to-head by the crowd. Add yours — free, no account.`;
  return {
    title,
    description,
    alternates: { canonical },
    openGraph: { title, description, url: canonical, type: "article" },
    // noindex (2026-07-25) — see app/opinions/[code]/page.tsx.
    robots: { index: false, follow: true },
  };
}

export default async function OpinionThreadPage({
  params,
}: {
  params: Promise<{ code: string; node: string }>;
}) {
  const { code, node } = await params;
  const nodeId = Number(node);
  if (!Number.isFinite(nodeId)) notFound(); // the "_" placeholder path
  const data = await getSeoNode(code, nodeId);
  if (!data) notFound();

  const canonical = `https://onemind.life/opinions/${data.code}/${data.node}`;
  // Deep-link straight into THIS thread inside the live chat (?take auto-descends).
  const chatHref = `/g/${data.code}?take=${data.node}`;
  const hubHref = `/opinions/${data.code}/`;
  const total = data.opinions.length;
  const topReply = data.opinions[0] ?? null;
  const analyticsRoute = `/opinions/${data.code}/${data.node}`;

  // DiscussionForumPosting: the parent opinion is the post; each ranked reply a
  // comment (best-first). The top reply is surfaced as the post `text` — the
  // extractable answer for AI answer-engines.
  const ld = {
    "@context": "https://schema.org",
    "@type": "DiscussionForumPosting",
    headline: truncate(data.parent, 110),
    articleBody: data.parent,
    text: topReply
      ? `Top-ranked reply (of ${total}, by head-to-head voting): ${topReply.content}`
      : undefined,
    url: canonical,
    author: { "@type": "Organization", name: "OneMind" },
    interactionStatistic: {
      "@type": "InteractionCounter",
      interactionType: "https://schema.org/CommentAction",
      userInteractionCount: total,
    },
    comment: data.opinions.map((o) => ({
      "@type": "Comment",
      text: o.content,
      author: { "@type": "Person", name: "Anonymous" },
    })),
  };
  const ldJson = JSON.stringify(ld).replace(/</g, "\\u003c");

  return (
    <AppShell>
      <TrackLandingView route={analyticsRoute} />
      <TrackAiReferral route={analyticsRoute} />
      <BrandRail />

      <header className="seo-hero">
        <div className="eyebrow">
          <a href={hubHref}>← All opinions</a>
        </div>
        <h1 className="seo-h1">{data.parent}</h1>
        <p className="seo-sub">
          {total} honest, anonymous replies to this take, ranked head-to-head —
          competing on the idea, not the name. Add yours and vote on the rest.
        </p>
        <CtaButton label="Reply in the live thread" route={analyticsRoute} href={chatHref} />
        <p className="fine">Anonymous · no account · 30 seconds</p>
      </header>

      {topReply && (
        <section className="seo-answer">
          <div className="lbl">The top-ranked reply</div>
          <blockquote>{topReply.content}</blockquote>
          <p className="fine">
            Ranked #1 of {total} — decided by people voting head-to-head, not by
            likes, karma, or recency.
          </p>
        </section>
      )}

      <section className="seo-section">
        <h2 className="seo-h2">All replies ({total})</h2>
        <ol className="seo-ranked">
          {data.opinions.map((o) => (
            <li key={o.id}>{o.content}</li>
          ))}
        </ol>
      </section>

      <section className="seo-closing">
        <h2 className="seo-h2">What do you say back?</h2>
        <p className="seo-sub">
          Drop your honest reply into the live thread — no name, no judgment —
          and watch the best responses rise to the top.
        </p>
        <CtaButton label="Reply in the live thread" route={analyticsRoute} href={chatHref} />
      </section>

      <LegalFooter />

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: ldJson }}
      />
    </AppShell>
  );
}
