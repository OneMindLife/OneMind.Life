import type { Metadata } from "next";

// /create is the interactive app surface (the create flow, incl. /create?game=1
// where CTAs land) — app UI, not indexable marketing content. The page itself is
// a client component and so can't export `metadata`, so robots lives here.
export const metadata: Metadata = {
  robots: { index: false, follow: false },
};

export default function CreateLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
