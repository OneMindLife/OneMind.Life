import type { Metadata } from "next";
import { getSeoIndex } from "@/lib/onemind/seo";
import TreeChatClient from "./TreeChatClient";

// Chat codes are unknown at build time, so static export can't pre-render each
// /g/<code>. We export ONE shell (/g/_) and serve every real /g/<code> from it
// via a Firebase Hosting rewrite (same pattern as /c/**); the code is read from
// the URL client-side in TreeChatClient.
export function generateStaticParams() {
  return [{ code: "_" }];
}

// noindex (2026-07-25) — same reasoning as /c/<code>. This shell serves the
// archived tree chats; it's an app surface, and "/" is the only page we want
// in the index.
export const metadata: Metadata = {
  title: "OneMind — one chat, everyone's best thinking",
  description:
    "Drop your take anonymously, vote head-to-head, and watch the chat build itself out of the group's best ideas.",
  robots: { index: false, follow: false },
};

export default async function TreeChatPage() {
  // Build-time snapshot of codes that have a static /opinions/<code>/ page, so
  // the client can point each SEO-eligible chat's canonical at its content page
  // (and everything else at a param-stripped self-canonical). Fails soft to []
  // → all self-canonical, never a canonical to a page that doesn't exist.
  const seoCodes = await getSeoIndex();
  return <TreeChatClient seoCodes={seoCodes} />;
}
