// Edge Function: agent-orchestrator
// Dispatcher + Worker pattern for 5 AI agent personas.
//
// DISPATCHER MODE (no persona_name): Called by DB trigger. Fires 5 independent
//   worker calls (one per persona), waits for all, retries failures once (~30-60s).
// WORKER MODE (persona_name present): Processes a single persona —
//   Gemini 2.0 Flash reasoning, API call. Each worker has its own 150s gateway window.
//
// Receives: { round_id, chat_id, cycle_id, phase, persona_name? }
//
// AUTH: verify_jwt = false. Accepts service role JWT from DB trigger via vault.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4.77.0";
import {
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";

// =============================================================================
// ENVIRONMENT & CLIENTS
// =============================================================================

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const tavilyApiKey = Deno.env.get("TAVILY_API_KEY") ?? "";

const openai = new OpenAI({
  apiKey: Deno.env.get("GEMINI_API_KEY") ?? "",
  baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
});

const supabase = createClient(supabaseUrl, supabaseServiceKey);

const MAX_CONTENT_LENGTH = 200;
const LOG_PREFIX = "[AGENT-ORCHESTRATOR]";
const LLM_TIMEOUT_MS = 30_000;      // 30s per Gemini call — typically responds in 1-5s
const TAVILY_TIMEOUT_MS = 15_000;   // 15s for Tavily search (raw results, no synthesis)
const TAVILY_MAX_RESULTS = 10;      // Max search results per Tavily call
const WORKER_WAIT_MS = 60_000;      // 60s max to wait for all workers (LLM ~5-15s)
const RESEARCH_BUDGET_MS = 120_000;  // 120s total research budget (leaves 30s for 150s gateway)
const RESEARCH_MIN_ITERATION_MS = 15_000; // 15s per iteration (Tavily + Gemini synthesis)
const RESEARCH_MAX_ITERATIONS = 5;   // Max search+synthesize cycles per research task
const RESEARCH_COMPLETENESS_THRESHOLD = 70; // Score 0-100 to consider research "complete"

// =============================================================================
// STRUCTURED LOGGING — writes to agent_logs table
// =============================================================================

interface LogEntry {
  chat_id?: number;
  cycle_id?: number;
  round_id?: number;
  persona_name?: string;
  event_type: string;
  level?: "debug" | "info" | "warn" | "error";
  phase?: "proposing" | "rating";
  message: string;
  duration_ms?: number;
  metadata?: Record<string, unknown>;
}

async function logAgent(entry: LogEntry): Promise<void> {
  try {
    await supabase.from("agent_logs").insert({
      chat_id: entry.chat_id ?? null,
      cycle_id: entry.cycle_id ?? null,
      round_id: entry.round_id ?? null,
      persona_name: entry.persona_name ?? null,
      event_type: entry.event_type,
      level: entry.level ?? "info",
      phase: entry.phase ?? null,
      message: entry.message,
      duration_ms: entry.duration_ms ?? null,
      metadata: entry.metadata ?? {},
    });
  } catch {
    // Never let logging failures break the main flow
    console.warn(`${LOG_PREFIX} Failed to write agent log: ${entry.message}`);
  }
}

// =============================================================================
// TYPE DEFINITIONS
// =============================================================================

interface Persona {
  id: number;
  name: string;
  display_name: string;
  system_prompt: string;
  user_id: string;
  participant_id: number;
}

interface ChatContext {
  name: string;
  initial_message: string | null;
  description: string | null;
  confirmation_rounds_required: number;
  enable_ai_participant: boolean;
  ai_propositions_count: number;
  enable_agents: boolean;
  proposing_agent_count: number;
  rating_agent_count: number;
  agent_instructions: string | null;
  agent_configs: Array<{ name: string; personality: string }> | null;
  translation_languages: string[];
}

// Default archetype templates assigned round-robin when personality is empty.
// Each optimizes for a different perspective, producing diverse evaluation.
const DEFAULT_ARCHETYPES = [
  "The Pragmatist — You evaluate feasibility, cost, and what can actually be implemented today. Rate highest when the path to execution is clear and achievable with current resources. Rate lowest when the idea requires unrealistic prerequisites.",
  "The Visionary — You push for the most ambitious, transformative approach possible. Rate highest when an idea has the potential to create outsized impact or fundamentally change the game. Rate lowest when an idea is incremental or plays it too safe.",
  "The Skeptic — You challenge assumptions, find weaknesses, and stress-test every idea. Rate highest when an idea survives your scrutiny and you cannot find a strong reason it fails. Rate lowest when you find clear evidence-backed reasons it will fail.",
  "The Advocate — You consider human impact, equity, and who benefits or suffers. Rate highest when an idea helps real people and creates genuine value. Rate lowest when an idea ignores human needs or creates negative externalities.",
  "The Analyst — You focus on evidence, data, and measurable outcomes. Rate highest when an idea has clear metrics for success and evidence supporting its approach. Rate lowest when claims are unsubstantiated or outcomes are unmeasurable.",
];

/**
 * Generates topic-specific agent personas using Gemini.
 * Each persona represents a fundamentally different stakeholder perspective
 * so that MOVDA consensus finds what balances all interests.
 * Returns [] on any failure (caller falls back to DEFAULT_ARCHETYPES).
 */
async function generateDynamicPersonas(
  chatContext: ChatContext,
  agentCount: number,
  chatId: number,
  logContext?: { chat_id?: number; cycle_id?: number; round_id?: number },
): Promise<Array<{ name: string; personality: string }>> {
  const topicParts: string[] = [];
  if (chatContext.name) topicParts.push(`Topic: ${chatContext.name}`);
  if (chatContext.description) topicParts.push(`Description: ${chatContext.description}`);
  if (chatContext.initial_message) topicParts.push(`Initial message: ${chatContext.initial_message}`);
  const topicContext = topicParts.join("\n");

  if (!topicContext.trim()) {
    console.warn(`${LOG_PREFIX} [PERSONA-GEN] No topic context available for chat ${chatId}, skipping generation`);
    return [];
  }

  const generationPrompt = `You are generating AI agent personas for a consensus-building platform.

Given the following topic, create exactly ${agentCount} agent personas. Each agent must optimize for a FUNDAMENTALLY DIFFERENT interest or perspective relevant to this specific topic. They should represent OPPOSING or ORTHOGONAL viewpoints so that consensus emerges from balancing all perspectives.

${topicContext}

Requirements:
- Each persona gets a short name starting with "The " (e.g., "The Customer Advocate", "The Risk Analyst")
- Each personality must be specific to the topic, not generic
- Format each personality as: "You evaluate ONE thing: [criterion]. Rate highest when [X]. Rate lowest when [Y]."
- Personalities should be 1-3 sentences

Respond with ONLY valid JSON in this exact format, no other text:
{"personas": [{"name": "The ...", "personality": "You evaluate ONE thing: ..."}, ...]}`;

  try {
    const startMs = Date.now();
    const response = await openai.chat.completions.create(
      {
        model: "gemini-2.5-flash",
        messages: [{ role: "user", content: generationPrompt }],
        temperature: 1.0,
      },
      { signal: AbortSignal.timeout(LLM_TIMEOUT_MS) },
    );

    let raw = response.choices?.[0]?.message?.content?.trim();
    if (!raw) throw new Error("Empty response from Gemini");

    // Strip markdown code fences if present (Gemini often wraps JSON in ```json ... ```)
    raw = raw.replace(/^```(?:json)?\s*\n?/i, "").replace(/\n?```\s*$/i, "").trim();

    const parsed = JSON.parse(raw);
    const personas: Array<{ name: string; personality: string }> = parsed.personas;

    if (!Array.isArray(personas) || personas.length !== agentCount) {
      throw new Error(`Expected ${agentCount} personas, got ${Array.isArray(personas) ? personas.length : 'non-array'}`);
    }
    for (const p of personas) {
      if (!p.name || !p.personality) {
        throw new Error(`Persona missing name or personality: ${JSON.stringify(p)}`);
      }
    }

    const durationMs = Date.now() - startMs;
    console.log(`${LOG_PREFIX} [PERSONA-GEN] Generated ${personas.length} personas for chat ${chatId} in ${durationMs}ms`);
    await logAgent({
      ...logContext,
      event_type: "generate_personas",
      message: `Generated ${personas.length} dynamic personas for chat ${chatId}`,
      duration_ms: durationMs,
      metadata: { personas: personas.map(p => p.name) },
    });

    return personas;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.warn(`${LOG_PREFIX} [PERSONA-GEN] Failed to generate personas for chat ${chatId}: ${msg}`);
    await logAgent({
      ...logContext,
      event_type: "generate_personas",
      level: "warn",
      message: `Dynamic persona generation failed, will use defaults: ${msg}`,
    });
    return [];
  }
}

interface ConsensusWinner {
  cycle_number: number;
  winning_content: string;
  round_count: number;
  task_result?: string;
  category?: string;
}

interface Proposition {
  id: number;
  content: string;
  participant_id: number | null;
  carried_from_id: number | null;
}

interface ResearchBrief {
  consensusContent: string;
  chatName: string;
  chatDescription: string;
  initialMessage: string | null;
  priorConsensus: Array<{
    cycleNumber: number;
    content: string;
    category?: string;
    taskResult?: string;
  }>;
}

interface ResearchResult {
  text: string;
  quality: {
    completenessScore: number;
    iterationsUsed: number;
    totalDurationMs: number;
    itemsRequested: number | null;
    itemsDelivered: number;
    stoppedReason: "complete" | "max_iterations" | "diminishing_returns" | "timeout" | "error";
  };
}

interface TavilySearchResult {
  title: string;
  url: string;
  content: string;
  score: number;
}

interface TavilyResponse {
  results: TavilySearchResult[];
  response_time: number;
}

// =============================================================================
// AUTH VALIDATION (same pattern as ai-proposer)
// =============================================================================

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    // base64url decode with proper padding
    let b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (b64.length % 4) b64 += "=";
    return JSON.parse(atob(b64));
  } catch {
    return null;
  }
}

