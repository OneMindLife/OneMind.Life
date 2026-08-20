// Renders a shareable image of the user's "chain" — the stack of ideas they
// descended through — as a portrait card that MIRRORS the on-screen stack
// (graphite ground, serif quotes, brass accent). The share artifact IS the UI,
// so a recipient understands OneMind before they even click. Pure client-side
// canvas; returns a PNG Blob (or null if canvas is unavailable).

const W = 1080;
const H = 1350;
const PAD = 72;
const BG = "#1a1613";
const CARD = "#211c18";
const LINE = "#332c25";
const BRASS = "#cda45e";
const INK = "#ece5d9";
const INK2 = "#8f857a";
const SERIF = "Georgia, 'Times New Roman', serif";
const SANS = "system-ui, -apple-system, Arial, sans-serif";

function roundRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
): void {
  const rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}

function wrap(
  ctx: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
): string[] {
  const words = text.replace(/\s+/g, " ").trim().split(" ");
  const lines: string[] = [];
  let line = "";
  for (const word of words) {
    const test = line ? `${line} ${word}` : word;
    if (ctx.measureText(test).width > maxWidth && line) {
      lines.push(line);
      line = word;
    } else {
      line = test;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function truncate(s: string, n: number): string {
  const t = s.replace(/\s+/g, " ").trim();
  return t.length <= n ? t : t.slice(0, n - 1).trimEnd() + "…";
}

export async function renderChainCard(
  quotes: { text: string; rank?: number | null; total?: number | null }[],
  stats?: { people: number; ideas: number; judgments: number } | null,
): Promise<Blob | null> {
  if (typeof document === "undefined") return null;
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;

  // Ground.
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, W, H);

  // Header.
  ctx.textBaseline = "alphabetic";
  ctx.fillStyle = BRASS;
  ctx.font = `700 52px ${SERIF}`;
  ctx.fillText("OneMind", PAD, PAD + 44);
  ctx.fillStyle = INK2;
  ctx.font = `400 25px ${SANS}`;
  ctx.fillText("where the best ideas win — not the loudest", PAD, PAD + 82);

  const bodyTop = PAD + 128;
  const bodyBottom = H - 104; // room for the footer
  const innerW = W - PAD * 2;
  const innerPad = 26;

  // Truncate; keep each quote's own-level rank alongside its text.
  const clean = quotes
    .map((q) => ({ ...q, text: truncate(q.text, 240) }))
    .filter((q) => q.text);
  let shown = clean.slice(0, 6);
  let fontSize = 34;
  const gap = 20;

  // Measure a card at a font size: wrapped text lines + total height (incl. an
  // optional top row for the "#N of M at its level" rank badge).
  const measure = (
    q: { text: string; rank?: number | null; total?: number | null },
    fs: number,
  ) => {
    const lineH = Math.round(fs * 1.34);
    ctx.font = `400 ${fs}px ${SERIF}`;
    const lines = wrap(ctx, `“${q.text}”`, innerW - innerPad * 2);
    const rankH = q.rank ? 30 : 0;
    return {
      lines,
      lineH,
      rankH,
      height: innerPad * 2 + rankH + lines.length * lineH,
    };
  };
  const totalHeight = (list: typeof shown, fs: number): number =>
    list.reduce((s, q) => s + measure(q, fs).height + gap, 0);

  // Shrink font, then drop trailing quotes, until it fits.
  for (;;) {
    if (totalHeight(shown, fontSize) <= bodyBottom - bodyTop) break;
    if (fontSize > 24) {
      fontSize -= 2;
    } else if (shown.length > 1) {
      shown = shown.slice(0, shown.length - 1);
      fontSize = 34;
    } else {
      break;
    }
  }

  // Draw the chain cards. Each shows the idea + its TRUE rank at its OWN level
  // (#N of M). The stack is a PATH — never claimed to be ranked against itself.
  ctx.textBaseline = "top";
  let y = bodyTop;
  shown.forEach((q) => {
    const { lines, lineH, rankH, height } = measure(q, fontSize);
    ctx.fillStyle = CARD;
    roundRect(ctx, PAD, y, innerW, height, 18);
    ctx.fill();
    ctx.strokeStyle = LINE;
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.fillStyle = BRASS;
    roundRect(ctx, PAD, y, 6, height, 3);
    ctx.fill();
    const tx = PAD + innerPad;
    if (q.rank) {
      ctx.fillStyle = BRASS;
      ctx.font = `700 18px ${SANS}`;
      ctx.fillText(
        `#${q.rank}${q.total ? ` of ${q.total}` : ""} at its level`,
        tx,
        y + innerPad,
      );
    }
    ctx.fillStyle = INK;
    ctx.font = `400 ${fontSize}px ${SERIF}`;
    lines.forEach((ln, li) =>
      ctx.fillText(ln, tx, y + innerPad + rankH + li * lineH),
    );
    y += height + gap;
  });
  ctx.textBaseline = "alphabetic";

  // Footer — honest scale as social proof (about the PLATFORM, not a claim that
  // the stack was ranked against itself). The header carries the positioning;
  // each card's "#N of M" carries the only real head-to-head claim.
  const fmt = (v: number) => v.toLocaleString("en-US");
  ctx.fillStyle = INK2;
  ctx.font = `400 26px ${SANS}`;
  ctx.fillText("onemind.life", PAD, H - 52);
  if (stats && stats.people > 0) {
    ctx.textAlign = "right";
    ctx.fillStyle = BRASS;
    ctx.font = `600 26px ${SANS}`;
    ctx.fillText(
      `${fmt(stats.people)} people · ${fmt(stats.judgments)} votes`,
      W - PAD,
      H - 52,
    );
    ctx.textAlign = "left";
  }

  return new Promise((resolve) =>
    canvas.toBlob((b) => resolve(b), "image/png", 0.92),
  );
}
