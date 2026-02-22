/**
 * Test: verifyClaims() — fact-checks Perplexity output against its citations
 *
 * Run: npx supabase functions serve agent-orchestrator
 * Then: deno run --allow-net supabase/functions/tests/verify-claims-test.ts
 *
 * This test simulates the r/CollectiveIntelligence hallucination to verify
 * the claim verification step would have caught it.
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://ccyuxrtrklgpkzcryzpj.supabase.co";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") || "";

// The actual Perplexity output from cycle 156 that contained hallucinations
const HALLUCINATED_ANSWER = `**r/CollectiveIntelligence**, **r/deliberative**, **r/IndieHackers**, **r/Entrepreneur**, **r/nolaw**, **r/Supabase**, and **r/FlutterDev** are the subreddits most aligned with OneMind's core features.

### Subreddits
| Subreddit | Alignment with OneMind |
|-----------|------------------------|
| **r/CollectiveIntelligence** | Directly matches consensus-building and group rating/proposing mechanics; users discuss algorithms for collective wisdom. |
| **r/deliberative** | Centers on deliberative democracy and structured group deliberation. |
| **r/IndieHackers** | Targets indie developers building and monetizing apps. |
| **r/Entrepreneur** | Broad maker community for bootstrapped SaaS/tools. |
| **r/nolaw** | Anonymous discussion forums with no logs/signup. |
| **r/Supabase** | Specific to Supabase users. |
| **r/FlutterDev** | Flutter developers. |`;

// The actual citations Perplexity provided (none are Reddit URLs!)
const CITATIONS = [
  "https://anymindgroup.com/blog/advertising-solution-richmedia-inaapp/",
  "https://www.onemindmartech.com/about/",
  "https://onemind.org/what-we-do/one-mind-accelerator/our-portfolio/",
  "https://onemind.org/what-we-do/one-mind-accelerator/",
  "https://onemindng.com",
  "https://www.businesswire.com/news/home/20260209994908/en/",
  "https://www.vivun.com/compare/vs-onemind",
  "https://pmc.ncbi.nlm.nih.gov/articles/PMC11701828/",
  "https://www.brandinginasia.com/anymind-group-rolls-out-gen-ai-functionality/",
];

async function testVerifyClaims() {
  console.log("=== verifyClaims Test ===\n");
  console.log("Input: Perplexity output with 7 subreddits (3 fake: r/CollectiveIntelligence, r/deliberative, r/nolaw)");
  console.log(`Citations: ${CITATIONS.length} URLs (NONE are reddit.com)\n`);

  // Call Gemini directly to simulate verifyClaims()
  const response = await fetch("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${GEMINI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gemini-2.0-flash",
      max_tokens: 4096,
      messages: [
        {
          role: "system",
          content: `You are a fact-checker. You will receive research results and a list of source URLs that were cited.

Your task: Rewrite the research results, REMOVING any specific claims that are NOT plausibly supported by the cited sources. This includes:
- Named entities (subreddits, organizations, communities, people) that no source URL corresponds to
- Statistics or numbers with no apparent source
- URLs or links not in the citations list
- Specific descriptions of communities/tools that aren't backed by any cited page

Rules:
- Keep claims that ARE supported by the cited URLs (e.g., if a reddit.com/r/XYZ URL is cited, that subreddit is verified)
- Keep general knowledge claims that don't need specific sourcing
- If a claim is removed, do NOT mention it was removed — just omit it
- Preserve the structure and formatting of the original
- If most claims are unsupported, return only what IS supported, even if brief
- Do NOT add new information — only filter existing claims`,
        },
        {
          role: "user",
          content: `RESEARCH RESULTS:
${HALLUCINATED_ANSWER}

CITED SOURCES:
${CITATIONS.map((url, i) => `${i + 1}. ${url}`).join("\n")}

Rewrite the research results keeping ONLY claims supported by the cited sources.`,
        },
      ],
    }),
  });

  const data = await response.json();
  const verified = data.choices?.[0]?.message?.content ?? "(empty)";

  console.log("--- VERIFIED OUTPUT ---");
  console.log(verified);
  console.log("\n--- ANALYSIS ---");

  // Check which subreddits survived
  const subreddits = ["CollectiveIntelligence", "deliberative", "IndieHackers", "Entrepreneur", "nolaw", "Supabase", "FlutterDev"];
  const fakes = ["CollectiveIntelligence", "deliberative", "nolaw"];
  const reals = ["IndieHackers", "Entrepreneur", "Supabase", "FlutterDev"];

  for (const sub of subreddits) {
    const present = verified.includes(sub);
    const isFake = fakes.includes(sub);
    const status = present
      ? (isFake ? "❌ STILL PRESENT (should have been removed)" : "⚠️ Present (real but not in citations)")
      : (isFake ? "✅ Correctly removed" : "⚠️ Removed (real but no citation backed it)");
    console.log(`  r/${sub}: ${status}`);
  }
}

testVerifyClaims().catch(console.error);
