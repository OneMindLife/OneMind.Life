/**
 * Edge Function: agent-chat-state
 *
 * Get current state of a chat (phase, propositions, time remaining).
 *
 * GET /agent-chat-state?chat_id=87
 * Headers: Authorization: Bearer onemind_sk_...
 *
 * Returns:
 * - 200: { chat_id, current_round, propositions, my_propositions_count, ... }
 * - 401: Invalid API key
 * - 403: Not a participant
 * - 404: Chat not found
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
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

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  // Only accept GET
  if (req.method !== "GET") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  // Parse query parameters
  const url = new URL(req.url);
  const chatIdParam = url.searchParams.get("chat_id");

  if (!chatIdParam) {
    return corsErrorResponse(
      "Missing chat_id query parameter",
      req,
      400,
      AgentErrorCodes.INVALID_REQUEST
    );
  }

  const chatId = parseInt(chatIdParam, 10);
  if (isNaN(chatId) || chatId <= 0) {
    return corsErrorResponse(
      "chat_id must be a positive integer",
      req,
      400,
      AgentErrorCodes.INVALID_REQUEST
    );
  }

  // Validate API key and participant status
  const supabase = getServiceClient();
  const authResult = await validateAgentParticipant(req, chatId, supabase);

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

  // Rate limit by agent ID (higher limit for polling endpoint)
  const rateLimiter = new RateLimiter(supabase);
  const rateLimit = await rateLimiter.check({
    key: `agent:chat-state:${authResult.agentId}`,
    ...AgentRateLimits.chatState,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-CHAT-STATE] Rate limited agent: ${authResult.agentName}`);
    return rateLimitResponse(rateLimit);
  }

  try {
    console.log(
      `[AGENT-CHAT-STATE] Agent ${authResult.agentName} checking chat ${chatId}`
    );

    // Get chat info
    const { data: chat, error: chatError } = await supabase
      .from("chats")
      .select("id, name, initial_message, description, propositions_per_user, confirmation_rounds")
      .eq("id", chatId)
      .single();

    if (chatError || !chat) {
      return corsErrorResponse(
        "Chat not found",
        req,
        404,
        AgentErrorCodes.CHAT_NOT_FOUND
      );
    }

    // Get current cycle and round
    // A round is called "iteration" in the DB, renamed for API clarity
    const { data: currentCycle, error: cycleError } = await supabase
      .from("cycles")
      .select(
        `
        id,
        winning_proposition_id,
        completed_at
      `
      )
      .eq("chat_id", chatId)
      .is("completed_at", null)
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (cycleError) {
      console.error("[AGENT-CHAT-STATE] Error getting cycle:", cycleError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // If no active cycle, return waiting state
    if (!currentCycle) {
      return corsJsonResponse(
        {
          chat_id: chatId,
          current_round: null,
          propositions: [],
          my_propositions_count: 0,
          propositions_per_user: chat.propositions_per_user,
          can_propose: false,
          can_rate: false,
          rating_progress: null,
        },
        req,
        200
      );
    }

    // Get current round (iteration)
    const { data: currentRound, error: roundError } = await supabase
      .from("rounds")
      .select(
        `
        id,
        custom_id,
        phase,
        phase_started_at,
        phase_ends_at,
        completed_at
      `
      )
      .eq("cycle_id", currentCycle.id)
      .is("completed_at", null)
      .order("custom_id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (roundError) {
      console.error("[AGENT-CHAT-STATE] Error getting round:", roundError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // If no active round, return waiting state
    if (!currentRound) {
      return corsJsonResponse(
        {
          chat_id: chatId,
          current_round: null,
          propositions: [],
          my_propositions_count: 0,
          propositions_per_user: chat.propositions_per_user,
          can_propose: false,
          can_rate: false,
          rating_progress: null,
        },
        req,
        200
      );
    }

    // Calculate seconds remaining
    const now = new Date();
    const phaseEndsAt = currentRound.phase_ends_at
      ? new Date(currentRound.phase_ends_at)
      : null;
    const secondsRemaining = phaseEndsAt
      ? Math.max(0, Math.floor((phaseEndsAt.getTime() - now.getTime()) / 1000))
      : null;

    // Get propositions for this round
    const { data: propositions, error: propsError } = await supabase
      .from("propositions")
      .select(
        `
        id,
        content,
        participant_id,
        carried_from_id,
        created_at
      `
      )
      .eq("round_id", currentRound.id)
      .order("created_at", { ascending: true });

    if (propsError) {
      console.error("[AGENT-CHAT-STATE] Error getting propositions:", propsError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // Count agent's propositions (excluding carried forward)
    const myPropositionsCount = propositions.filter(
      (p) =>
        p.participant_id === authResult.participantId && p.carried_from_id === null
    ).length;

    // Check if agent can propose
    const canPropose =
      currentRound.phase === "proposing" &&
      secondsRemaining !== null &&
      secondsRemaining > 0 &&
      myPropositionsCount < (chat.propositions_per_user ?? 3);

    // Check if agent can rate
    const canRate =
      currentRound.phase === "rating" &&
      secondsRemaining !== null &&
      secondsRemaining > 0;

    // Get rating progress if in rating phase
    let ratingProgress = null;
    if (currentRound.phase === "rating") {
      // Get total propositions that can be rated (exclude own)
      const otherPropositions = propositions.filter(
        (p) => p.participant_id !== authResult.participantId
      );

      // Get agent's ratings for this round
      const { data: ratings, error: ratingsError } = await supabase
        .from("grid_rankings")
        .select("proposition_id")
        .eq("round_id", currentRound.id)
        .eq("participant_id", authResult.participantId);

      if (!ratingsError && ratings) {
        ratingProgress = {
          rated_count: ratings.length,
          total_to_rate: otherPropositions.length,
          is_complete: ratings.length >= otherPropositions.length,
        };
      }
    }

    // Format propositions for response
    const formattedPropositions = propositions.map((p) => ({
      id: p.id,
      content: p.content,
      is_mine: p.participant_id === authResult.participantId,
      is_carried_forward: p.carried_from_id !== null,
    }));

    return corsJsonResponse(
      {
        chat_id: chatId,
        chat_name: chat.name,
        chat_description: chat.description ?? null,
        chat_initial_message: chat.initial_message ?? null,
        current_round: {
          id: currentRound.id,
          round_number: currentRound.custom_id,
          phase: currentRound.phase,
          phase_started_at: currentRound.phase_started_at,
          phase_ends_at: currentRound.phase_ends_at,
          seconds_remaining: secondsRemaining,
        },
        propositions: formattedPropositions,
        my_propositions_count: myPropositionsCount,
        propositions_per_user: chat.propositions_per_user ?? 3,
        can_propose: canPropose,
        can_rate: canRate,
        rating_progress: ratingProgress,
      },
      req,
      200
    );
  } catch (error) {
    console.error("[AGENT-CHAT-STATE] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
