// Build-time loader for the SEO landing pages. Single source of truth lives at
// the repo root (tools/seo_pages.json) — also consumed by the Flutter prerender
// + generate_seo_pages.dart. We read it at build (Node, SSG) so the wedge's
// keyword landings stay in lockstep with that file. After editing the JSON,
// rebuild the wedge.
import fs from "fs";
import path from "path";

export type Faq = { q: string; a: string };
export type Block = { icon?: string; title: string; description: string };
export type SeoPage = {
  slug: string;
  topic: string;
  definition: string;
  title: string;
  description: string;
  ogTitle: string;
  ogDescription: string;
  heroHeadline: string;
  heroSubheadline: string;
  seedQuestions?: string[];
  toolIntent?: boolean;
  ctaLabel: string;
  problemHeadline: string;
  problemDescription: string;
  steps: Block[];
  features: Block[];
  proofLine: string;
  closingHeadline: string;
  closingSubheadline: string;
  faq: Faq[];
};

let cache: Record<string, Omit<SeoPage, "slug">> | null = null;

function load(): Record<string, Omit<SeoPage, "slug">> {
  if (cache) return cache;
  const p = path.join(process.cwd(), "..", "tools", "seo_pages.json");
  const raw = JSON.parse(fs.readFileSync(p, "utf8")) as Record<string, unknown>;
  delete raw._comment;
  cache = raw as Record<string, Omit<SeoPage, "slug">>;
  return cache;
}

export function allSeoSlugs(): string[] {
  return Object.keys(load());
}

export function getSeoPage(slug: string): SeoPage | null {
  const d = load()[slug];
  return d ? ({ slug, ...d } as SeoPage) : null;
}
