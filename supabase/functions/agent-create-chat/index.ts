/**
 * Edge Function: agent-create-chat
 *
 * Create a new chat for agent coordination.
 * The creating agent becomes the host and first participant.
 *
 * POST /agent-create-chat
 * Headers: Authorization: Bearer onemind_sk_...
 * Body: {
 *   name: string,
 *   initial_message: string,
 *   description?: string,
 *   proposing_duration_seconds?: number (default: 1800 = 30 min),
 *   rating_duration_seconds?: number (default: 1800 = 30 min),
 *   propositions_per_user?: number (default: 3),
 *   confirmation_rounds?: number (default: 2),
 *   start_mode?: "manual" | "auto" (default: "auto"),
 *   auto_start_participant_count?: number (default: 3)
 * }
 *
 * Returns:
 * - 201: { success: true, chat_id: number, invite_code: string, participant_id: number }
 * - 400: Invalid request
 * - 401: Invalid API key
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { z } from "npm:zod@3.23.8";
import {
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";
import {
  validateAgentAuth,
  getServiceClient,
  AgentErrorCodes,
  AgentRateLimits,
} from "../_shared/agent-auth.ts";
import { RateLimiter, rateLimitResponse } from "../_shared/rate-limiter.ts";
import { sanitizeString, containsMaliciousContent } from "../_shared/validation.ts";

// Request body schema with sensible defaults for agent coordination
const RequestSchema = z.object({
  name: z
    .string()
    .min(1, "Name is required")
    .max(100, "Name must be at most 100 characters"),
  initial_message: z
    .string()
    .min(1, "Initial message is required")
    .max(500, "Initial message must be at most 500 characters"),
  description: z
    .string()
    .max(1000, "Description must be at most 1000 characters")
    .optional(),
  // Phase durations - default to 30 minutes each for fast iteration
  proposing_duration_seconds: z
    .number()
    .int()
    .min(60, "Minimum 60 seconds")
    .max(86400, "Maximum 24 hours")
    .default(1800), // 30 minutes
  rating_duration_seconds: z
    .number()
    .int()
    .min(60, "Minimum 60 seconds")
    .max(86400, "Maximum 24 hours")
    .default(1800), // 30 minutes
  propositions_per_user: z
    .number()
    .int()
    .min(1, "Minimum 1 proposition")
    .max(10, "Maximum 10 propositions")
    .default(3),
  confirmation_rounds: z
    .number()
    .int()
    .min(1, "Minimum 1 round")
    .max(10, "Maximum 10 rounds")
    .default(2),
  start_mode: z.enum(["manual", "auto"]).default("auto"),
  auto_start_participant_count: z
    .number()
    .int()
    .min(2, "Minimum 2 participants")
    .max(100, "Maximum 100 participants")
    .default(3),
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

  // Validate API key
  const supabase = getServiceClient();
  const authResult = await validateAgentAuth(req, supabase);

  if (!authResult.valid) {
    return corsErrorResponse(
      authResult.error || "Unauthorized",
      req,
      401,
      authResult.errorCode
    );
  }

  // Rate limit by agent ID
  const rateLimiter = new RateLimiter(supabase);
  const rateLimit = await rateLimiter.check({
    key: `agent:create-chat:${authResult.agentId}`,
    ...AgentRateLimits.createChat,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-CREATE-CHAT] Rate limited agent: ${authResult.agentName}`);
    return rateLimitResponse(rateLimit);
  }

  try {
    // Parse and validate request body
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

    const data = validationResult.data;

    // Sanitize text inputs
    const name = sanitizeString(data.name);
    const initial_message = sanitizeString(data.initial_message);
    const description = data.description ? sanitizeString(data.description) : null;

    // Check for malicious content
    const fieldsToCheck = [name, initial_message, description].filter(Boolean) as string[];
    for (const field of fieldsToCheck) {
      if (containsMaliciousContent(field)) {
        return corsErrorResponse(
          "Input contains potentially malicious patterns",
          req,
          400,
          AgentErrorCodes.MALICIOUS_CONTENT
        );
      }
    }

    // Check for empty required fields after sanitization
    if (name.length === 0) {
      return corsErrorResponse(
        "Chat name cannot be empty",
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }
    if (initial_message.length === 0) {
      return corsErrorResponse(
        "Initial message cannot be empty",
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }

    console.log(
      `[AGENT-CREATE-CHAT] Agent ${authResult.agentName} creating chat: ${name}`
    );

    // Create the chat
    // access_method: "code" makes it a public chat (joinable via invite code)
    // Agents create public chats so other agents can join
    const { data: chat, error: chatError } = await supabase
      .from("chats")
      .insert({
        name: name, // Use sanitized value
        initial_message: initial_message, // Use sanitized value
        description: description, // Use sanitized value (already nullable)
        access_method: "code", // Public chat with invite code
        require_approval: false, // No approval needed for agents
        require_auth: false, // Anonymous agents can participate
        creator_id: authResult.userId,
        is_active: true,
        is_official: false,
        start_mode: data.start_mode,
        auto_start_participant_count: data.auto_start_participant_count,
        proposing_duration_seconds: data.proposing_duration_seconds,
        rating_duration_seconds: data.rating_duration_seconds,
        propositions_per_user: data.propositions_per_user,
        confirmation_rounds: data.confirmation_rounds,
        // Don't enable AI participant - let agents participate directly
        enable_ai_participant: false,
      })
      .select("id, invite_code")
      .single();

    if (chatError || !chat) {
      console.error("[AGENT-CREATE-CHAT] Error creating chat:", chatError);
      return corsErrorResponse(
        "Failed to create chat",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    console.log(
      `[AGENT-CREATE-CHAT] Chat created: ${chat.id} with code ${chat.invite_code}`
    );

    // Add the creating agent as the host participant
    const { data: participant, error: participantError } = await supabase
      .from("participants")
      .insert({
        chat_id: chat.id,
        user_id: authResult.userId,
        display_name: `Agent: ${authResult.agentName}`,
        is_host: true,
        is_authenticated: true,
        status: "active",
      })
      .select("id")
      .single();

    if (participantError || !participant) {
      console.error(
        "[AGENT-CREATE-CHAT] Error creating participant:",
        participantError
      );
      // Chat was created but participant failed - try to clean up
      await supabase.from("chats").delete().eq("id", chat.id);
      return corsErrorResponse(
        "Failed to add host participant",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    console.log(
      `[AGENT-CREATE-CHAT] Agent ${authResult.agentName} is host of chat ${chat.id}`
    );

    return corsJsonResponse(
      {
        success: true,
        chat_id: chat.id,
        invite_code: chat.invite_code,
        participant_id: participant.id,
        message: `Chat created! Other agents can join with code: ${chat.invite_code}`,
      },
      req,
      201
    );
  } catch (error) {
    console.error("[AGENT-CREATE-CHAT] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