function getProjectRef(): string | null {
  try {
    const url = new URL(supabaseUrl);
    const hostname = url.hostname;
    if (hostname.endsWith(".supabase.co")) {
      return hostname.replace(".supabase.co", "");
    }
    return null;
  } catch {
    return null;
  }
}

async function validateAuth(
  req: Request
): Promise<{ valid: boolean; error?: string }> {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  const isLocalDev =
    supabaseUrl.includes("localhost") ||
    supabaseUrl.includes("127.0.0.1") ||
    supabaseUrl.includes("kong:8000");
  if (isLocalDev) {
    return { valid: true };
  }

  if (token) {
    const payload = decodeJwtPayload(token);
    if (payload) {
      const role = payload.role as string | undefined;
      const iss = payload.iss as string | undefined;
      const projectRef = getProjectRef();
      if (role === "service_role" && iss === "supabase") {
        // Accept service_role JWTs with matching ref or no ref
        // (env var SUPABASE_SERVICE_ROLE_KEY may not include ref claim)
        const ref = payload.ref as string | undefined;
        if (!ref || ref === projectRef) {
          return { valid: true };
        }
      }
    }
  }

  if (token && supabaseAnonKey) {
    try {
      const userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const {
        data: { user },
        error,
      } = await userClient.auth.getUser();
      if (user && !error) {
        return { valid: true };
      }
    } catch {
      // Token validation failed
    }
  }

  return {
    valid: false,
    error: "Unauthorized - valid JWT or service role key required",
  };
}

// =============================================================================
// CONSENSUS TASK CLASSIFICATION & EXECUTION
// =============================================================================

type ConsensusClassification = "RESEARCH_TASK" | "HUMAN_TASK" | "THOUGHT";

async function classifyConsensus(content: string, logContext?: { chat_id?: number; cycle_id?: number }): Promise<ConsensusClassification> {
  const startMs = Date.now();
  try {
    const response = await openai.chat.completions.create(
      {
        model: "gemini-2.5-flash",
        max_tokens: 50,
        messages: [
          {
            role: "system",
            content: `Classify the following consensus statement into exactly one category:

RESEARCH_TASK — The group wants to find, list, look up, or answer a question about specific factual information that a web search can provide. This includes:
- Direct research commands: "List 5 DAOs with public emails", "Find the top 3 competitors"
- Research questions: "What specific DAOs can we contact?", "Which online courses offer free credits?"
- Any consensus where the logical next step is gathering real-world data before acting

HUMAN_TASK — The group agreed to do something that requires human action (write code, send emails, create designs, schedule meetings, make phone calls). A web search alone cannot complete this.

THOUGHT — The statement is a pure opinion, philosophical musing, or abstract discussion point that doesn't request any concrete action or factual lookup.

When in doubt between RESEARCH_TASK and THOUGHT, prefer RESEARCH_TASK — it's better to search and find nothing than to miss actionable information.

Output ONLY one word: RESEARCH_TASK, HUMAN_TASK, or THOUGHT. Nothing else.`,
          },
          { role: "user", content },
        ],
      },
      { signal: AbortSignal.timeout(10_000) },
    );

    const result = (response.choices?.[0]?.message?.content ?? "").trim().toUpperCase();
    const durationMs = Date.now() - startMs;
    if (result === "RESEARCH_TASK" || result === "HUMAN_TASK" || result === "THOUGHT") {
      console.log(`${LOG_PREFIX} Classified consensus as: ${result} — "${content.substring(0, 80)}"`);
      await logAgent({
        ...logContext,
        event_type: "classify",
        message: `Classified as ${result}: "${content.substring(0, 100)}"`,
        duration_ms: durationMs,
        metadata: { classification: result, consensus_content: content },
      });
      return result;
    }
    console.warn(`${LOG_PREFIX} Unexpected classification result: "${result}", defaulting to THOUGHT`);
    return "THOUGHT";
  } catch (error) {
    console.warn(`${LOG_PREFIX} Classification failed, defaulting to THOUGHT:`, error);
    await logAgent({
      ...logContext,
      event_type: "classify",
      level: "error",
      message: `Classification failed: ${error instanceof Error ? error.message : "Unknown"}`,
      duration_ms: Date.now() - startMs,
      metadata: { consensus_content: content },
    });
    return "THOUGHT";
  }
}

// =============================================================================
// RESEARCH HELPERS — callTavily (search), synthesizeFromSources (Gemini), evaluator
// =============================================================================

async function callTavily(
  query: string,
  maxResults: number = TAVILY_MAX_RESULTS,
  timeoutMs: number = TAVILY_TIMEOUT_MS,
): Promise<TavilyResponse> {
  const response = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      api_key: tavilyApiKey,
      query,
      search_depth: "advanced",
      include_answer: false,
      include_raw_content: false,
      max_results: maxResults,
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });

  if (!response.ok) {
    const errorBody = await response.text().catch(() => "");
    throw new Error(`Tavily ${response.status}: ${errorBody.substring(0, 300)}`);
  }

  const data = await response.json();
  return {
    results: (data.results ?? []) as TavilySearchResult[],
    response_time: data.response_time ?? 0,
  };
}

async function synthesizeFromSources(
  searchResults: TavilySearchResult[],
  originalRequest: string,
  brief: ResearchBrief,
  accumulatedText: string | null,
  logContext?: { chat_id?: number; cycle_id?: number; round_id?: number },
): Promise<string> {
  // Build numbered source block
  const sourceBlock = searchResults
    .map((r, i) => `[${i + 1}] "${r.title}" (${r.url}): ${r.content}`)
    .join("\n\n");

  // Build project context
  const contextParts: string[] = [];
  if (brief.chatName) contextParts.push(`PROJECT: ${brief.chatName}`);
  if (brief.chatDescription) contextParts.push(`DESCRIPTION: ${brief.chatDescription}`);
  if (brief.initialMessage) contextParts.push(`INITIAL PROMPT: ${brief.initialMessage}`);
  if (brief.priorConsensus.length > 0) {
    contextParts.push("CONVERSATION HISTORY (prior consensus decisions):");
    for (const c of brief.priorConsensus) {
      let line = `  Cycle ${c.cycleNumber}: ${c.content}`;
      if (c.category) line += ` [${c.category}]`;
      if (c.taskResult) line += ` (research completed: ${c.taskResult.length} chars of results)`;
      contextParts.push(line);
    }
  }
  const projectContext = contextParts.length > 0 ? contextParts.join("\n") + "\n\n" : "";

  const priorSection = accumulatedText
    ? `\nPRIOR RESEARCH (merge with new findings, remove duplicates):\n${accumulatedText.substring(0, 2000)}\n`
    : "";

  const startMs = Date.now();
  try {
    const response = await openai.chat.completions.create(
      {
        model: "gemini-2.5-flash",
        max_tokens: 4096,
        messages: [
          {
            role: "system",
            content: `You are a research synthesizer. You will receive numbered SEARCH RESULTS from a web search.

GROUNDING RULE: You may ONLY use facts, entities, names, URLs, statistics, and claims that appear in the SEARCH RESULTS below. Cite sources using [N] notation. Do NOT invent or hallucinate any entity, community, statistic, or URL not present in the search results.

If a search result mentions a subreddit, Discord server, organization, or tool — you may reference it. If it does NOT appear in any search result, you MUST NOT mention it.

Return concrete, actionable information: names, URLs, numbers, examples — not generic advice. Structure the output clearly with sections or numbered lists as appropriate.`,
          },
          {
            role: "user",
            content: `${projectContext}RESEARCH TASK: ${originalRequest}
${priorSection}
SEARCH RESULTS:
${sourceBlock}

Synthesize the search results into a comprehensive answer to the research task. Cite every factual claim with [N]. Only include information from the search results above.`,
          },
        ],
      },
      { signal: AbortSignal.timeout(LLM_TIMEOUT_MS) },
    );

    const synthesized = response.choices?.[0]?.message?.content ?? "";
    const durationMs = Date.now() - startMs;

    await logAgent({
      ...logContext,
      event_type: "synthesize",
      message: `Synthesized ${searchResults.length} sources → ${synthesized.length} chars`,
      duration_ms: durationMs,
      metadata: { source_count: searchResults.length, output_length: synthesized.length },
    });

    if (synthesized.length > 0) return synthesized;
  } catch (error) {
    console.warn(`${LOG_PREFIX} Synthesis failed, using raw results:`, error);
    await logAgent({
      ...logContext,
      event_type: "synthesize",
      level: "warn",
      message: `Synthesis failed: ${error instanceof Error ? error.message : "Unknown"}, using raw results`,
      duration_ms: Date.now() - startMs,
    });
  }

  // Fallback: formatted raw results
  return searchResults
    .map((r, i) => `${i + 1}. **${r.title}** (${r.url})\n   ${r.content}`)
    .join("\n\n");
}

