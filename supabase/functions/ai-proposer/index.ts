// Edge Function: ai-proposer
// Automatically generates AI propositions when a round enters the proposing phase
//
// Called by database trigger when rounds.phase becomes 'proposing'
// Receives: { round_id, chat_id, cycle_id, custom_id }
//
// Process:
// 1. Fetch context: chat info, consensus history, carried forward propositions
// 2. Call Kimi K2.5 API with context to generate propositions
// 3. Insert AI propositions with participant_id = NULL
//
// AUTH: This function uses internal auth validation (verify_jwt should be false at Supabase level)
// - Accepts service role key in Authorization header (from DB trigger via vault)
// - Allows local development without auth

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4.77.0";
import { z } from "npm:zod@3.23.8";
import {
  getCorsHeaders,
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";

// Environment variables
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// Initialize OpenAI client pointing to NVIDIA-hosted Kimi K2.5
const openai = new OpenAI({
  apiKey: Deno.env.get("NVIDIA_API_KEY") ?? "",
  baseURL: "https://integrate.api.nvidia.com/v1",
});

// Initialize Supabase client with service role for DB operations
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Request body schema
const RequestSchema = z.object({
  round_id: z.number().int().positive(),
  chat_id: z.number().int().positive(),
  cycle_id: z.number().int().positive(),
  custom_id: z.number().int().positive(), // Round number within cycle
});

// =============================================================================
// TYPE DEFINITIONS
// =============================================================================

interface ChatContext {
  id: number;
  name: string;
  initial_message: string;
  description: string | null;
  ai_propositions_count: number;
}

interface ConsensusWinner {
  cycle_number: number;
  winning_content: string;
  round_count: number;
}

interface CarriedProposition {
  id: number;
  content: string;
  carried_from_id: number;
}

interface AIProposerContext {
  chat: ChatContext;
  consensus_history: ConsensusWinner[];
  carried_propositions: CarriedProposition[];
  current_cycle_number: number;
  current_round_number: number;
  is_first_round_of_cycle: boolean;
}

// Maximum proposition length (matches database constraint)
const MAX_CONTENT_LENGTH = 200;

// =============================================================================
// CONTENT VALIDATION
// =============================================================================

/**
 * Validates that all propositions meet the length requirement.
 * Returns the invalid propositions (too long) for error reporting.
 */
function validatePropositionLengths(propositions: string[]): { valid: boolean; tooLong: string[] } {
  const tooLong = propositions.filter(p => p.trim().length > MAX_CONTENT_LENGTH);
  return { valid: tooLong.length === 0, tooLong };
}

// =============================================================================
// AUTH VALIDATION (same pattern as translate function)
// =============================================================================

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = parts[1];
    const decoded = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(decoded);
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

async function validateAuth(req: Request): Promise<{ valid: boolean; error?: string }> {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  // 1. Allow local development
  const isLocalDev = supabaseUrl.includes("localhost") ||
                     supabaseUrl.includes("127.0.0.1") ||
                     supabaseUrl.includes("kong:8000");
  if (isLocalDev) {
    return { valid: true };
  }

  // 2. Check for service role JWT
  if (token) {
    const payload = decodeJwtPayload(token);
    if (payload) {
      const role = payload.role as string | undefined;
      const iss = payload.iss as string | undefined;
      const projectRef = getProjectRef();

      if (role === "service_role" && iss === "supabase" && projectRef) {
        const ref = payload.ref as string | undefined;
        if (ref === projectRef) {
          console.log("[AI-PROPOSER] Auth: Valid service role JWT for project", projectRef);
          return { valid: true };
        }
      }
    }
  }

  // 3. Validate user JWT via Supabase Auth
  if (token && supabaseAnonKey) {
    try {
      const userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data: { user }, error } = await userClient.auth.getUser();
      if (user && !error) {
        return { valid: true };
      }
    } catch {
      // Token validation failed
    }
  }

  return { valid: false, error: "Unauthorized - valid JWT or service role key required" };
}

// =============================================================================
// CONTEXT FETCHING
// =============================================================================

