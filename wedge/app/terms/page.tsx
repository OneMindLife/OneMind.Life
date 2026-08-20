import type { Metadata } from "next";
import { termsHtml } from "@/lib/legal";
import { AppShell, BrandRail } from "../components/ui";

export const metadata: Metadata = {
  title: "Terms of Service — OneMind",
  description:
    "The terms governing your use of OneMind, the collective alignment platform. Free to use, anonymous by design, results are non-binding.",
  alternates: { canonical: "https://onemind.life/terms" },
};

export default function TermsPage() {
  return (
    <AppShell>
      <BrandRail />
      <article
        className="legal"
        dangerouslySetInnerHTML={{ __html: termsHtml() }}
      />
    </AppShell>
  );
}
