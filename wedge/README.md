# OneMind Quick-Chat Wedge (Next.js)

The cold-traffic quick-chat funnel, rebuilt in Next.js for native SEO + fast
load (decision **D38**). Reuses the existing Supabase backend **unchanged** —
this is a UI-only rebuild. The deep `/home` dashboard is **not** ported.

**Spec is the source of truth:** `../docs/wedge-spec/` (`00`-architecture is the
anchor; `01` routing, `02` screens, `03` state-machines, `04` data-contracts,
`05` acceptance criteria). If code and spec disagree, fix one deliberately.

## Status
Scaffold only (Next 16 App Router, TS, Tailwind, `@supabase/supabase-js`,
static export). Screens not built yet.

> ⚠️ This is **Next 16** — it has breaking changes vs. older Next. See
> `AGENTS.md`; consult `node_modules/next/dist/docs/` before writing app code.

## Setup
```bash
cp .env.local.example .env.local   # fill in the public Supabase URL + anon key
npm install
npm run dev                        # http://localhost:3000
npm run build                      # static export → ./out
```

## Hosting / rendering (decision A)
**Static export → Firebase Hosting** (`next.config.ts: output:'export'`). Same
host as the Flutter app. Marketing/SEO pages (`/`, `/<slug>`) are SSG = real
crawlable HTML (the SEO win, no `prerender.js` hack). The chat is client-rendered.

### The `/c/<code>` dynamic-route caveat (resolve before building the chat route)
`output: 'export'` can't pre-render dynamic routes with unknown params (chat codes
aren't known at build time). Plan: serve `/c/<code>` from a **single client shell**
via a **Firebase Hosting rewrite** (`"/c/**" → the exported /c shell`), and read
`<code>` from the URL client-side. (Alternative: a query param `/c?code=…`, but
the path form is what the spec wants for clean share links + scraper-safety.)
Decide the exact mechanism when implementing the chat route.

## URL architecture (spec `01`)
One durable URL per chat: **`/c/<code>`** (random invite code; **never** the
sequential `chat_id`). Opening it views **and** joins (auto-join for open chats,
request-to-join for approval-required, reopen for existing members). No separate
`/join` step. Routes: `/`, `/<seo-slug>`, `/create`, `/c/<code>`.

## Backend
All RPCs / realtime / RLS reused as-is (Supabase project `ccyuxrtrklgpkzcryzpj`).
Contracts catalogued in `../docs/wedge-spec/04-data-contracts.md`. pgtap suite
(in the parent repo) remains the backend's regression guard — unchanged.
