import type { Metadata } from "next";
import { privacyHtml } from "@/lib/legal";
import { AppShell, BrandRail } from "../components/ui";

export const metadata: Metadata = {
  title: "Privacy Policy — OneMind",
  description:
    "How OneMind collects, uses, and protects your data. We collect minimal data by design — no email or real name required, propositions are anonymous, and we never sell your data.",
  alternates: { canonical: "https://onemind.life/privacy" },
};

export default function PrivacyPage() {
  return (
    <AppShell>
      <BrandRail />
      <article
        className="legal"
        dangerouslySetInnerHTML={{ __html: privacyHtml() }}
      />
    </AppShell>
  );
}
