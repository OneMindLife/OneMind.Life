// Build-time loader for the legal docs. Single source of truth lives at the
// repo root (docs/legal/*.md) — the same files the Flutter app rendered. We read
// + convert to HTML at build (Node, SSG) so /privacy and /terms ship as real
// crawlable static pages after the wedge replaces Flutter on onemind.life.
import fs from "fs";
import path from "path";
import { marked } from "marked";

marked.setOptions({ gfm: true });

function render(file: string): string {
  const p = path.join(process.cwd(), "..", "docs", "legal", file);
  const md = fs.readFileSync(p, "utf8");
  return marked.parse(md, { async: false }) as string;
}

export function privacyHtml(): string {
  return render("PRIVACY_POLICY.md");
}

export function termsHtml(): string {
  return render("TERMS_OF_SERVICE.md");
}
