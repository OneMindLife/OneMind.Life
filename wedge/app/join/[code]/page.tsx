import type { Metadata } from "next";
import ChatClient from "../../c/[code]/ChatClient";

// Legacy invite links use /join/<code> (the Flutter app shared these). New
// invites use /c/<code>, but old links are in the wild — serve them the same
// chat. One exported shell (/join/_) + a Firebase rewrite /join/** → it; the
// code is read from the URL in ChatClient (which matches /c/ OR /join/).
export function generateStaticParams() {
  return [{ code: "_" }];
}

// noindex (2026-07-25) — same reasoning as /c/<code>, which this shell mirrors.
export const metadata: Metadata = {
  robots: { index: false, follow: false },
};

export default function JoinPage() {
  return <ChatClient />;
}
