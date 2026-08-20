// SEO canonical resolution for the single-shell /g/<code> route.
//
// /g/<code> is served from ONE static shell (/g/_) for every code via a Firebase
// rewrite, so its raw HTML can't carry a per-code <link rel="canonical">. We
// inject one client-side once the code is known (Google renders JS and honors
// rendered canonicals). This decides WHERE it points — the pure part, so it's
// unit-tested rather than buried in a component effect.
//
// Two cases (docs/SEO_CONTENT_STRATEGY.md — "pages-not-rooms"):
//   • SEO-eligible chats (an official public chat with a static /opinions/<code>/
//     content page) → canonical points at that content page, consolidating the
//     interactive app URL's signals onto the crawlable surface we actually want
//     indexed.
//   • Every other code → a param-STRIPPED self-canonical. This is what clears
//     Search Console's "Duplicate without user-selected canonical": every
//     /g/<code>?take=<node> deep-link variant now declares the clean /g/<code>
//     as its one canonical, instead of each param combo looking like its own
//     unclaimed duplicate.

export const CANONICAL_ORIGIN = "https://onemind.life";

/// The canonical URL for a /g/<code> view. `seoCodes` is the build-time snapshot
/// of codes that have a static /opinions page (from getSeoIndex()); matching is
/// case-insensitive since path codes are upper-cased on read.
export function canonicalForCode(
  code: string,
  seoCodes: readonly string[],
): string {
  const c = code.toUpperCase();
  const hasOpinionsPage = seoCodes.some((s) => s.toUpperCase() === c);
  return hasOpinionsPage
    ? `${CANONICAL_ORIGIN}/opinions/${c}/` // trailingSlash:true → slash form
    : `${CANONICAL_ORIGIN}/g/${c}`; // param-stripped self-canonical
}
