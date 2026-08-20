// Edge Function: generate-options
//
// Generates a small batch of candidate idea-options from a question in ONE
// LLM call, for a preview of the "gather ideas from the group" flow.
//
// CLIENT-INVOKED (from Flutter via supabase.functions.invoke), not cron.
//
// Accepts:
// - { question: string, count?: number }  (count defaults to 5, clamped [2, 6])
// - optional { round_id: number } — enables the per-round shared pool: the
//   first caller for a round generates + caches the batch in starter_pools
//   (service-role only; RLS denies clients), everyone after gets the cached
//   batch instantly. One LLM call per round instead of per visitor.
//
// Returns:
// - 200 { options: string[], fallback: false } on success
// - 200 { options: [], fallback: true, error: "<short>" } on LLM/parse failure
//   (graceful degradation — the client lets the creator type their own)
// - 401 if the Authorization JWT is missing/invalid
//
// AUTH: verify_jwt = false in config.toml (deploy uses --no-verify-jwt).
// We validate the user JWT internally via supabase.auth.getUser(token).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4.77.0";
import {
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";
import {
  cleanOptions,
  DEFAULT_COUNT,
  MAX_COUNT,
  MAX_OPTION_LENGTH,
  MIN_COUNT,
} from "./options-clean.ts";

// Re-export the pure helper so callers/tests can import it from the function entry too.
export { cleanOptions };

// Environment variables
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const deepseekApiKey = Deno.env.get("DEEPSEEK_API_KEY") ?? "";

// Initialize Supabase client with service role for auth validation
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Initialize OpenAI client pointing to DeepSeek
const openai = new OpenAI({
  apiKey: deepseekApiKey,
  baseURL: "https://api.deepseek.com",
});

const LLM_MODEL = "deepseek-v4-flash";
const LLM_TIMEOUT_MS = 12_000;

// =============================================================================
// AUTH VALIDATION
// =============================================================================

/**
 * Validate the request JWT via supabase.auth.getUser(token).
 * Returns the user id on success, an error string otherwise.
 */
async function validateAuth(
  req: Request,
): Promise<{ user: { id: string } } | { error: string }> {
  const authHeader = req.headers.get("Authorization") ||
    req.headers.get("authorization");
  const token = authHeader?.replace("Bearer ", "");

  if (!token) {
    return { error: "Unauthorized - no token" };
  }

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return { error: "Invalid token" };
  }
  return { user: { id: user.id } };
}

// =============================================================================
// LLM CALL
// =============================================================================

type OptionsMode = "question" | "answer";

function buildPrompt(
  question: string,
  count: number,
  strict: boolean,
  mode: OptionsMode = "answer",
  history: string[] = [],
): string {
  const hasHistory = history.length > 0;

  let base: string;
  if (hasHistory) {
    // Context-aware "best next take". The room is ONE continuous conversation
    // (no question/answer mode): the model reads the whole thread and proposes
    // the strongest next contributions — answer the latest open question, push
    // back, or raise the next thing worth deciding — whatever moves it forward.
    base =
      `A room of anonymous strangers is having one evolving group conversation. Here it is so far, oldest first:\n\n` +
      `${history.join("\n")}\n\n` +
      `Suggest exactly ${count} distinct, natural NEXT contributions that keep this conversation going — each should build on where it has gone: answer the latest open question, take a fresh angle, push back, or raise the next thing worth deciding. Write each in a real person's voice, a single short line under ${MAX_OPTION_LENGTH} characters. Do not repeat anything already said, and don't number them.\n\n` +
      `Return ONLY a JSON array of strings.`;
  } else if (mode === "question") {
    base =
      `Generate exactly ${count} distinct, open-ended, OPINION-SPLITTING questions for a room of anonymous strangers to debate — the kind where everyone has a different answer and wants to weigh in. Each must be a single, self-contained question ending in a question mark, thought-provoking but not offensive, under ${MAX_OPTION_LENGTH} characters. Favor "what / why / should / is it ever / would you rather" framings; avoid trivia and simple yes/no facts.\n\n` +
      `Examples: "What's the most overrated life goal?", "Is it ever okay to lie to protect someone?", "Does hard work matter more than luck?", "What belief did you change your mind about?"\n\n` +
      `Return ONLY a JSON array of strings, nothing else. Example:\n` +
      `["First question?", "Second question?"]`;
  } else {
    base =
      `A group of people is deciding on the following question/topic:\n\n"${question}"\n\n` +
      `Generate exactly ${count} distinct, concrete, short candidate options that ` +
      `members of the group might propose in response. Each option must be a single ` +
      `idea, no longer than ${MAX_OPTION_LENGTH} characters, with no numbering, no ` +
      `bullets, and no preamble.\n\n` +
      `Return ONLY a JSON array of strings, nothing else. Example:\n` +
      `["First idea", "Second idea"]`;
  }

  if (!strict) return base;

  return base +
    `\n\nSTRICT: Output must be valid JSON only — a flat array of plain strings. ` +
    `No markdown, no code fences, no keys, no trailing text. ` +
    `Each string must be under ${MAX_OPTION_LENGTH} characters.`;
}