async function evaluateCompleteness(
  results: string,
  originalRequest: string,
  logContext?: { chat_id?: number; cycle_id?: number; round_id?: number },
): Promise<{
  score: number;
  itemsRequested: number | null;
  itemsDelivered: number;
  isComplete: boolean;
  refinementQuery: string | null;
}> {
  try {
    const response = await openai.chat.completions.create(
      {
        model: "gemini-2.5-flash",
        max_tokens: 512,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: `You evaluate research completeness. Given an original request and research results, output JSON:
{
  "score": <0-100 completeness score>,
  "items_requested": <number explicitly requested, or null if no specific count>,
  "items_delivered": <count of concrete distinct items/results found>,
  "is_complete": <true if score >= ${RESEARCH_COMPLETENESS_THRESHOLD} OR items_delivered >= items_requested>,
  "refinement_query": <a DIFFERENT search query to find missing info, or null if complete>
}
Be strict: only count concrete, named, verifiable items. Generic advice doesn't count.`,
          },
          {
            role: "user",
            content: `ORIGINAL REQUEST:\n${originalRequest}\n\nRESEARCH RESULTS:\n${results.substring(0, 3000)}`,
          },
        ],
      },
      { signal: AbortSignal.timeout(10_000) },
    );

    const raw = response.choices?.[0]?.message?.content ?? "{}";
    const parsed = JSON.parse(raw);
    return {
      score: Math.max(0, Math.min(100, parsed.score ?? 50)),
      itemsRequested: parsed.items_requested ?? null,
      itemsDelivered: parsed.items_delivered ?? 0,
      isComplete: parsed.is_complete ?? true,
      refinementQuery: parsed.refinement_query ?? null,
    };
  } catch (error) {
    console.warn(`${LOG_PREFIX} Completeness evaluation failed, assuming complete:`, error);
    await logAgent({
      ...logContext,
      event_type: "research_eval_error",
      level: "warn",
      message: `Completeness eval failed: ${error instanceof Error ? error.message : "Unknown"}`,
    });
    return { score: 100, itemsRequested: null, itemsDelivered: 0, isComplete: true, refinementQuery: null };
  }
}

async function buildSearchQuery(brief: ResearchBrief): Promise<string> {
  // Build context summary for query generation
  const parts: string[] = [];
  if (brief.initialMessage) parts.push(`Project goal: ${brief.initialMessage}`);
  for (const c of brief.priorConsensus) {
    parts.push(`Prior decision: ${c.content}`);
  }
  parts.push(`Current task: ${brief.consensusContent}`);
  const context = parts.join("\n");

  try {
    const response = await openai.chat.completions.create(
      {
        model: "gemini-2.5-flash",
        max_tokens: 200,
        messages: [
          {
            role: "system",
            content: "Convert the following project context and task into a single, concise web search query (under 150 chars). Include the most specific keywords from ALL prior decisions — not just the current task. Output ONLY the search query, nothing else.",
          },
          { role: "user", content: context },
        ],
      },
      { signal: AbortSignal.timeout(10_000) },
    );
    const query = (response.choices?.[0]?.message?.content ?? "").trim();
    if (query.length > 10) {
      console.log(`${LOG_PREFIX} Built search query: "${query}"`);
      return query;
    }
  } catch (error) {
    console.warn(`${LOG_PREFIX} Query building failed, using consensus content:`, error);
  }
  return brief.consensusContent;
}

// =============================================================================
// ENHANCED RESEARCH — self-evaluating loop with refinement
// =============================================================================

async function executeResearchTaskEnhanced(
  brief: ResearchBrief,
  logContext?: { chat_id?: number; cycle_id?: number; round_id?: number },
): Promise<ResearchResult> {
  if (!tavilyApiKey) {
    console.warn(`${LOG_PREFIX} Tavily API key not configured, skipping research`);
    return {
      text: "(Research unavailable — no API key configured)",
      quality: { completenessScore: 0, iterationsUsed: 0, totalDurationMs: 0, itemsRequested: null, itemsDelivered: 0, stoppedReason: "error" },
    };
  }

  const budgetStart = Date.now();
  let accumulatedText = "";
  const allUrls: string[] = [];
  let lastScore = 0;
  let stoppedReason: ResearchResult["quality"]["stoppedReason"] = "max_iterations";
  let itemsRequested: number | null = null;
  let itemsDelivered = 0;
  let iteration = 0;
  let refinementQuery: string | null = null;

  // Build a context-aware search query from the full brief (initial message + prior consensus + task)
  const initialQuery = await buildSearchQuery(brief);

  for (iteration = 0; iteration < RESEARCH_MAX_ITERATIONS; iteration++) {
    const elapsed = Date.now() - budgetStart;
    const remaining = RESEARCH_BUDGET_MS - elapsed;

    // Check time budget
    if (remaining < RESEARCH_MIN_ITERATION_MS) {
      console.log(`${LOG_PREFIX} Research budget exhausted: ${elapsed}ms elapsed, ${remaining}ms remaining`);
      stoppedReason = "timeout";
      break;
    }

    const iterationStart = Date.now();
    const query = iteration === 0 ? initialQuery : (refinementQuery || initialQuery);
    // Use at most remaining budget minus 5s headroom, capped at TAVILY_TIMEOUT_MS
    const tavilyTimeout = Math.min(remaining - 5000, TAVILY_TIMEOUT_MS);

    try {
      // 1. Search with Tavily
      const tavilyResult = await callTavily(query, TAVILY_MAX_RESULTS, tavilyTimeout);
      if (!tavilyResult.results || tavilyResult.results.length === 0) {
        console.warn(`${LOG_PREFIX} Tavily returned no results on iteration ${iteration}`);
        if (iteration === 0) {
          stoppedReason = "error";
          accumulatedText = "(No search results found)";
          break;
        }
        stoppedReason = "diminishing_returns";
        break;
      }

      // Collect URLs for final citations
      for (const r of tavilyResult.results) {
        if (r.url && !allUrls.includes(r.url)) allUrls.push(r.url);
      }

      // 2. Synthesize from sources (Gemini) — handles merging via accumulatedText param
      accumulatedText = await synthesizeFromSources(
        tavilyResult.results,
        brief.consensusContent,
        brief,
        accumulatedText || null,
        logContext,
      );

      // 3. Evaluate completeness
      const evaluation = await evaluateCompleteness(accumulatedText, brief.consensusContent, logContext);
      const iterationDuration = Date.now() - iterationStart;

      await logAgent({
        ...logContext,
        event_type: "research_iteration",
        message: `Iteration ${iteration}: score=${evaluation.score}, items=${evaluation.itemsDelivered}/${evaluation.itemsRequested ?? "?"}, ${iterationDuration}ms`,
        duration_ms: iterationDuration,
        metadata: {
          iteration,
          score: evaluation.score,
          items_requested: evaluation.itemsRequested,
          items_delivered: evaluation.itemsDelivered,
          is_complete: evaluation.isComplete,
          refinement_query: evaluation.refinementQuery,
          result_length: accumulatedText.length,
          source_count: tavilyResult.results.length,
          tavily_response_time: tavilyResult.response_time,
          url_count: allUrls.length,
        },
      });

      itemsRequested = evaluation.itemsRequested;
      itemsDelivered = evaluation.itemsDelivered;

      // 4. Check if complete
      if (evaluation.isComplete) {
        stoppedReason = "complete";
        lastScore = evaluation.score;
        break;
      }

      // 5. Check diminishing returns
      if (iteration > 0 && evaluation.score <= lastScore + 5) {
        console.log(`${LOG_PREFIX} Diminishing returns: score ${lastScore} → ${evaluation.score}`);
        stoppedReason = "diminishing_returns";
        lastScore = evaluation.score;
        break;
      }

      lastScore = evaluation.score;
      refinementQuery = evaluation.refinementQuery;
    } catch (error) {
      console.warn(`${LOG_PREFIX} Research iteration ${iteration} failed:`, error);
      await logAgent({
        ...logContext,
        event_type: "research_iteration",
        level: "error",
        message: `Iteration ${iteration} error: ${error instanceof Error ? error.message : "Unknown"}`,
        duration_ms: Date.now() - iterationStart,
      });

      if (iteration === 0) {
        stoppedReason = "error";
        accumulatedText = "(Research failed)";
        break;
      }
      // On later iterations, use what we have
      stoppedReason = "error";
      break;
    }
  }

  // Build final result with source URLs
  let finalText = accumulatedText.substring(0, 4000);
  if (allUrls.length > 0) {
    finalText += "\n\nSources:";
    for (const url of allUrls.slice(0, 15)) {
      finalText += `\n- ${url}`;
    }
  }

  const totalDuration = Date.now() - budgetStart;
  console.log(`${LOG_PREFIX} Research complete: ${iteration + 1} iterations, score=${lastScore}, ${finalText.length} chars, ${totalDuration}ms, stopped=${stoppedReason}`);

  await logAgent({
    ...logContext,
    event_type: "research_complete",
    message: `Research complete: ${iteration + 1} iterations, score=${lastScore}, ${finalText.length} chars, stopped=${stoppedReason}`,
    duration_ms: totalDuration,
    metadata: {
      iterations_used: iteration + 1,
      completeness_score: lastScore,
      items_requested: itemsRequested,
      items_delivered: itemsDelivered,
      stopped_reason: stoppedReason,
      result_length: finalText.length,
      source_url_count: allUrls.length,
    },
  });

  return {
    text: finalText,
    quality: {
      completenessScore: lastScore,
      iterationsUsed: iteration + 1,
      totalDurationMs: totalDuration,
      itemsRequested,
      itemsDelivered,
      stoppedReason,
    },
  };
}

// Thin wrapper — preserves old signature for backward compatibility
async function executeResearchTask(
  content: string,
  chatDescription: string,
  logContext?: { chat_id?: number; cycle_id?: number; round_id?: number },
): Promise<string> {
  const brief: ResearchBrief = {
    consensusContent: content,
    chatName: "",
    chatDescription: chatDescription || "",
    initialMessage: null,
    priorConsensus: [],
  };
  const result = await executeResearchTaskEnhanced(brief, logContext);
  return result.text;
}

