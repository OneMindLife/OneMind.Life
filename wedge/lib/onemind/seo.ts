// Build-time SEO content fetch. These run during `next build` (static export)
// in Node — NOT in the browser — so we hit the PostgREST RPC endpoint directly
// with the public anon key rather than the browser supabase client (avoids its
// localStorage/session assumptions at build). The RPCs are SECURITY DEFINER and
// return only public-safe fields (see supabase migration 20260714162005 +
// docs/SEO_CONTENT_STRATEGY.md).

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

async function rpc<T>(fn: string, body: Record<string, unknown> = {}): Promise<T> {
  if (!SUPABASE_URL || !ANON_KEY) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL / ANON_KEY at build time.");
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    // force-cache (not no-store): a static export requires build-time fetches
    // to be cacheable, else the route is treated as dynamic and export fails.
    // The cache is per-build, so each `next build` still pulls fresh content.
    cache: "force-cache",
  });
  if (!res.ok) {
    throw new Error(`SEO rpc ${fn} failed: ${res.status} ${await res.text()}`);
  }
  return res.json() as Promise<T>;
}

// opinions arrive RANKED best-first (by head-to-head global_score); `score` is
// that 0–100 score (null until an opinion has been compared). Array index = rank.
export type SeoOpinion = { id: number; content: string; score: number | null };
export type SeoChat = {
  code: string;
  name: string;
  question: string | null; // null for open-floor chats (no seed question)
  opinions: SeoOpinion[];
};

/// Invite codes eligible for a static /opinions/<code> page (official public
/// chats with >=5 human opinions). Empty array is a valid result (no eligible
/// chats yet) — the route then generates nothing.
export async function getSeoIndex(): Promise<string[]> {
  try {
    const rows = await rpc<{ code: string; human_props: number }[]>("get_seo_index");
    return (rows ?? []).map((r) => r.code);
  } catch (e) {
    // A build shouldn't hard-fail because SEO content is unreachable; just skip.
    console.warn("[seo] get_seo_index failed, skipping SEO pages:", e);
    return [];
  }
}

/// Full public-safe content for one chat's SEO page. Returns null if the code
/// is not (or no longer) an eligible SEO chat.
export async function getSeoChat(code: string): Promise<SeoChat | null> {
  const data = await rpc<SeoChat | null>("get_seo_chat", { p_code: code });
  return data && data.code ? data : null;
}

// ── Per-thread (sub-thread) SEO pages ──────────────────────────────────────
// Each opinion's reply thread is its own topical page: /opinions/<code>/<node>,
// where <node> is the parent proposition's id. Powered by get_seo_node_index /
// get_seo_node (migration 20260716010000). Fails soft everywhere so a build
// never breaks — until the RPCs exist, the index is just empty (no node pages).

export type SeoNodeRef = {
  code: string;
  node: number;
  parent: string; // the opinion the thread hangs off — the link label
  replies: number;
};
export type SeoNode = {
  code: string;
  node: number;
  parent: string; // the opinion being discussed (the page's topic/headline)
  opinions: SeoOpinion[]; // its replies, ranked best-first
};

/// Every sub-thread eligible for a static page (human parent + >=2 human
/// replies). Empty array on any failure — the node route then generates nothing.
export async function getSeoNodeIndex(): Promise<SeoNodeRef[]> {
  try {
    const rows = await rpc<SeoNodeRef[]>("get_seo_node_index");
    return rows ?? [];
  } catch (e) {
    console.warn("[seo] get_seo_node_index failed, skipping node pages:", e);
    return [];
  }
}

/// The sub-threads under ONE chat (for the hub page's "threads" section).
export async function getSeoNodesForChat(code: string): Promise<SeoNodeRef[]> {
  const all = await getSeoNodeIndex();
  return all.filter((n) => n.code === code);
}

/// One sub-thread's content. Null if the code/node is not (or no longer)
/// eligible.
export async function getSeoNode(
  code: string,
  node: number,
): Promise<SeoNode | null> {
  try {
    const data = await rpc<SeoNode | null>("get_seo_node", {
      p_code: code,
      p_node: node,
    });
    return data && data.code ? data : null;
  } catch (e) {
    console.warn("[seo] get_seo_node failed:", e);
    return null;
  }
}