/**
 * One batched chat.completions.create call. Returns the raw response text.
 */
async function callLlm(
  question: string,
  count: number,
  strict: boolean,
  mode: OptionsMode = "answer",
  history: string[] = [],
): Promise<string> {
  const message = await openai.chat.completions.create(
    {
      model: LLM_MODEL,
      max_tokens: 1024,
      messages: [
        {
          role: "user",
          content: buildPrompt(question, count, strict, mode, history),
        },
      ],
    },
    { signal: AbortSignal.timeout(LLM_TIMEOUT_MS) },
  );
  return message.choices[0]?.message?.content ?? "";
}

// =============================================================================
// MAIN HANDLER
// =============================================================================

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  // Only accept POST
  if (req.method !== "POST") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  // Validate auth (real user calling it)
  const authResult = await validateAuth(req);
  if ("error" in authResult) {
    console.log("[GENERATE-OPTIONS] Auth failed:", authResult.error);
    return corsErrorResponse(authResult.error, req, 401);
  }

  // Parse and validate request body
  let question: string;
  let count: number;
  let roundId: number | null = null;
  let mode: OptionsMode = "answer";
  let history: string[] = [];
  try {
    const body = await req.json();
    if (typeof body?.question !== "string" || body.question.trim().length === 0) {
      return corsErrorResponse("Validation error: question is required", req, 400);
    }
    question = body.question.trim();
    const rawCount = typeof body?.count === "number" ? Math.floor(body.count) : DEFAULT_COUNT;
    count = Math.min(MAX_COUNT, Math.max(MIN_COUNT, rawCount || DEFAULT_COUNT));
    if (typeof body?.round_id === "number" && Number.isInteger(body.round_id)) {
      roundId = body.round_id;
    }
    // Anything not exactly "question" normalizes to "answer" (the default).
    mode = body?.mode === "question" ? "question" : "answer";
    // Optional ordered conversation history (oldest→newest). Keep only
    // non-empty strings, and cap to the last 40 to bound prompt size. Missing
    // or empty → no history (current behavior).
    if (Array.isArray(body?.history)) {
      history = body.history
        .filter((h: unknown): h is string => typeof h === "string" && h.trim().length > 0)
        .map((h: string) => h.trim())
        .slice(-40);
    }
  } catch {
    return corsErrorResponse("Validation error: invalid JSON body", req, 400);
  }

  // Per-round pool: serve the cached batch if one exists.
  if (roundId !== null) {
    const { data: pool } = await supabase
      .from("starter_pools")
      .select("options")
      .eq("round_id", roundId)
      .maybeSingle();
    if (pool && Array.isArray(pool.options) && pool.options.length >= MIN_COUNT) {
      return corsJsonResponse(
        { options: pool.options, fallback: false, cached: true },
        req,
      );
    }
  }

  // Generate options — graceful degradation on any failure (never 500).
  try {
    // Attempt 1
    const raw1 = await callLlm(question, count, false, mode, history);
    let options = cleanOptions(raw1, count);

    // Retry ONCE with a stricter prompt if we got fewer than 2 valid options.
    if (options.length < MIN_COUNT) {
      console.log("[GENERATE-OPTIONS] First attempt yielded", options.length, "— retrying strict");
      const raw2 = await callLlm(question, count, true, mode, history);
      options = cleanOptions(raw2, count);
    }

    if (options.length < MIN_COUNT) {
      console.log("[GENERATE-OPTIONS] Insufficient options after retry — fallback");
      return corsJsonResponse(
        { options: [], fallback: true, error: "insufficient_options" },
        req,
      );
    }

    console.log("[GENERATE-OPTIONS] Generated", options.length, "options");

    // Cache the batch for the round (first writer wins; a concurrent
    // generator's conflict is fine — both batches are valid).
    if (roundId !== null) {
      const { error: poolError } = await supabase
        .from("starter_pools")
        .insert({ round_id: roundId, options });
      if (poolError && poolError.code !== "23505" && poolError.code !== "23503") {
        // 23505 = concurrent first-writer, 23503 = round deleted — both benign.
        console.error("[GENERATE-OPTIONS] Pool cache write failed:", poolError.message);
      }
    }

    return corsJsonResponse({ options, fallback: false }, req);
  } catch (error) {
    const short = error instanceof Error
      ? error.message.slice(0, 120)
      : "unknown_error";
    console.error("[GENERATE-OPTIONS] Generation failed (fallback):", error);
    return corsJsonResponse(
      { options: [], fallback: true, error: short },
      req,
    );
  }
});