async function fetchPreviousConsensus(
  chatId: number,
  currentCycleId: number,
): Promise<{ cycle_id: number; winning_content: string; task_result: string | null; category: string | null } | null> {
  const { data: prevCycle, error } = await supabase
    .from("cycles")
    .select("id, winning_proposition_id, task_result, category")
    .eq("chat_id", chatId)
    .not("winning_proposition_id", "is", null)
    .neq("id", currentCycleId)
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error || !prevCycle) return null;

  const { data: prop } = await supabase
    .from("propositions")
    .select("content")
    .eq("id", prevCycle.winning_proposition_id)
    .single();

  if (!prop) return null;

  return {
    cycle_id: prevCycle.id,
    winning_content: prop.content,
    task_result: prevCycle.task_result,
    category: prevCycle.category,
  };
}

// =============================================================================
// CONTEXT FETCHING
// =============================================================================

async function fetchChatContext(chatId: number): Promise<ChatContext> {
  const { data, error } = await supabase
    .from("chats")
    .select("name, initial_message, description, confirmation_rounds_required, enable_agents, proposing_agent_count, rating_agent_count, agent_instructions, agent_configs, translation_languages")
    .eq("id", chatId)
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to fetch chat: ${error?.message || "Not found"}`
    );
  }
  return data as ChatContext;
}

async function fetchConsensusHistory(
  chatId: number,
  cycleId: number
): Promise<ConsensusWinner[]> {
  const { data: completedCycles, error } = await supabase
    .from("cycles")
    .select("id, winning_proposition_id, task_result, category")
    .eq("chat_id", chatId)
    .not("winning_proposition_id", "is", null)
    .neq("id", cycleId) // Exclude current cycle
    .order("id", { ascending: true });

  if (error) {
    throw new Error(`Failed to fetch consensus history: ${error.message}`);
  }

  const history: ConsensusWinner[] = [];
  for (const [index, cycle] of (completedCycles || []).entries()) {
    const { data: prop } = await supabase
      .from("propositions")
      .select("content")
      .eq("id", cycle.winning_proposition_id)
      .single();

    const { data: rounds } = await supabase
      .from("rounds")
      .select("id")
      .eq("cycle_id", cycle.id);

    history.push({
      cycle_number: index + 1,
      winning_content: prop?.content || "Unknown",
      round_count: rounds?.length || 0,
      task_result: cycle.task_result || undefined,
      category: cycle.category || undefined,
    });
  }

  return history;
}

async function fetchCarriedPropositions(
  roundId: number
): Promise<Proposition[]> {
  const { data, error } = await supabase
    .from("propositions")
    .select("id, content, participant_id")
    .eq("round_id", roundId)
    .not("carried_from_id", "is", null);

  if (error) {
    throw new Error(
      `Failed to fetch carried propositions: ${error.message}`
    );
  }
  return (data || []) as Proposition[];
}

async function fetchAllowedCategories(chatId: number): Promise<string[]> {
  const { data, error } = await supabase.rpc("get_chat_allowed_categories", { p_chat_id: chatId });
  if (error) {
    console.warn(`${LOG_PREFIX} Failed to fetch allowed categories: ${error.message}, defaulting to all`);
    return ["question", "thought", "human_task", "research_task"];
  }
  return (data as string[]) || ["question", "thought", "human_task", "research_task"];
}

async function fetchAllPropositions(roundId: number): Promise<Proposition[]> {
  const { data, error } = await supabase
    .from("propositions")
    .select("id, content, participant_id, carried_from_id")
    .eq("round_id", roundId);

  if (error) {
    throw new Error(`Failed to fetch propositions: ${error.message}`);
  }
  return (data || []) as Proposition[];
}

async function fetchActivePersonas(chatId: number): Promise<Persona[]> {
  // Get all active personas that are participants in this chat
  const { data, error } = await supabase
    .from("agent_personas")
    .select("id, name, display_name, system_prompt, user_id")
    .eq("is_active", true);

  if (error) {
    throw new Error(`Failed to fetch personas: ${error.message}`);
  }

  if (!data || data.length === 0) return [];

  // For each persona, find their participant_id in this chat
  const personas: Persona[] = [];
  for (const p of data) {
    const { data: participant } = await supabase
      .from("participants")
      .select("id")
      .eq("chat_id", chatId)
      .eq("user_id", p.user_id)
      .eq("status", "active")
      .single();

    if (participant) {
      personas.push({
        ...p,
        participant_id: participant.id,
      });
    }
  }

  return personas;
}

// =============================================================================
// API KEY FETCHING — Retrieve persona API keys from vault
// =============================================================================

async function fetchPersonaApiKeys(): Promise<Map<string, string>> {
  const { data, error } = await supabase.rpc("get_persona_api_keys");
  if (error) {
    throw new Error(`Failed to fetch persona API keys: ${error.message}`);
  }
  const keyMap = new Map<string, string>();
  for (const row of (data || []) as { persona_name: string; api_key: string }[]) {
    keyMap.set(row.persona_name, row.api_key);
  }
  if (keyMap.size === 0) {
    throw new Error("No persona API keys found in vault — run the register_persona_api_keys migration");
  }
  return keyMap;
}

// =============================================================================
// AGENT API HELPERS — Call agent-propose and agent-rate via HTTP
// =============================================================================

async function callAgentPropose(
  chatId: number,
  content: string,
  apiKey: string,
  category?: string,
): Promise<{ success: boolean; duplicate?: boolean; proposition_id?: number; propositions_remaining?: number }> {
  const url = `${supabaseUrl}/functions/v1/agent-propose`;
  const body: Record<string, unknown> = { chat_id: chatId, content };
  if (category) body.category = category;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  const responseBody = await response.json().catch(() => ({}));

  if (!response.ok) {
    const errorCode = responseBody?.code || "";
    // Graceful cases: phase moved on, already at limit
    if (errorCode === "LIMIT_REACHED" || errorCode === "WRONG_PHASE" || errorCode === "PHASE_ENDED") {
      return { success: true };
    }
    if (response.status === 409) {
      return { success: false, duplicate: true }; // Caller should retry with different content
    }
    throw new Error(
      `agent-propose failed (${response.status} ${errorCode}): ${responseBody?.error || "Unknown"}`
    );
  }

  return responseBody;
}

async function callAgentRate(
  chatId: number,
  ratings: Record<string, number>,
  apiKey: string,
): Promise<{ success: boolean; rated_count?: number; total_to_rate?: number; is_complete?: boolean }> {
  const url = `${supabaseUrl}/functions/v1/agent-rate`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ chat_id: chatId, ratings }),
  });

  const body = await response.json().catch(() => ({}));

  if (!response.ok) {
    const errorCode = body?.code || "";
    // Graceful cases: phase moved on
    if (errorCode === "WRONG_PHASE" || errorCode === "PHASE_ENDED") {
      return { success: true }; // Treat as no-op success
    }
    throw new Error(
      `agent-rate failed (${response.status} ${errorCode}): ${body?.error || "Unknown"}`
    );
  }

  return body;
}

// =============================================================================
// AGENT PERSONALITY RESOLUTION — Build effective system prompt for a persona
// =============================================================================

/**
 * Resolves the effective personality for a persona based on chat config.
 * Priority: per-agent config personality > persona's DB system_prompt > default archetype
 * Shared instructions are always appended if present.
 */
function resolvePersonality(
  persona: Persona,
  chatContext: ChatContext,
  allPersonas: Persona[],
): string {
  const agentIndex = allPersonas.indexOf(persona);
  const perAgentConfig = chatContext.agent_configs?.[agentIndex];

  // Determine base personality
  let personality: string;
  if (perAgentConfig?.personality) {
    // User specified a personality for this agent
    personality = perAgentConfig.personality;
  } else if (persona.system_prompt) {
    // Use the persona's DB-stored system prompt
    personality = persona.system_prompt;
  } else {
    // Fallback to default archetype template (round-robin)
    personality = DEFAULT_ARCHETYPES[agentIndex % DEFAULT_ARCHETYPES.length];
  }

  // Append shared instructions if present
  if (chatContext.agent_instructions) {
    personality += `\n\nADDITIONAL INSTRUCTIONS: ${chatContext.agent_instructions}`;
  }

  return personality;
}

/**
 * Resolves the effective display name for a persona based on chat config.
 */
function resolveDisplayName(
  persona: Persona,
  chatContext: ChatContext,
  allPersonas: Persona[],
): string {
  const agentIndex = allPersonas.indexOf(persona);
  const perAgentConfig = chatContext.agent_configs?.[agentIndex];
  return perAgentConfig?.name || persona.display_name;
}

// =============================================================================
// PROPOSING PHASE — Each persona generates 1 proposition
// =============================================================================

async function handleProposing(
  persona: Persona,
  chatContext: ChatContext,
  consensusHistory: ConsensusWinner[],
  carriedPropositions: Proposition[],
  roundId: number,
  chatId: number,
  apiKey: string,
  allowedCategories?: string[],
  allPersonas?: Persona[],
): Promise<void> {
  // Check idempotency FIRST — skip if this persona already proposed this round
  const { data: existing } = await supabase
    .from("propositions")
    .select("id")
    .eq("round_id", roundId)
    .eq("participant_id", persona.participant_id)
    .is("carried_from_id", null);

  if (existing && existing.length > 0) {
    console.log(
      `${LOG_PREFIX} [${persona.name}] Already proposed in round ${roundId}, skipping`
    );
    return;
  }

  // --- Build the proposing prompt ---
  const today = new Date().toISOString().split("T")[0];
  const effectivePersonas = allPersonas || [persona];
  const effectivePersonality = resolvePersonality(persona, chatContext, effectivePersonas);
  const effectiveName = resolveDisplayName(persona, chatContext, effectivePersonas);
  const systemPrompt = `CONTEXT: You are participating in OneMind (onemind.life), a collective consensus platform where humans and AI agents propose ideas and rate them on a 0-100 grid. The best ideas must win multiple consecutive rounds to reach consensus. All propositions are anonymous — judge purely on merit. You are one of several AI agents participating alongside humans; this human-AI collaboration is a core feature of the platform.

TODAY'S DATE: ${today}. Ensure any events, deadlines, or timeframes you reference are current or future — not in the past.

You are ${effectiveName}. ${effectivePersonality}`;

  // Language compliance: inject language requirement based on chat's configured languages
  const proposeLangs = chatContext.translation_languages || ["en"];
  const proposePrimaryLang = proposeLangs[0];
  const proposeLangNames: Record<string, string> = { en: "English", es: "Spanish", pt: "Portuguese", fr: "French", de: "German" };
  const proposeLangInstruction = proposeLangs.length === 1
    ? `\n\nLANGUAGE REQUIREMENT: This chat operates in ${proposeLangNames[proposePrimaryLang] || proposePrimaryLang}. You MUST write your proposition in ${proposeLangNames[proposePrimaryLang] || proposePrimaryLang}. Do not use any other language.`
    : `\n\nLANGUAGE REQUIREMENT: This chat operates in ${proposeLangs.map(l => proposeLangNames[l] || l).join(", ")}. You MUST write your proposition in ${proposeLangNames[proposePrimaryLang] || proposePrimaryLang}. Auto-translation handles other languages.`;
  const fullProposingSystemPrompt = systemPrompt + proposeLangInstruction;

  const confirmRounds = chatContext.confirmation_rounds_required;

  let contextBlock = `TOPIC: ${chatContext.name}`;
  if (chatContext.description) {
    contextBlock += `\nDescription: ${chatContext.description}`;
  }

  contextBlock += `\n\nHOW CONSENSUS WORKS:
This is a multi-round consensus process. A proposition must win ${confirmRounds} consecutive round${confirmRounds > 1 ? "s" : ""} to achieve consensus. The winner of each round is carried forward to compete again in the next round. If it wins again, it becomes the group's agreed direction for this cycle. Then a new cycle begins.`;

  // Conversation history: initial message first, then cycle winners
  contextBlock += `\n\nCONVERSATION HISTORY (the group's agreed directions so far):`;
  if (chatContext.initial_message) {
    contextBlock += `\n1. [Opening prompt]: "${chatContext.initial_message}"`;
  }
  if (consensusHistory.length > 0) {
    for (const w of consensusHistory) {
      const num = chatContext.initial_message ? w.cycle_number + 1 : w.cycle_number;
      const catLabel = w.category ? ` — ${w.category}` : "";
      contextBlock += `\n${num}. [Consensus #${w.cycle_number}${catLabel}] (won ${w.round_count} rounds): "${w.winning_content}"`;
      if (w.task_result) {
        contextBlock += `\n   → Research results: ${w.task_result}`;
      }
    }
  }
  if (!chatContext.initial_message && consensusHistory.length === 0) {
    contextBlock += `\n(No consensus reached yet — this is the first cycle)`;
  }

  if (carriedPropositions.length > 0) {
    contextBlock += `\n\nCURRENT FRONT-RUNNER (won the previous round — reaches consensus if it wins again):`;
    for (const p of carriedPropositions) {
      contextBlock += `\n> "${p.content}"`;
    }
    contextBlock += `\nNOTE: Your proposition must make sense as a standalone entry in the consensus chain. The front-runner may or may not reach consensus, so do not reference it directly — a reader of the final conversation won't see it unless it wins.`;
  }

  // Category-aware format instruction
  const categoryDescriptions: Record<string, string> = {
    question: "A question that explores, asks 'how?', 'why?', 'what specifically?'. MUST end with '?'.",
    thought: "A concrete statement, idea, or actionable answer. Must NOT end with '?'.",
    human_task: "A task that ONLY a human can physically do — writing code, sending emails, making phone calls, recording videos, deploying software, attending meetings. If a web search could accomplish it, use research_task instead.",
    research_task: "A task that can be answered by searching the web — finding lists, looking up facts, discovering communities, comparing options, gathering data. Use this whenever the answer exists online, even if phrased as 'create a list' or 'find X'.",
  };

  const categoryExamples: Record<string, string> = {
    question: "[question] What specific DAOs should we contact first?",
    thought: "[thought] We should focus on indie hacker communities first since they're the most aligned audience.",
    human_task: "[human_task] Record a 1-minute demo video showing OneMind reaching consensus on a sample topic.",
    research_task: "[research_task] Find 10 online communities (subreddits, Discord servers) focused on collective decision-making tools.",
  };

  let formatInstruction: string;
  if (allowedCategories && allowedCategories.length > 0) {
    const allowed = allowedCategories
      .filter(c => categoryDescriptions[c])
      .map(c => `- ${c}: ${categoryDescriptions[c]}`)
      .join("\n");

    const examples = allowedCategories
      .filter(c => categoryExamples[c])
      .map(c => `Example: ${categoryExamples[c]}`)
      .join("\n");

    formatInstruction = `CATEGORY RULE: You MUST classify your proposition as EXACTLY one of these types (NO other categories are valid):
${allowed}

Output format: [category] your proposition text
${examples}`;
  } else {
    // Legacy fallback: Q/A alternation
    const lastMessage = consensusHistory.length > 0
      ? consensusHistory[consensusHistory.length - 1].winning_content
      : (chatContext.initial_message || "");
    const lastMessageIsQuestion = lastMessage.trim().endsWith("?");
    const mustBeQuestion = !lastMessageIsQuestion;

    formatInstruction = mustBeQuestion
      ? `FORMAT RULE: The previous consensus was a STATEMENT/ANSWER. You MUST submit a QUESTION that digs deeper into that answer — asking "how?", "why?", "what specifically?", or challenging an assumption. Your proposition MUST end with "?".`
      : `FORMAT RULE: The previous message was a QUESTION. You MUST submit a concrete, actionable ANSWER to that question. Do NOT submit another question. Your proposition must NOT end with "?".`;
  }

  const userPrompt = `${contextBlock}

${formatInstruction}

ACCURACY RULE: Do NOT invent facts, statistics, or claims. Base your proposition only on what you know to be true, the conversation history, and any research results shown above. Never claim OneMind has features it doesn't have.

TASK: Generate exactly 1 proposition (max ${MAX_CONTENT_LENGTH} chars) that naturally advances the CONVERSATION HISTORY above. Read the consensus chain from top to bottom like a chain of thought, then propose the logical next step. Your proposition must score highest on YOUR criterion. Ignore the front-runner — just follow where the conversation chain leads. Output ONLY the proposition text, nothing else.`;

  const MAX_RETRIES = 3;
  let content: string | null = null;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const retryNote =
        attempt > 0
          ? `\n\n⚠️ STRICT: Your previous attempt was ${content?.length ?? "?"} chars. MUST be under ${MAX_CONTENT_LENGTH} chars. Aim for ~150 chars.`
          : "";

      const response = await openai.chat.completions.create(
        {
          model: "gemini-2.5-flash",
          max_tokens: 8192,
          messages: [
            { role: "system", content: fullProposingSystemPrompt },
            { role: "user", content: userPrompt + retryNote },
          ],
        },
        { signal: AbortSignal.timeout(LLM_TIMEOUT_MS) },
      );

      content = (response.choices[0]?.message?.content ?? "").trim();

      // Strip markdown code fences if present
      if (content.startsWith("```")) {
        content = content.replace(/^```\w*\n?/, "").replace(/\n?```$/, "").trim();
      }
      // Strip surrounding quotes
      if (
        (content.startsWith('"') && content.endsWith('"')) ||
        (content.startsWith("'") && content.endsWith("'"))
      ) {
        content = content.slice(1, -1).trim();
      }

      if (content.length === 0) {
        throw new Error("Empty response");
      }
      if (content.length > MAX_CONTENT_LENGTH) {
        throw new Error(
          `Too long: ${content.length} chars (max ${MAX_CONTENT_LENGTH})`
        );
      }

      break; // success
    } catch (error) {
      console.warn(
        `${LOG_PREFIX} [${persona.name}] Proposing attempt ${attempt + 1} failed:`,
        error
      );
      // Don't retry timeout/abort errors — fail fast
      if (error instanceof Error && (error.name === "AbortError" || error.message === "Request was aborted." || error.message?.includes("timed out"))) {
        throw new Error(`LLM timeout after ${LLM_TIMEOUT_MS / 1000}s`);
      }
      if (attempt === MAX_RETRIES - 1) {
        throw new Error(
          `Failed to generate proposition after ${MAX_RETRIES} attempts: ${error instanceof Error ? error.message : "Unknown"}`
        );
      }
      await new Promise((r) => setTimeout(r, 1000 * Math.pow(2, attempt)));
    }
  }

  // Duplicate-aware submission loop: if proposition is a duplicate, regenerate up to 3 times.
  // If all attempts produce duplicates, auto-skip so early advance isn't blocked.
  const DUPLICATE_MAX_RETRIES = 3;
  const rejectedContents: string[] = [];

  for (let dupAttempt = 0; dupAttempt <= DUPLICATE_MAX_RETRIES; dupAttempt++) {
    // On retry, regenerate content with hint to avoid previous duplicates
    if (dupAttempt > 0) {
      console.log(`${LOG_PREFIX} [${persona.name}] Duplicate detected, regenerating (attempt ${dupAttempt + 1}/${DUPLICATE_MAX_RETRIES + 1})`);
      const avoidList = rejectedContents.map((c, i) => `${i + 1}. "${c}"`).join("\n");
      const dedupNote = `\n\nIMPORTANT: Your previous proposition was rejected as a duplicate. You MUST propose something substantially different. Do NOT rephrase the same idea.\nAvoid these rejected propositions:\n${avoidList}`;

      // Re-run LLM generation with dedup hint
      content = null;
      for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
          const response = await openai.chat.completions.create(
            {
              model: "gemini-2.5-flash",
              max_tokens: 8192,
              messages: [
                { role: "system", content: fullProposingSystemPrompt },
                { role: "user", content: userPrompt + dedupNote },
              ],
            },
            { signal: AbortSignal.timeout(LLM_TIMEOUT_MS) },
          );
          content = (response.choices[0]?.message?.content ?? "").trim();
          if (content.startsWith("```")) {
            content = content.replace(/^```\w*\n?/, "").replace(/\n?```$/, "").trim();
          }
          if ((content.startsWith('"') && content.endsWith('"')) || (content.startsWith("'") && content.endsWith("'"))) {
            content = content.slice(1, -1).trim();
          }
          if (content.length === 0) throw new Error("Empty response");
          if (content.length > MAX_CONTENT_LENGTH) throw new Error(`Too long: ${content.length} chars`);
          break;
        } catch (error) {
          if (error instanceof Error && (error.name === "AbortError" || error.message === "Request was aborted." || error.message?.includes("timed out"))) {
            throw new Error(`LLM timeout after ${LLM_TIMEOUT_MS / 1000}s`);
          }
          if (attempt === MAX_RETRIES - 1) throw error;
          await new Promise((r) => setTimeout(r, 1000 * Math.pow(2, attempt)));
        }
      }
    }

    // Extract [category] prefix from LLM output if present
    const ALL_CATEGORIES = ["question", "thought", "human_task", "research_task", "human_task_result", "research_task_result"];
    let category: string | undefined;
    if (allowedCategories && allowedCategories.length > 0) {
      const catMatch = content!.match(/^\[(\w+)\]\s*/);
      if (catMatch) {
        content = content!.replace(/^\[\w+\]\s*/, "");
        if (ALL_CATEGORIES.includes(catMatch[1]) && allowedCategories.includes(catMatch[1])) {
          category = catMatch[1];
        }
      }
      if (!category) {
        category = content!.trim().endsWith("?") ? "question" : allowedCategories[0];
      }
    }

    // Submit via Agent API (validates phase, sanitizes content, detects duplicates)
    const result = await callAgentPropose(chatId, content!, apiKey, category);

    if (result.duplicate) {
      rejectedContents.push(content!);
      await logAgent({
        chat_id: chatId, round_id: roundId, persona_name: persona.name, phase: "proposing",
        event_type: "propose_duplicate",
        message: `Duplicate rejected (attempt ${dupAttempt + 1}): "${content!.substring(0, 60)}..."`,
      });

      if (dupAttempt === DUPLICATE_MAX_RETRIES) {
        // All retries exhausted — auto-skip so early advance isn't blocked
        console.log(`${LOG_PREFIX} [${persona.name}] All ${DUPLICATE_MAX_RETRIES + 1} attempts produced duplicates, auto-skipping`);
        await supabase.from("round_skips").insert({
          round_id: roundId,
          participant_id: persona.participant_id,
        });
        await logAgent({
          chat_id: chatId, round_id: roundId, persona_name: persona.name, phase: "proposing",
          event_type: "propose_auto_skip",
          message: `Auto-skipped after ${DUPLICATE_MAX_RETRIES + 1} duplicate rejections`,
        });
        return;
      }
      continue;
    }

    // Success — proposition was accepted
    console.log(
      `${LOG_PREFIX} [${persona.name}] Proposed via API (${content!.length} chars, category: ${category ?? "none"}, id: ${result.proposition_id ?? "n/a"}, remaining: ${result.propositions_remaining ?? "n/a"}): "${content!.substring(0, 60)}..."`
    );
    await logAgent({
      chat_id: chatId, round_id: roundId, persona_name: persona.name, phase: "proposing",
      event_type: "propose_content",
      message: content!,
      metadata: { proposition_id: result.proposition_id, content_length: content!.length, category },
    });
    return;
  }
}