async function fetchContext(
  chatId: number,
  cycleId: number,
  roundId: number,
  customId: number
): Promise<AIProposerContext> {
  // 1. Fetch chat info
  const { data: chat, error: chatError } = await supabase
    .from("chats")
    .select("id, name, initial_message, description, ai_propositions_count")
    .eq("id", chatId)
    .single();

  if (chatError || !chat) {
    throw new Error(`Failed to fetch chat: ${chatError?.message || "Not found"}`);
  }

  // 2. Get current cycle number (for context)
  const { data: cycles, error: cyclesError } = await supabase
    .from("cycles")
    .select("id")
    .eq("chat_id", chatId)
    .order("id", { ascending: true });

  if (cyclesError) {
    throw new Error(`Failed to fetch cycles: ${cyclesError.message}`);
  }

  const currentCycleNumber = cycles?.findIndex(c => c.id === cycleId) + 1 || 1;

  // 3. Fetch consensus history (completed cycles with winners)
  const { data: completedCycles, error: consensusError } = await supabase
    .from("cycles")
    .select("id, winning_proposition_id")
    .eq("chat_id", chatId)
    .not("winning_proposition_id", "is", null)
    .order("id", { ascending: true });

  if (consensusError) {
    throw new Error(`Failed to fetch consensus history: ${consensusError.message}`);
  }

  // Fetch winning proposition content and round counts separately
  const consensusHistory: ConsensusWinner[] = [];
  for (const [index, cycle] of (completedCycles || []).entries()) {
    // Get winning proposition content
    const { data: winningProp } = await supabase
      .from("propositions")
      .select("content")
      .eq("id", cycle.winning_proposition_id)
      .single();

    // Get round count for this cycle
    const { data: roundsData } = await supabase
      .from("rounds")
      .select("id")
      .eq("cycle_id", cycle.id);

    consensusHistory.push({
      cycle_number: index + 1,
      winning_content: winningProp?.content || "Unknown",
      round_count: roundsData?.length || 0,
    });
  }

  // 4. Fetch carried forward propositions for this round (the competition)
  const { data: carriedProps, error: carriedError } = await supabase
    .from("propositions")
    .select("id, content, carried_from_id")
    .eq("round_id", roundId)
    .not("carried_from_id", "is", null);

  if (carriedError) {
    throw new Error(`Failed to fetch carried propositions: ${carriedError.message}`);
  }

  const carriedPropositions: CarriedProposition[] = (carriedProps || []).map(p => ({
    id: p.id,
    content: p.content,
    carried_from_id: p.carried_from_id,
  }));

  return {
    chat: chat as ChatContext,
    consensus_history: consensusHistory,
    carried_propositions: carriedPropositions,
    current_cycle_number: currentCycleNumber,
    current_round_number: customId,
    is_first_round_of_cycle: customId === 1,
  };
}

// =============================================================================
// AI PROPOSITION GENERATION
// =============================================================================

