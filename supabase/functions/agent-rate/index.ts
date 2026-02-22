/**
 * Edge Function: agent-rate
 *
 * Submit ratings during rating phase.
 *
 * POST /agent-rate
 * Headers: Authorization: Bearer onemind_sk_...
 * Body: { chat_id: number, ratings: { [proposition_id: string]: number } }
 *
 * Ratings are 0-100 inclusive.
 *
 * Returns:
 * - 200: { success: true, rated_count: number, total_to_rate: number, is_complete: boolean }
 * - 400: WRONG_PHASE, PHASE_ENDED, INVALID_RATING, CANNOT_RATE_OWN
 * - 401: Invalid API key
 * - 403: Not a participant
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

// Request body schema
const RequestSchema = z.object({
  chat_id: z.number().int().positive("Chat ID must be a positive integer"),
  ratings: z.record(
    z.string(),
    z.number().min(0, "Rating must be at least 0").max(100, "Rating must be at most 100")
  ),
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

  // Parse request body first
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

  const { chat_id, ratings } = validationResult.data;

  if (Object.keys(ratings).length === 0) {
    return corsErrorResponse(
      "At least one rating is required",
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
    key: `agent:rate:${authResult.agentId}`,
    ...AgentRateLimits.rate,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-RATE] Rate limited agent: ${authResult.agentName}`);
    return rateLimitResponse(rateLimit);
  }

  try {
    console.log(
      `[AGENT-RATE] Agent ${authResult.agentName} rating in chat ${chat_id}`
    );

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
      console.error("[AGENT-RATE] Error getting cycle:", cycleError);
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
      console.error("[AGENT-RATE] Error getting round:", roundError);
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
    if (currentRound.phase !== "rating") {
      return corsErrorResponse(
        `Cannot rate during "${currentRound.phase}" phase`,
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
          "Rating phase has ended, waiting for transition",
          req,
          400,
          AgentErrorCodes.PHASE_ENDED
        );
      }
    }

    // Get all propositions for this round
    const { data: propositions, error: propsError } = await supabase
      .from("propositions")
      .select("id, participant_id")
      .eq("round_id", currentRound.id);

    if (propsError) {
      console.error("[AGENT-RATE] Error getting propositions:", propsError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // Create a map of valid proposition IDs
    const propositionMap = new Map<number, number | null>();
    for (const p of propositions) {
      propositionMap.set(p.id, p.participant_id);
    }

    // Validate each rating
    const ratingsToInsert: Array<{
      proposition_id: number;
      participant_id: number;
      round_id: number;
      grid_position: number;
    }> = [];

    for (const [propIdStr, score] of Object.entries(ratings)) {
      const propId = parseInt(propIdStr, 10);

      if (isNaN(propId)) {
        return corsErrorResponse(
          `Invalid proposition ID: ${propIdStr}`,
          req,
          400,
          AgentErrorCodes.INVALID_RATING
        );
      }

      if (!propositionMap.has(propId)) {
        return corsErrorResponse(
          `Proposition ${propId} does not exist in this round`,
          req,
          400,
          AgentErrorCodes.INVALID_RATING
        );
      }

      // Check if trying to rate own proposition
      const propParticipantId = propositionMap.get(propId);
      if (propParticipantId === authResult.participantId) {
        return corsErrorResponse(
          `Cannot rate your own proposition (ID: ${propId})`,
          req,
          400,
          AgentErrorCodes.CANNOT_RATE_OWN
        );
      }

      ratingsToInsert.push({
        proposition_id: propId,
        participant_id: authResult.participantId!,
        round_id: currentRound.id,
        grid_position: score,
      });
    }

    // Upsert ratings (update if exists, insert if not)
    const { error: upsertError } = await supabase.from("grid_rankings").upsert(
      ratingsToInsert,
      {
        onConflict: "round_id,proposition_id,participant_id",
        ignoreDuplicates: false,
      }
    );

    if (upsertError) {
      console.error("[AGENT-RATE] Error upserting ratings:", upsertError);
      return corsErrorResponse(
        "Failed to save ratings",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // Calculate rating progress
    const otherPropositions = propositions.filter(
      (p) => p.participant_id !== authResult.participantId
    );

    // Get total ratings submitted by this agent
    const { count: totalRated, error: countError } = await supabase
      .from("grid_rankings")
      .select("id", { count: "exact", head: true })
      .eq("round_id", currentRound.id)
      .eq("participant_id", authResult.participantId);

    if (countError) {
      console.error("[AGENT-RATE] Error counting ratings:", countError);
    }

    const ratedCount = totalRated ?? ratingsToInsert.length;
    const totalToRate = otherPropositions.length;
    const isComplete = ratedCount >= totalToRate;

    console.log(
      `[AGENT-RATE] Agent ${authResult.agentName} rated ${ratingsToInsert.length} propositions (${ratedCount}/${totalToRate} complete)`
    );

    return corsJsonResponse(
      {
        success: true,
        rated_count: ratedCount,
        total_to_rate: totalToRate,
        is_complete: isComplete,
      },
      req,
      200
    );
  } catch (error) {
    console.error("[AGENT-RATE] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