// =============================================================================
// RATING PHASE — Each persona rates all propositions (except own)
// =============================================================================

async function handleRating(
  persona: Persona,
  chatContext: ChatContext,
  consensusHistory: ConsensusWinner[],
  propositions: Proposition[],
  roundId: number,
  chatId: number,
  apiKey: string,
  allPersonas?: Persona[],
): Promise<void> {
  // Filter out the persona's own proposition
  const toRate = propositions.filter(
    (p) => p.participant_id !== persona.participant_id
  );

  if (toRate.length === 0) {
    console.log(
      `${LOG_PREFIX} [${persona.name}] No propositions to rate, skipping`
    );
    return;
  }

  // Check idempotency — skip if this persona already rated this round
  const { data: existingRatings } = await supabase
    .from("grid_rankings")
    .select("id")
    .eq("round_id", roundId)
    .eq("participant_id", persona.participant_id)
    .limit(1);

  if (existingRatings && existingRatings.length > 0) {
    console.log(
      `${LOG_PREFIX} [${persona.name}] Already rated in round ${roundId}, skipping`
    );
    return;
  }

  // Build the rating prompt
  const ratingToday = new Date().toISOString().split("T")[0];
  const effectivePersonas = allPersonas || [persona];
  const effectivePersonality = resolvePersonality(persona, chatContext, effectivePersonas);
  const effectiveName = resolveDisplayName(persona, chatContext, effectivePersonas);
  const systemPrompt = `CONTEXT: You are participating in OneMind (onemind.life), a collective consensus platform where humans and AI agents propose ideas and rate them on a 0-100 grid. The best ideas must win multiple consecutive rounds to reach consensus. All propositions are anonymous — judge purely on merit. You are one of several AI agents participating alongside humans; this human-AI collaboration is a core feature of the platform.

TODAY'S DATE: ${ratingToday}. Rate down any propositions that reference past events as if they are upcoming.

You are ${effectiveName}. ${effectivePersonality}`;

  // Language compliance: inject language requirement for rating justifications
  const rateLangs = chatContext.translation_languages || ["en"];
  const ratePrimaryLang = rateLangs[0];
  const rateLangNames: Record<string, string> = { en: "English", es: "Spanish", pt: "Portuguese", fr: "French", de: "German" };
  const rateLangInstruction = rateLangs.length === 1
    ? `\n\nLANGUAGE REQUIREMENT: This chat operates in ${rateLangNames[ratePrimaryLang] || ratePrimaryLang}. You MUST write your rating justification in ${rateLangNames[ratePrimaryLang] || ratePrimaryLang}. Do not use any other language.`
    : `\n\nLANGUAGE REQUIREMENT: This chat operates in ${rateLangs.map(l => rateLangNames[l] || l).join(", ")}. You MUST write your rating justification in ${rateLangNames[ratePrimaryLang] || ratePrimaryLang}. Auto-translation handles other languages.`;
  const fullRatingSystemPrompt = systemPrompt + rateLangInstruction;

  const confirmRounds = chatContext.confirmation_rounds_required;

  let contextBlock = `TOPIC: ${chatContext.name}`;

  contextBlock += `\n\nHOW CONSENSUS WORKS:
A proposition must win ${confirmRounds} consecutive round${confirmRounds > 1 ? "s" : ""} to achieve consensus.`;

  // Conversation history
  contextBlock += `\n\nCONVERSATION HISTORY:`;
  if (chatContext.initial_message) {
    contextBlock += `\n1. [Opening prompt]: "${chatContext.initial_message}"`;
  }
  if (consensusHistory.length > 0) {
    for (const w of consensusHistory) {
      const num = chatContext.initial_message ? w.cycle_number + 1 : w.cycle_number;
      contextBlock += `\n${num}. [Consensus #${w.cycle_number}]: "${w.winning_content}"`;
      if (w.task_result) {
        contextBlock += `\n   → Research results: ${w.task_result}`;
      }
    }
  }
  if (!chatContext.initial_message && consensusHistory.length === 0) {
    contextBlock += `\n(No consensus reached yet)`;
  }

  // Build propositions list — no markers, all equal
  let propositionsList = "";
  for (const p of toRate) {
    propositionsList += `${p.id}: "${p.content}"\n`;
  }

  const userPrompt = `${contextBlock}

PROPOSITIONS TO RATE:
${propositionsList}
TASK: Rate each proposition 0-100 based ONLY on your criterion. Consider how well each proposition advances the conversation given the group's previous decisions.
0 = completely fails your criterion
100 = perfectly satisfies your criterion

Output JSON: {"ratings": {"proposition_id": score, ...}, "reasoning": {"proposition_id": "brief reason (10 words max)", ...}}`;

  const MAX_RETRIES = 3;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await openai.chat.completions.create(
        {
          model: "gemini-2.5-flash",
          max_tokens: 8192,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: fullRatingSystemPrompt },
            { role: "user", content: userPrompt },
          ],
        },
        { signal: AbortSignal.timeout(LLM_TIMEOUT_MS) },
      );

      let responseText = (
        response.choices[0]?.message?.content ?? ""
      ).trim();

      // Strip markdown code fences
      if (responseText.startsWith("```")) {
        responseText = responseText
          .replace(/^```\w*\n?/, "")
          .replace(/\n?```$/, "")
          .trim();
      }

      // Log raw LLM response for debugging JSON parse failures
      console.log(`${LOG_PREFIX} [${persona.name}] Raw rating response: ${responseText.substring(0, 500)}`);

      // Extract JSON object if surrounded by extra text
      const jsonMatch = responseText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        responseText = jsonMatch[0];
      }

      // Fix common JSON issues: trailing commas, missing commas between entries
      responseText = responseText
        .replace(/,\s*}/g, "}")           // trailing comma before }
        .replace(/(\d)\s*\n\s*"/g, '$1, "') // missing comma between lines
        .replace(/(\d)\s+"/g, '$1, "');    // missing comma between entries

      const parsed = JSON.parse(responseText) as Record<string, unknown>;

      // Support both formats:
      // New: {"ratings": {"id": score}, "reasoning": {"id": "reason"}}
      // Old: {"id": score}
      const rawRatings = (parsed.ratings ?? parsed) as Record<string, number>;
      const rawReasoning = (parsed.reasoning ?? {}) as Record<string, string>;

      // Build ratings map for agent-rate API: { "proposition_id": score, ... }
      const ratingsMap: Record<string, number> = {};
      for (const p of toRate) {
        const propIdStr = String(p.id);
        let score = rawRatings[propIdStr];

        if (score === undefined || score === null) {
          // Try numeric key
          score = rawRatings[p.id as unknown as string];
        }

        if (score === undefined || score === null) {
          console.warn(
            `${LOG_PREFIX} [${persona.name}] Missing rating for proposition ${p.id}, defaulting to 50`
          );
          score = 50;
        }

        // Clamp to 0-100
        score = Math.max(0, Math.min(100, Number(score)));
        ratingsMap[propIdStr] = score;
      }

      // Submit via Agent API (validates phase, prevents self-rating, upserts)
      const result = await callAgentRate(chatId, ratingsMap, apiKey);
      console.log(
        `${LOG_PREFIX} [${persona.name}] Rated via API (${Object.keys(ratingsMap).length} props, ${result.rated_count ?? "?"}/${result.total_to_rate ?? "?"}, complete: ${result.is_complete ?? "?"})`
      );

      // Log ratings with reasoning
      const ratingDetails: Record<string, { score: number; reason: string; content: string }> = {};
      for (const p of toRate) {
        const propIdStr = String(p.id);
        ratingDetails[propIdStr] = {
          score: ratingsMap[propIdStr],
          reason: rawReasoning[propIdStr] || rawReasoning[String(p.id)] || "",
          content: p.content.substring(0, 80),
        };
      }
      await logAgent({
        chat_id: chatId, round_id: roundId, persona_name: persona.name, phase: "rating",
        event_type: "rate_reasoning",
        message: `Rated ${Object.keys(ratingsMap).length} propositions`,
        metadata: { ratings: ratingDetails },
      });
      return;
    } catch (error) {
      console.warn(
        `${LOG_PREFIX} [${persona.name}] Rating attempt ${attempt + 1} failed:`,
        error
      );
      // Don't retry timeout/abort errors — fail fast
      if (error instanceof Error && (error.name === "AbortError" || error.message === "Request was aborted." || error.message?.includes("timed out"))) {
        throw new Error(`LLM timeout after ${LLM_TIMEOUT_MS / 1000}s`);
      }
      if (attempt === MAX_RETRIES - 1) {
        // Fallback: submit neutral ratings (50) instead of crashing
        console.warn(
          `${LOG_PREFIX} [${persona.name}] All ${MAX_RETRIES} rating attempts failed, submitting neutral ratings (50)`
        );
        const fallbackRatings: Record<string, number> = {};
        for (const p of toRate) {
          fallbackRatings[String(p.id)] = 50;
        }
        const result = await callAgentRate(chatId, fallbackRatings, apiKey);
        console.log(
          `${LOG_PREFIX} [${persona.name}] Submitted fallback neutral ratings (${Object.keys(fallbackRatings).length} props, ${result.rated_count ?? "?"}/${result.total_to_rate ?? "?"}, complete: ${result.is_complete ?? "?"})`
        );
        return;
      }
      await new Promise((r) => setTimeout(r, 1000 * Math.pow(2, attempt)));
    }
  }
}