async function generatePropositions(
  context: AIProposerContext,
  count: number
): Promise<string[]> {
  const MAX_RETRIES = 3;
  const RETRY_DELAY = 1000;

  // Build the prompt with context
  let prompt = `You are participating in OneMind, an ANONYMOUS consensus-building platform.

## How OneMind Works
- All propositions are anonymous - no one knows who submitted what
- Users propose short ideas (under 200 chars) and rate each other's propositions
- The highest-rated proposition wins the round and auto-carries to the next round
- If it wins again, it becomes permanent consensus (the group couldn't find anything better)
- IMPORTANT: Never suggest direct communication between participants - anonymity is core to the platform

## The Topic
**${context.chat.name}**

${context.chat.initial_message ? context.chat.initial_message : "(Open discussion - no specific prompt provided)"}

${context.chat.description ? `\n**Additional Context:** ${context.chat.description}` : ""}
`;

  // Add consensus history - this IS the conversation thread
  if (context.consensus_history.length > 0) {
    prompt += `\n## The Conversation So Far
This is the thread of ideas the community has agreed upon. Each consensus builds on the previous, forming a collaborative conversation:\n`;
    for (const consensus of context.consensus_history) {
      prompt += `\n**Response ${consensus.cycle_number}** (agreed after ${consensus.round_count} rounds of voting):\n"${consensus.winning_content}"\n`;
    }
    prompt += `\nYour job is to continue this conversation with the next compelling idea that builds on or responds to what's been established.\n`;
  } else {
    prompt += `\n## Starting Point
This is the beginning of the conversation. No consensus has been reached yet - you're helping to kickstart the discussion.\n`;
  }

  // Add carried forward propositions - competition to beat (not to respond to)
  if (context.carried_propositions.length > 0) {
    prompt += `\n## Current Leader (Your Competition)
The following proposition${context.carried_propositions.length > 1 ? 's are' : ' is'} currently winning the vote:\n`;
    for (const prop of context.carried_propositions) {
      prompt += `\n> "${prop.content}"\n`;
    }
    prompt += `
IMPORTANT: This is your COMPETITION, not something to respond to or build upon.
- Do NOT reference, acknowledge, or build upon the competition's content
- Do NOT say things like "before doing X" or "in addition to X" where X is their idea
- Propose a completely INDEPENDENT alternative approach
- Think of this like an election: you're a different candidate with a different platform
- Your proposition should stand completely on its own\n`;
  }

  // Base task instructions (will be augmented on retries)
  const baseTaskPrompt = `\n## Your Task
Generate ${count} proposition${count > 1 ? "s" : ""} as your response to this conversation.

Guidelines:
- Respond to the topic and any consensus history with fresh insight
- **CRITICAL: Each proposition MUST be under ${MAX_CONTENT_LENGTH} characters** (this is a hard database limit)
- Be specific and actionable
- Consider what would unite diverse perspectives
${context.carried_propositions.length > 0 ? "- Propose a completely different approach than the current leader - do not reference their idea at all" : "- As the first responder, set a high bar for quality"}

Return ONLY a JSON array of strings, no markdown or explanation:
["Your proposition here"]`;

  let attempts = 0;

  while (attempts < MAX_RETRIES) {
    try {
      // On retry, add stricter length warning
      let taskPrompt = baseTaskPrompt;
      if (attempts > 0) {
        taskPrompt = `\n## Your Task
Generate ${count} proposition${count > 1 ? "s" : ""} as your response to this conversation.

⚠️ **STRICT LENGTH REQUIREMENT** ⚠️
Your previous attempt was rejected because propositions exceeded ${MAX_CONTENT_LENGTH} characters.
Each proposition MUST be ${MAX_CONTENT_LENGTH} characters or fewer. This is a hard database constraint.
Count your characters carefully. Aim for ~150 characters to be safe.

Guidelines:
- Be CONCISE - every word must earn its place
- **MAX ${MAX_CONTENT_LENGTH} CHARACTERS per proposition** (shorter is better)
- Focus on ONE clear idea per proposition
${context.carried_propositions.length > 0 ? "- Propose a completely different approach than the current leader" : "- Set a high bar for quality"}

Return ONLY a JSON array of strings, no markdown:
["Your proposition here"]`;
      }

      const fullPrompt = prompt + taskPrompt;

      const message = await openai.chat.completions.create({
        model: "moonshotai/kimi-k2.5",
        max_tokens: 8192, // Kimi K2.5 is a reasoning model — thinking tokens count against this limit
        messages: [
          {
            role: "user",
            content: fullPrompt,
          },
        ],
      });

      // Extract text from response
      const responseText = message.choices[0]?.message?.content ?? "";

      // Clean up the response
      let cleanedResponse = responseText.trim();
      if (cleanedResponse.startsWith("```json")) {
        cleanedResponse = cleanedResponse.slice(7);
      } else if (cleanedResponse.startsWith("```")) {
        cleanedResponse = cleanedResponse.slice(3);
      }
      if (cleanedResponse.endsWith("```")) {
        cleanedResponse = cleanedResponse.slice(0, -3);
      }
      cleanedResponse = cleanedResponse.trim();

      // Parse and validate
      const parsed = JSON.parse(cleanedResponse);
      if (!Array.isArray(parsed)) {
        throw new Error("Response is not an array");
      }

      // Filter out non-strings and empty strings
      const propositions = parsed
        .filter((p): p is string => typeof p === "string" && p.trim().length > 0)
        .map((p) => p.trim())
        .slice(0, count); // Limit to requested count

      if (propositions.length === 0) {
        throw new Error("No valid propositions generated");
      }

      // Validate length - if any are too long, throw to trigger retry
      const validation = validatePropositionLengths(propositions);
      if (!validation.valid) {
        const lengths = validation.tooLong.map(p => p.length).join(', ');
        throw new Error(`Propositions too long (${lengths} chars, max ${MAX_CONTENT_LENGTH}). Retrying with stricter prompt.`);
      }

      // Log with length info for debugging
      for (const prop of propositions) {
        console.log(`[AI-PROPOSER] Proposition (${prop.length} chars): "${prop.substring(0, 50)}${prop.length > 50 ? '...' : ''}"`);
      }
      console.log(`[AI-PROPOSER] Generated ${propositions.length} valid propositions`);
      return propositions;
    } catch (error) {
      attempts++;
      console.error(`[AI-PROPOSER] Attempt ${attempts} failed:`, error);

      if (attempts === MAX_RETRIES) {
        throw new Error(
          `Failed to generate propositions after ${MAX_RETRIES} attempts: ${error instanceof Error ? error.message : "Unknown error"}`
        );
      }

      // Exponential backoff
      await new Promise((resolve) =>
        setTimeout(resolve, RETRY_DELAY * Math.pow(2, attempts - 1))
      );
    }
  }

  throw new Error("Generation failed unexpectedly");
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

  // Validate auth
  const authResult = await validateAuth(req);
  if (!authResult.valid) {
    console.log("[AI-PROPOSER] Auth failed:", authResult.error);
    return corsErrorResponse(authResult.error || "Unauthorized", req, 401);
  }

  try {
    // Parse and validate request body
    const body = await req.json();
    console.log("[AI-PROPOSER] Request:", JSON.stringify(body));

    const validationResult = RequestSchema.safeParse(body);
    if (!validationResult.success) {
      const errors = validationResult.error.errors.map((e) => e.message).join(", ");
      console.error("[AI-PROPOSER] Validation error:", errors);
      return corsErrorResponse(`Validation error: ${errors}`, req, 400);
    }

    const { round_id, chat_id, cycle_id, custom_id } = validationResult.data;

    // Fetch context
    console.log("[AI-PROPOSER] Fetching context for round", round_id);
    const context = await fetchContext(chat_id, cycle_id, round_id, custom_id);

    // Check if AI propositions are enabled and count is valid
    const count = context.chat.ai_propositions_count || 1;
    if (count <= 0) {
      console.log("[AI-PROPOSER] Skipped: ai_propositions_count is", count);
      return corsJsonResponse({ success: true, propositions_created: 0 }, req);
    }

    // Check if AI has already submitted to this round (idempotency)
    const { data: existingAiProps, error: checkError } = await supabase
      .from("propositions")
      .select("id")
      .eq("round_id", round_id)
      .is("participant_id", null)
      .is("carried_from_id", null); // Exclude carried forward (they also have null participant_id)

    if (checkError) {
      throw new Error(`Failed to check existing AI propositions: ${checkError.message}`);
    }

    if (existingAiProps && existingAiProps.length > 0) {
      console.log("[AI-PROPOSER] Skipped: AI already submitted to round", round_id);
      return corsJsonResponse({
        success: true,
        propositions_created: 0,
        message: "AI already submitted to this round",
      }, req);
    }

    // Generate propositions
    console.log("[AI-PROPOSER] Generating", count, "propositions");
    const propositions = await generatePropositions(context, count);

    // Insert propositions
    const inserts = propositions.map(content => ({
      round_id,
      participant_id: null, // Marks as AI-generated
      content,
      carried_from_id: null,
    }));

    const { data: inserted, error: insertError } = await supabase
      .from("propositions")
      .insert(inserts)
      .select("id");

    if (insertError) {
      throw new Error(`Failed to insert propositions: ${insertError.message}`);
    }

    console.log("[AI-PROPOSER] Successfully created", inserted?.length || 0, "propositions");

    return corsJsonResponse({
      success: true,
      propositions_created: inserted?.length || 0,
      proposition_ids: inserted?.map(p => p.id) || [],
    }, req);
  } catch (error) {
    console.error("[AI-PROPOSER] Error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500
    );
  }
});
