import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getSeoChat, getSeoIndex, getSeoNodesForChat } from "@/lib/onemind/seo";
import { AppShell, BrandRail, LegalFooter } from "../../components/ui";
import { CtaButton, TrackLandingView, TrackAiReferral } from "../../components/track";

// Crawlable, ANSWER-FIRST content page: the OneMind chat's opinions ranked by
// head-to-head voting, leading with the group's top-ranked take. Statically
// rendered at build (real HTML for search) and structured for AI answer-engines
// to lift the ranked answer (the preference-oracle-for-AI thesis) — while
// funneling every reader into the ONE live chat. See docs/SEO_CONTENT_STRATEGY.md
// and docs/ONEMIND_CONCEPT.md.
export const dynamicParams = false;

export async function generateStaticParams() {
  const codes = await getSeoIndex();
  // output:export rejects a dynamic route that yields ZERO params, so when the
  // index is empty (a brand-new/low-content official room, before it has sealed
  // enough human takes) fall back to a single placeholder that 404s — the page
  // notFound()s when the code has no eligible SEO chat. Mirrors the [node] route.
  if (codes.length === 0) return [{ code: "GLOBAL" }];
  return codes.map((code) => ({ code }));
}

// Open-floor chats (GLOBAL) have no seed question, so lead with a keyword-rich
// generic headline instead of the chat name; topical chats lead with their
// question (the strongest on-page SEO signal).
function headline(question: string | null): string {
  return question ?? "What the world is saying";
}
function truncate(s: string, n: number): string {
  return s.length <= n ? s : s.slice(0, n - 1).trimEnd() + "…";
}
function pageTitle(question: string | null): string {
  return question
    ? `${question} — what the world is saying, ranked | OneMind`
    : "What the world is saying — ranked by the crowd | OneMind";
}
// Answer-first meta description: lead with the actual top-ranked take so the
// search snippet / AI answer already carries the payoff (the extractable answer).
function summarize(
  question: string | null,
  count: number,
  topTake: string | null,
): string {
  const lead = topTake ? `Top-ranked take: “${truncate(topTake, 100)}”. ` : "";
  return question
    ? `${lead}${count} takes on "${question}" from OneMind — the world's group chat — ranked head-to-head by the crowd. Join in. Free.`
    : `${lead}${count} takes from people worldwide in OneMind, the world's group chat, ranked head-to-head by the crowd — the best lines rise to the top. Join in. Free.`;
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ code: string }>;
}): Promise<Metadata> {
  const { code } = await params;
  const chat = await getSeoChat(code);
  if (!chat) return {};
  const canonical = `https://onemind.life/opinions/${chat.code}`;
  const top = chat.opinions[0]?.content ?? null;
  const title = pageTitle(chat.question);
  const description = summarize(chat.question, chat.opinions.length, top);
  return {
    title,
    description,
    alternates: { canonical },
    openGraph: { title, description, url: canonical, type: "article" },
    // noindex (2026-07-25). These pages are from the expanding-thread era; the
    // product is now the single group chat at /c/GLOBAL, and "/" is the only
    // page we want indexed. Left live rather than deleted so Google can crawl
    // the tag and drop them cleanly.
    robots: { index: false, follow: true },
  };
}

export default async function OpinionsPage({
  params,
}: {
  params: Promise<{ code: string }>;
}) {
  const { code } = await params;
  const chat = await getSeoChat(code);
  if (!chat) notFound();

  // Sub-threads worth their own page (hub → spokes internal linking). Most reply
  // to a top-level opinion, so we drop the opening quote to keep labels tight.
  const threads = await getSeoNodesForChat(chat.code);

  const canonical = `https://onemind.life/opinions/${chat.code}`;
  const chatHref = `/c/${chat.code}`;
  const total = chat.opinions.length;
  const topTake = chat.opinions[0] ?? null;

  // DiscussionForumPosting: the question is the post, each ranked opinion a
  // comment (emitted best-first so the top take is the first comment). The
  // top-ranked take is also surfaced as the post's `text` — the extractable
  // answer for AI answer-engines.
  const ld = {
    "@context": "https://schema.org",
    "@type": "DiscussionForumPosting",
    headline: headline(chat.question),
    text: topTake
      ? `Top-ranked take (of ${total}, by head-to-head voting): ${topTake.content}`
      : undefined,
    url: canonical,
    author: { "@type": "Organization", name: "OneMind" },
    interactionStatistic: {
      "@type": "InteractionCounter",
      interactionType: "https://schema.org/CommentAction",
      userInteractionCount: total,
    },
    comment: chat.opinions.map((o) => ({
      "@type": "Comment",
      text: o.content,
      author: { "@type": "Person", name: "Anonymous" },
    })),
  };
  // Escape "<" so user text can't break out of the JSON-LD <script>.
  const ldJson = JSON.stringify(ld).replace(/</g, "\\u003c");

  return (
    <AppShell>
      <TrackLandingView route={`/opinions/${chat.code}`} />
      <TrackAiReferral route={`/opinions/${chat.code}`} />
      <BrandRail />

      <header className="seo-hero">
        <div className="eyebrow">The world&apos;s group chat</div>
        <h1 className="seo-h1">{headline(chat.question)}</h1>
        <p className="seo-sub">
          {total} takes from people around the world, ranked head-to-head — the
          best lines rise to the top. Jump into the chat and add yours.
        </p>
        <CtaButton label="Join the chat" route={`/opinions/${chat.code}`} href={chatHref} />
        <p className="fine">Free · no account · 30 seconds</p>
      </header>

      {topTake && (
        <section className="seo-answer">
          <div className="lbl">The group&apos;s top-ranked take</div>
          <blockquote>{topTake.content}</blockquote>
          <p className="fine">
            Ranked #1 of {total} — decided by people voting head-to-head, not by
            likes, karma, or recency.
          </p>
        </section>
      )}

      <section className="seo-section">
        <h2 className="seo-h2">The full ranking ({total})</h2>
        {/* The COMPLETE ranking, #1 first — so the list's #1 matches the
            spotlighted top take above (the <ol> counter starts at 1). Rendering
            opinions.slice(1) here mislabelled #2 as "1" and contradicted the
            spotlight. */}
        <ol className="seo-ranked">
          {chat.opinions.map((o) => (
            <li key={o.id}>{o.content}</li>
          ))}
        </ol>
      </section>

      {threads.length > 0 && (
        <section className="seo-section">
          <h2 className="seo-h2">Threads people are debating ({threads.length})</h2>
          <ul className="seo-threads">
            {threads.map((t) => (
              <li key={t.node}>
                <a href={`/opinions/${chat.code}/${t.node}/`}>
                  {t.parent}
                  <span className="seo-thread-count">
                    {t.replies} {t.replies === 1 ? "reply" : "replies"} ›
                  </span>
                </a>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="seo-closing">
        <h2 className="seo-h2">Join the world&apos;s group chat</h2>
        <p className="seo-sub">
          Drop your take into the live chat and watch the room&apos;s best
          thinking rise to the top — one room the whole world is in.
        </p>
        <CtaButton label="Enter the chat" route={`/opinions/${chat.code}`} href={chatHref} />
      </section>

      <LegalFooter />

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: ldJson }}
      />
    </AppShell>
  );
}