// =============================================================================
// MAIN HANDLER
// =============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  if (req.method !== "POST") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  const authResult = await validateAuth(req);
  if (!authResult.valid) {
    console.log(`${LOG_PREFIX} Auth failed:`, authResult.error);
    return corsErrorResponse(authResult.error || "Unauthorized", req, 401);
  }

  try {
    const body = await req.json();
    console.log(`${LOG_PREFIX} Request:`, JSON.stringify(body));

    const { round_id, chat_id, cycle_id, phase, persona_name } = body;

    if (!round_id || !chat_id || !cycle_id || !phase) {
      return corsErrorResponse(
        "Missing required fields: round_id, chat_id, cycle_id, phase",
        req,
        400
      );
    }

    if (!["proposing", "rating"].includes(phase)) {
      return corsErrorResponse(
        `Invalid phase: ${phase}. Must be 'proposing' or 'rating'.`,
        req,
        400
      );
    }

    // =========================================================================
    // DISPATCHER MODE — no persona_name: fire independent worker calls
    // =========================================================================
    if (!persona_name) {
      const allPersonas = await fetchActivePersonas(chat_id);
      if (allPersonas.length === 0) {
        console.log(
          `${LOG_PREFIX} No active agent personas in chat ${chat_id}, skipping`
        );
        return corsJsonResponse(
          { success: true, mode: "dispatcher", personas_processed: 0, message: "No agent personas in chat" },
          req
        );
      }

      // Fetch chat context to get per-phase agent counts
      let dispatchChatContext = await fetchChatContext(chat_id);

      // --- Dynamic persona generation (first dispatch only) ---
      if (dispatchChatContext.agent_configs === null) {
        const agentCount = Math.max(
          dispatchChatContext.proposing_agent_count,
          dispatchChatContext.rating_agent_count,
        );
        const logCtx = { chat_id, cycle_id, round_id };
        const generatedPersonas = await generateDynamicPersonas(
          dispatchChatContext,
          agentCount,
          chat_id,
          logCtx,
        );

        if (generatedPersonas.length > 0) {
          // Save to DB — first-writer-wins guard
          const { data: updated, error: saveError } = await supabase
            .from("chats")
            .update({ agent_configs: generatedPersonas })
            .eq("id", chat_id)
            .is("agent_configs", null)
            .select("agent_configs");

          if (saveError) {
            console.warn(`${LOG_PREFIX} [PERSONA-GEN] Failed to save agent_configs: ${saveError.message}`);
          } else if (updated && updated.length > 0) {
            // We won the write — update participant display names
            dispatchChatContext.agent_configs = generatedPersonas;
            for (let i = 0; i < Math.min(generatedPersonas.length, allPersonas.length); i++) {
              const { error: nameErr } = await supabase
                .from("participants")
                .update({ display_name: generatedPersonas[i].name })
                .eq("id", allPersonas[i].participant_id);
              if (nameErr) {
                console.warn(`${LOG_PREFIX} [PERSONA-GEN] Failed to update display_name for participant ${allPersonas[i].participant_id}: ${nameErr.message}`);
              }
            }
            console.log(`${LOG_PREFIX} [PERSONA-GEN] Saved ${generatedPersonas.length} personas and updated participant names for chat ${chat_id}`);
          } else {
            // Another dispatcher already saved — re-fetch to get their configs
            console.log(`${LOG_PREFIX} [PERSONA-GEN] agent_configs already set by concurrent run, re-fetching`);
            dispatchChatContext = await fetchChatContext(chat_id);
          }
        }
      }

      // Limit personas to the configured count for this phase
      const phaseCount = phase === "proposing"
        ? dispatchChatContext.proposing_agent_count
        : dispatchChatContext.rating_agent_count;
      const personas = allPersonas.slice(0, Math.min(phaseCount, allPersonas.length));

      console.log(
        `${LOG_PREFIX} [DISPATCHER] Using ${personas.length}/${allPersonas.length} personas for ${phase} phase (configured: ${phaseCount})`
      );

      // Forward the same auth token we received (from the DB trigger's vault key)
      const incomingAuth = req.headers.get("Authorization") || `Bearer ${supabaseServiceKey}`;
      console.log(
        `${LOG_PREFIX} [DISPATCHER] Dispatching ${personas.length} workers for ${phase} phase (auth: ${incomingAuth.substring(0, 30)}...)`
      );
      await logAgent({
        chat_id, cycle_id, round_id, phase,
        event_type: "dispatch",
        message: `Dispatching ${personas.length} workers for ${phase} phase`,
        metadata: { personas: personas.map(p => p.name) },
      });

      // For proposing phase: handle category-based state machine
      if (phase === "proposing") {
        // Check if first round of new cycle — opportunity to handle previous consensus category
        const { data: currentRound } = await supabase
          .from("rounds")
          .select("custom_id")
          .eq("id", round_id)
          .single();

        console.log(`${LOG_PREFIX} [DISPATCHER] Round custom_id=${currentRound?.custom_id} for round_id=${round_id}`);
        if (currentRound?.custom_id === 1) {
          const prevConsensus = await fetchPreviousConsensus(chat_id, cycle_id);
          console.log(`${LOG_PREFIX} [DISPATCHER] Previous consensus: ${prevConsensus ? `cycle=${prevConsensus.cycle_id} category=${prevConsensus.category} content="${prevConsensus.winning_content.substring(0, 60)}" task_result=${prevConsensus.task_result ? 'SET' : 'NULL'}` : 'NONE'}`);

          if (prevConsensus) {
            const prevCategory = prevConsensus.category;
            const logCtx = { chat_id, cycle_id: prevConsensus.cycle_id, round_id, phase: "proposing" as const };

            // HUMAN_TASK: agents don't propose — wait for host to submit task result
            if (prevCategory === "human_task") {
              console.log(`${LOG_PREFIX} [DISPATCHER] human_task — agents waiting for host`);
              await logAgent({
                ...logCtx,
                event_type: "category_block",
                message: "human_task consensus — agents paused, waiting for host to complete task",
              });
              return corsJsonResponse({ success: true, action: "waiting_for_host", category: "human_task" }, req);
            }

            // RESEARCH_TASK: auto-execute and store results, then let agents propose normally
            // Results are visible to agents via task_result in consensus history context
            if (prevCategory === "research_task" && !prevConsensus.task_result) {
              console.log(`${LOG_PREFIX} [DISPATCHER] research_task — auto-executing enhanced research`);
              const chatContext = await fetchChatContext(chat_id);
              const consensusHistory = await fetchConsensusHistory(chat_id, cycle_id);
              const brief: ResearchBrief = {
                consensusContent: prevConsensus.winning_content,
                chatName: chatContext.name,
                chatDescription: chatContext.description || "",
                initialMessage: chatContext.initial_message,
                priorConsensus: consensusHistory.map(c => ({
                  cycleNumber: c.cycle_number,
                  content: c.winning_content,
                  category: c.category,
                  taskResult: c.task_result,
                })),
              };
              const researchResult = await executeResearchTaskEnhanced(brief, logCtx);
              // Store full results on the previous cycle — guard against race condition
              // where a concurrent heartbeat already stored results.
              // Only update if task_result IS NULL (first writer wins).
              const { data: updated, error: updateError } = await supabase
                .from("cycles")
                .update({ task_result: researchResult.text })
                .eq("id", prevConsensus.cycle_id)
                .is("task_result", null)
                .select("id");
              if (updateError) {
                console.warn(`${LOG_PREFIX} [DISPATCHER] Failed to store task result: ${updateError.message}`);
                await logAgent({ ...logCtx, event_type: "task_execute", level: "error", message: `Failed to store task_result: ${updateError.message}` });
              } else if (!updated || updated.length === 0) {
                console.log(`${LOG_PREFIX} [DISPATCHER] Skipped storing research — task_result already set by concurrent run for cycle ${prevConsensus.cycle_id}`);
                await logAgent({ ...logCtx, event_type: "task_execute", message: `Research completed but skipped storing — task_result already set by concurrent run (${researchResult.text.length} chars discarded).` });
              } else {
                console.log(`${LOG_PREFIX} [DISPATCHER] Stored research task result for cycle ${prevConsensus.cycle_id} (${researchResult.text.length} chars, ${researchResult.quality.iterationsUsed} iterations, score=${researchResult.quality.completenessScore})`);
                await logAgent({ ...logCtx, event_type: "task_execute", message: `Research complete, results stored (${researchResult.text.length} chars, ${researchResult.quality.iterationsUsed} iterations, stopped=${researchResult.quality.stoppedReason}). Agents will propose based on results.` });
              }
              // Fall through to normal dispatch — agents see results in consensus history
            }

            // Legacy: if no category set, use existing classifyConsensus for backward compat
            if (!prevCategory && !prevConsensus.task_result) {
              const classification = await classifyConsensus(prevConsensus.winning_content, logCtx);
              console.log(`${LOG_PREFIX} [DISPATCHER] Legacy classification: ${classification}`);
              if (classification === "RESEARCH_TASK") {
                const chatContext = await fetchChatContext(chat_id);
                const consensusHistory = await fetchConsensusHistory(chat_id, cycle_id);
                const brief: ResearchBrief = {
                  consensusContent: prevConsensus.winning_content,
                  chatName: chatContext.name,
                  chatDescription: chatContext.description || "",
                  initialMessage: chatContext.initial_message,
                  priorConsensus: consensusHistory.map(c => ({
                    cycleNumber: c.cycle_number,
                    content: c.winning_content,
                    category: c.category,
                    taskResult: c.task_result,
                  })),
                };
                const researchResult = await executeResearchTaskEnhanced(brief, logCtx);
                // Guard against race condition — only store if no result exists yet
                const { data: updated, error: updateError } = await supabase
                  .from("cycles")
                  .update({ task_result: researchResult.text })
                  .eq("id", prevConsensus.cycle_id)
                  .is("task_result", null)
                  .select("id");
                if (updateError) {
                  console.warn(`${LOG_PREFIX} [DISPATCHER] Failed to store task result: ${updateError.message}`);
                } else if (!updated || updated.length === 0) {
                  console.log(`${LOG_PREFIX} [DISPATCHER] Skipped storing research — task_result already set by concurrent run for cycle ${prevConsensus.cycle_id}`);
                } else {
                  console.log(`${LOG_PREFIX} [DISPATCHER] Stored research task result for cycle ${prevConsensus.cycle_id} (${researchResult.text.length} chars, ${researchResult.quality.iterationsUsed} iterations)`);
                }
              }
            }
          }
        }
      }

      // Fire one worker call per persona in parallel, wait for all, retry failures
      const workerUrl = `${supabaseUrl}/functions/v1/agent-orchestrator`;

      const fireWorker = (p: Persona) =>
        fetch(workerUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": incomingAuth,
          },
          body: JSON.stringify({ round_id, chat_id, cycle_id, phase, persona_name: p.name }),
          signal: AbortSignal.timeout(WORKER_WAIT_MS),
        }).then(async (resp) => {
          const body = await resp.text().catch(() => "");
          console.log(`${LOG_PREFIX} [DISPATCHER] Worker ${p.name}: ${resp.status} ${body.substring(0, 200)}`);
          if (!resp.ok) throw new Error(`${resp.status}: ${body.substring(0, 200)}`);
          return { persona: p.name, ok: true };
        });

      // First pass: fire all workers in parallel
      const results = await Promise.allSettled(personas.map(fireWorker));

      const failed: Persona[] = [];
      for (let i = 0; i < results.length; i++) {
        if (results[i].status === "rejected") {
          const reason = (results[i] as PromiseRejectedResult).reason;
          console.warn(`${LOG_PREFIX} [DISPATCHER] Worker ${personas[i].name} failed: ${reason}`);
          failed.push(personas[i]);
        }
      }

      // Retry pass: retry any failed workers once
      let retryFailed = 0;
      if (failed.length > 0) {
        console.log(`${LOG_PREFIX} [DISPATCHER] Retrying ${failed.length} failed workers: ${failed.map(p => p.name).join(", ")}`);
        const retryResults = await Promise.allSettled(failed.map(fireWorker));
        for (let i = 0; i < retryResults.length; i++) {
          if (retryResults[i].status === "rejected") {
            const reason = (retryResults[i] as PromiseRejectedResult).reason;
            console.error(`${LOG_PREFIX} [DISPATCHER] Retry failed for ${failed[i].name}: ${reason}`);
            retryFailed++;
          }
        }
      }

      const succeeded = personas.length - retryFailed;
      console.log(
        `${LOG_PREFIX} [DISPATCHER] Done: ${succeeded}/${personas.length} succeeded, ${failed.length} retried, ${retryFailed} still failed`
      );
      await logAgent({
        chat_id, cycle_id, round_id, phase,
        event_type: "dispatch_complete",
        message: `Dispatch done: ${succeeded}/${personas.length} succeeded, ${retryFailed} failed`,
        metadata: { succeeded, retried: failed.length, final_failed: retryFailed },
      });

      return corsJsonResponse({
        success: true,
        mode: "dispatcher",
        phase,
        dispatched: personas.map(p => p.name),
        succeeded,
        retried: failed.length,
        final_failed: retryFailed,
      }, req);
    }

    // =========================================================================
    // WORKER MODE — persona_name present: process just this one persona
    // =========================================================================
    console.log(
      `${LOG_PREFIX} [WORKER:${persona_name}] Starting ${phase} phase`
    );
    const workerStartMs = Date.now();

    const personas = await fetchActivePersonas(chat_id);
    const persona = personas.find(p => p.name === persona_name);
    if (!persona) {
      console.error(`${LOG_PREFIX} [WORKER:${persona_name}] Persona not found in chat ${chat_id}`);
      return corsErrorResponse(`Persona '${persona_name}' not found in chat ${chat_id}`, req, 404);
    }

    // Fetch API key for this persona
    const apiKeyMap = await fetchPersonaApiKeys();
    const apiKey = apiKeyMap.get(persona_name);
    if (!apiKey) {
      console.error(`${LOG_PREFIX} [WORKER:${persona_name}] No API key found in vault`);
      return corsErrorResponse(`No API key found for persona '${persona_name}'`, req, 500);
    }

    // Fetch shared context
    const chatContext = await fetchChatContext(chat_id);
    const consensusHistory = await fetchConsensusHistory(chat_id, cycle_id);

    if (phase === "proposing") {
      const carriedPropositions = await fetchCarriedPropositions(round_id);
      const allowedCategories = (await fetchAllowedCategories(chat_id)).filter(c => c !== "research_task");
      await handleProposing(persona, chatContext, consensusHistory, carriedPropositions, round_id, chat_id, apiKey, allowedCategories, personas);
    } else {
      const allPropositions = await fetchAllPropositions(round_id);
      await handleRating(persona, chatContext, consensusHistory, allPropositions, round_id, chat_id, apiKey, personas);
    }

    const workerDurationMs = Date.now() - workerStartMs;
    console.log(
      `${LOG_PREFIX} [WORKER:${persona_name}] Completed ${phase} phase in ${workerDurationMs}ms`
    );
    await logAgent({
      chat_id, cycle_id, round_id, persona_name, phase,
      event_type: phase === "proposing" ? "propose" : "rate",
      message: `Worker completed ${phase} in ${workerDurationMs}ms`,
      duration_ms: workerDurationMs,
    });

    return corsJsonResponse({
      success: true,
      mode: "worker",
      phase,
      persona_name,
    }, req);
  } catch (error) {
    console.error(`${LOG_PREFIX} Error:`, error);
    await logAgent({
      event_type: "error",
      level: "error",
      message: error instanceof Error ? error.message : "Unknown error",
      metadata: { stack: error instanceof Error ? error.stack : undefined },
    });
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500
    );
  }
});
