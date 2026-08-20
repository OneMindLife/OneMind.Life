import type { Metadata } from "next";
import ChatClient from "./ChatClient";

// Chat codes are unknown at build time, so static export can't pre-render each
// /c/<code>. We export ONE shell (/c/_) and serve every real /c/<code> from it
// via a Firebase Hosting rewrite (see wedge/README.md); the code is read from
// the URL client-side in ChatClient.
export function generateStaticParams() {
  return [{ code: "_" }];
}

// noindex (2026-07-25). The room is an app surface, not a search destination.
// Because every /c/<code> is served this ONE file, they'd otherwise all be
// byte-identical pages competing with each other and with "/" — verified: the
// prod HTML for /c/GLOBAL and /c/ZZZZZZ have the same md5. Deliberate product
// decision: "/" is the only page we want in the index.
export const metadata: Metadata = {
  robots: { index: false, follow: false },
};

export default function ChatPage() {
  return <ChatClient />;
}
