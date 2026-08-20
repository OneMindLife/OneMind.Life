import type { Metadata } from "next";

// /home is a legacy redirect route (old Flutter deep links → /c/<code> or "/"),
// not content — keep it out of the index. The page is a client component and so
// can't export `metadata`, so robots lives here.
export const metadata: Metadata = {
  robots: { index: false, follow: false },
};

export default function HomeLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
