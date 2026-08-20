import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Static export → Firebase Hosting (decision A, docs/wedge-spec/00-architecture.md).
  // Marketing/SEO pages are SSG (real crawlable HTML); the chat (/c/<code>) is
  // client-rendered. Per-chat dynamic routes that can't be pre-generated (unknown
  // codes) are served via a Firebase hosting rewrite to a client shell — see
  // wedge/README.md.
  // Static export ONLY for the production build. Next 16's `output:'export'`
  // makes dynamic routes strict (every param must be in generateStaticParams) —
  // which 500s `/c/<real-code>` in dev. So dev runs the full Next server (the
  // `[code]` route serves any code), while `next build` static-exports a `/c/_`
  // shell that Firebase rewrites onto every `/c/<code>` (README; code read
  // client-side from the URL).
  output: process.env.NODE_ENV === "production" ? "export" : undefined,
  // Static export can't use the Next image optimizer.
  images: { unoptimized: true },
  // Emit /route/index.html (cleaner static hosting paths).
  trailingSlash: true,
};

export default nextConfig;
