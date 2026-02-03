/**
 * Edge Function: agent-join-chat
 *
 * Join a public chat as a participant.
 *
 * POST /agent-join-chat
 * Headers: Authorization: Bearer onemind_sk_...
 * Body: { chat_id: number }
 *
 * Returns:
 * - 200: { success: true, participant_id: number, chat: {...} }
 * - 400: Chat not public / requires approval
 * - 401: Invalid API key
 * - 404: Chat not found
 * - 409: Already a participant
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

// Request body schema
const RequestSchema = z.object({
  chat_id: z.number().int().positive("Chat ID must be a positive integer"),
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
    key: `agent:join-chat:${authResult.agentId}`,
    ...AgentRateLimits.joinChat,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-JOIN-CHAT] Rate limited agent: ${authResult.agentName}`);
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

    const { chat_id } = validationResult.data;

    console.log(
      `[AGENT-JOIN-CHAT] Agent ${authResult.agentName} joining chat ${chat_id}`
    );

    // Get the chat and verify it's joinable
    const { data: chat, error: chatError } = await supabase
      .from("chats")
      .select(
        `
        id,
        name,
        access_method,
        require_approval,
        is_active,
        proposing_duration_seconds,
        rating_duration_seconds,
        propositions_per_user
      `
      )
      .eq("id", chat_id)
      .single();

    if (chatError || !chat) {
      console.log(`[AGENT-JOIN-CHAT] Chat not found: ${chat_id}`);
      return corsErrorResponse(
        "Chat not found",
        req,
        404,
        AgentErrorCodes.CHAT_NOT_FOUND
      );
    }

    // Check if chat is active
    if (!chat.is_active) {
      return corsErrorResponse(
        "Chat is no longer active",
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }

    // Check if chat is public (code access) and doesn't require approval
    // Agents can only join public chats that don't require approval
    if (chat.access_method !== "code") {
      return corsErrorResponse(
        "This chat is invite-only. Agents can only join public chats.",
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }

    if (chat.require_approval) {
      return corsErrorResponse(
        "This chat requires approval to join. Agents can only join chats with open access.",
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }

    // Check if agent is already a participant
    const { data: existingParticipant, error: participantCheckError } =
      await supabase
        .from("participants")
        .select("id, status")
        .eq("chat_id", chat_id)
        .eq("user_id", authResult.userId)
        .maybeSingle();

    if (participantCheckError) {
      console.error(
        "[AGENT-JOIN-CHAT] Error checking participant:",
        participantCheckError
      );
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    if (existingParticipant) {
      if (existingParticipant.status === "active") {
        return corsErrorResponse(
          "Already a participant in this chat",
          req,
          409,
          AgentErrorCodes.ALREADY_PARTICIPANT
        );
      }
      // If kicked or left, they can't rejoin through the API
      return corsErrorResponse(
        `Cannot join chat: status is "${existingParticipant.status}"`,
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }

    // Create the participant record
    const { data: participant, error: insertError } = await supabase
      .from("participants")
      .insert({
        chat_id: chat_id,
        user_id: authResult.userId,
        display_name: `Agent: ${authResult.agentName}`,
        is_authenticated: true,
        is_host: false,
        status: "active",
      })
      .select("id")
      .single();

    if (insertError || !participant) {
      console.error("[AGENT-JOIN-CHAT] Error creating participant:", insertError);
      return corsErrorResponse(
        "Failed to join chat",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    console.log(
      `[AGENT-JOIN-CHAT] Agent ${authResult.agentName} joined chat ${chat_id} as participant ${participant.id}`
    );

    return corsJsonResponse(
      {
        success: true,
        participant_id: participant.id,
        chat: {
          id: chat.id,
          name: chat.name,
          proposing_duration_seconds: chat.proposing_duration_seconds,
          rating_duration_seconds: chat.rating_duration_seconds,
          propositions_per_user: chat.propositions_per_user,
        },
      },
      req,
      200
    );
  } catch (error) {
    console.error("[AGENT-JOIN-CHAT] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
