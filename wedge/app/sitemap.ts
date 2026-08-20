import type { MetadataRoute } from "next";

// Generated sitemap. A sitemap should list exactly the pages we want indexed —
// nothing else — so this mirrors the 2026-07-25 decision that "/" is the only
// search destination on the domain (legal pages kept indexable but they're
// listed here too since they're crawlable and canonical).
//
// Everything else is noindexed at the route level rather than merely omitted
// here: the blog (app/blog/**), the retired expanding-thread opinion pages
// (app/opinions/**), and the client-rendered app shells (/c, /g, /join, /home,
// /create, /instant). Omitting a URL from a sitemap does NOT deindex it — the
// `robots` metadata on those routes is what does the work. Don't re-add them
// here without also removing their noindex, or you'd be telling Google two
// opposite things.
//
// This used to fan out to tools/seo_pages.json (keyword landing pages, retired
// 2026-07-16) and to get_seo_index / get_seo_node_index over the network. It no
// longer touches the database at all, so a Supabase hiccup can't affect a build.
const BASE = "https://onemind.life";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  // Static export → resolves at build time; lastModified reflects the build,
  // which is exactly when this static content last changed.
  const now = new Date();
  const at = (path: string) => `${BASE}${path}`; // trailingSlash:true → canonical form has the slash

  return [
    { url: at("/"), lastModified: now, changeFrequency: "weekly", priority: 1.0 },
    { url: at("/privacy/"), lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: at("/terms/"), lastModified: now, changeFrequency: "yearly", priority: 0.3 },
  ];
}
