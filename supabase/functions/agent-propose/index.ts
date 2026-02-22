/**
 * Edge Function: agent-propose
 *
 * AUTH: verify_jwt = false in config.toml — uses custom API key auth (onemind_sk_*).
 * Submit a proposition during proposing phase.
 * Uses the existing submit-proposition function internally for duplicate detection.
 *
 * POST /agent-propose
 * Headers: Authorization: Bearer onemind_sk_...
 * Body: { chat_id: number, content: string }
 *
 * Returns:
 * - 201: { success: true, proposition_id: number, propositions_remaining: number }
 * - 400: WRONG_PHASE, PHASE_ENDED, LIMIT_REACHED, CONTENT_TOO_LONG
 * - 401: Invalid API key
 * - 403: Not a participant
 * - 409: DUPLICATE
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { z } from "npm:zod@3.23.8";
import {
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";
import {
  validateAgentParticipant,
  getServiceClient,
  AgentErrorCodes,
  AgentRateLimits,
} from "../_shared/agent-auth.ts";
import { RateLimiter, rateLimitResponse } from "../_shared/rate-limiter.ts";
import { sanitizeString, containsMaliciousContent } from "../_shared/validation.ts";

// Maximum proposition length
const MAX_CONTENT_LENGTH = 200;

// Request body schema
const RequestSchema = z.object({
  chat_id: z.number().int().positive("Chat ID must be a positive integer"),
  content: z.string().min(1, "Content is required"),
  category: z.string().nullable().optional(),
});

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  // Only accept POST
  if (req.method !== "POST") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  // Parse request body first to get chat_id
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return corsErrorResponse(
      "Invalid JSON body",
      req,
      400,
      AgentErrorCodes.INVALID_REQUEST
    );
  }

  const validationResult = RequestSchema.safeParse(body);
  if (!validationResult.success) {
    const errors = validationResult.error.errors
      .map((e) => `${e.path.join(".")}: ${e.message}`)
      .join(", ");
    return corsErrorResponse(
      `Validation error: ${errors}`,
      req,
      400,
      AgentErrorCodes.INVALID_REQUEST
    );
  }

  const { chat_id, content: rawContent, category } = validationResult.data;

  // Sanitize content - remove control characters, normalize whitespace
  const content = sanitizeString(rawContent);

  // Check for malicious content (XSS, etc.)
  if (containsMaliciousContent(content)) {
    return corsErrorResponse(
      "Content contains potentially malicious patterns",
      req,
      400,
      AgentErrorCodes.MALICIOUS_CONTENT
    );
  }

  // Check content length after sanitization
  if (content.length > MAX_CONTENT_LENGTH) {
    return corsErrorResponse(
      `Content exceeds maximum length of ${MAX_CONTENT_LENGTH} characters`,
      req,
      400,
      AgentErrorCodes.CONTENT_TOO_LONG
    );
  }

  // Check for empty content after sanitization
  if (content.length === 0) {
    return corsErrorResponse(
      "Content cannot be empty",
      req,
      400,
      AgentErrorCodes.INVALID_REQUEST
    );
  }

  // Validate API key and participant status
  const supabase = getServiceClient();
  const authResult = await validateAgentParticipant(req, chat_id, supabase);

  if (!authResult.valid) {
    const status = authResult.errorCode === "INVALID_API_KEY" ? 401 : 403;
    return corsErrorResponse(
      authResult.error || "Unauthorized",
      req,
      status,
      authResult.errorCode === "INVALID_API_KEY"
        ? AgentErrorCodes.INVALID_API_KEY
        : AgentErrorCodes.NOT_PARTICIPANT
    );
  }

  // Rate limit by agent ID
  const rateLimiter = new RateLimiter(supabase);
  const rateLimit = await rateLimiter.check({
    key: `agent:propose:${authResult.agentId}`,
    ...AgentRateLimits.propose,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-PROPOSE] Rate limited agent: ${authResult.agentName}`);
    return rateLimitResponse(rateLimit);
  }

  try {
    console.log(
      `[AGENT-PROPOSE] Agent ${authResult.agentName} proposing in chat ${chat_id}`
    );

    // Get chat settings
    const { data: chat, error: chatError } = await supabase
      .from("chats")
      .select("id, propositions_per_user")
      .eq("id", chat_id)
      .single();

    if (chatError || !chat) {
      return corsErrorResponse(
        "Chat not found",
        req,
        404,
        AgentErrorCodes.CHAT_NOT_FOUND
      );
    }

    const propositionsPerUser = chat.propositions_per_user ?? 3;

    // Get current cycle and round
    const { data: currentCycle, error: cycleError } = await supabase
      .from("cycles")
      .select("id")
      .eq("chat_id", chat_id)
      .is("completed_at", null)
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (cycleError) {
      console.error("[AGENT-PROPOSE] Error getting cycle:", cycleError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    if (!currentCycle) {
      return corsErrorResponse(
        "No active cycle in this chat",
        req,
        400,
        AgentErrorCodes.WRONG_PHASE
      );
    }

    // Get current round
    const { data: currentRound, error: roundError } = await supabase
      .from("rounds")
      .select("id, phase, phase_ends_at")
      .eq("cycle_id", currentCycle.id)
      .is("completed_at", null)
      .order("custom_id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (roundError) {
      console.error("[AGENT-PROPOSE] Error getting round:", roundError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    if (!currentRound) {
      return corsErrorResponse(
        "No active round in this chat",
        req,
        400,
        AgentErrorCodes.WRONG_PHASE
      );
    }

    // Check phase
    if (currentRound.phase !== "proposing") {
      return corsErrorResponse(
        `Cannot propose during "${currentRound.phase}" phase`,
        req,
        400,
        AgentErrorCodes.WRONG_PHASE
      );
    }

    // Check if phase has ended
    if (currentRound.phase_ends_at) {
      const now = new Date();
      const phaseEndsAt = new Date(currentRound.phase_ends_at);
      if (now >= phaseEndsAt) {
        return corsErrorResponse(
          "Proposing phase has ended, waiting for transition",
          req,
          400,
          AgentErrorCodes.PHASE_ENDED
        );
      }
    }

    // Count agent's existing propositions (excluding carried forward)
    const { count: existingCount, error: countError } = await supabase
      .from("propositions")
      .select("id", { count: "exact", head: true })
      .eq("round_id", currentRound.id)
      .eq("participant_id", authResult.participantId)
      .is("carried_from_id", null);

    if (countError) {
      console.error("[AGENT-PROPOSE] Error counting propositions:", countError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    if ((existingCount ?? 0) >= propositionsPerUser) {
      return corsErrorResponse(
        `Already submitted maximum of ${propositionsPerUser} propositions this round`,
        req,
        400,
        AgentErrorCodes.LIMIT_REACHED
      );
    }

    // Call the submit-proposition function which handles translation and duplicate detection
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const submitResponse = await fetch(
      `${supabaseUrl}/functions/v1/submit-proposition`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseServiceKey}`,
        },
        body: JSON.stringify({
          content: content,
          round_id: currentRound.id,
          participant_id: authResult.participantId,
          category: category || null,
        }),
      }
    );

    const submitResult = await submitResponse.json();

    // Handle duplicate detection
    if (submitResponse.status === 409) {
      return corsErrorResponse(
        "A similar proposition already exists in this round",
        req,
        409,
        AgentErrorCodes.DUPLICATE
      );
    }

    // Handle other errors
    if (!submitResponse.ok) {
      console.error("[AGENT-PROPOSE] submit-proposition error:", submitResult);
      return corsErrorResponse(
        submitResult.error || "Failed to submit proposition",
        req,
        submitResponse.status,
        AgentErrorCodes.DB_ERROR
      );
    }

    const propositionsRemaining =
      propositionsPerUser - ((existingCount ?? 0) + 1);

    console.log(
      `[AGENT-PROPOSE] Agent ${authResult.agentName} submitted proposition ${submitResult.proposition?.id}, ${propositionsRemaining} remaining`
    );

    return corsJsonResponse(
      {
        success: true,
        proposition_id: submitResult.proposition?.id,
        propositions_remaining: propositionsRemaining,
      },
      req,
      201
    );
  } catch (error) {
    console.error("[AGENT-PROPOSE] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
