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
import { scoresToPairwiseRows } from "../_shared/pairwise.ts";

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

    // Rating mode decides HOW the scores are recorded: grid mode upserts
    // grid_rankings; matches mode converts scores into pairwise votes — the
    // same match-by-match rows humans cast.
    const { data: chatRow, error: chatError } = await supabase
      .from("chats")
      .select("rating_mode")
      .eq("id", chat_id)
      .single();

    if (chatError) {
      console.error("[AGENT-RATE] Error getting chat:", chatError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }
    const isMatchesMode = chatRow?.rating_mode === "matches";

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

    // Conditional self-inclusion: a rater normally can't rate their own
    // proposition, EXCEPT when excluding it would leave them under 2 votable
    // props (<= 2-prop rounds). Mirrors get_least_rated_propositions.
    const nonOwnCount = propositions.filter(
      (p) => p.participant_id !== authResult.participantId
    ).length;
    const selfRatingAllowed = nonOwnCount < 2;

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

      // Check if trying to rate own proposition (allowed in conditional
      // self-inclusion rounds, where everyone rates everything)
      const propParticipantId = propositionMap.get(propId);
      if (propParticipantId === authResult.participantId && !selfRatingAllowed) {
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

    // Votable set = non-own props, or ALL props in conditional-self-inclusion
    // rounds. Used for progress in both modes.
    const otherPropositions = selfRatingAllowed
      ? propositions
      : propositions.filter(
          (p) => p.participant_id !== authResult.participantId
        );

    if (isMatchesMode) {
      // Matches mode: record match-by-match votes, exactly like a human —
      // one pairwise_comparisons row per unordered pair (winner = the
      // higher-scored prop, equal = tie) plus a rating_completions row.
      // The 0-100 request contract is unchanged for callers; only the
      // recording differs. Grid rows are NOT written (they'd only feed the
      // grid-based advance math, which matches rounds don't use).
      const pairRows = scoresToPairwiseRows(
        ratingsToInsert.map((r) => ({
          propositionId: r.proposition_id,
          score: r.grid_position,
        })),
        currentRound.id,
        authResult.participantId!
      );

      if (pairRows.length > 0) {
        const { error: pairError } = await supabase
          .from("pairwise_comparisons")
          .insert(pairRows);
        // 23505 = this agent already voted these pairs (idempotent re-run).
        if (pairError && pairError.code !== "23505") {
          console.error("[AGENT-RATE] Error inserting pairwise votes:", pairError);
          return corsErrorResponse(
            "Failed to save votes",
            req,
            500,
            AgentErrorCodes.DB_ERROR
          );
        }
      }

      // Completion marker — drives matches progress, finalize triggers, and
      // the "who's done" UI. Only once the agent has scored its full votable
      // set (a partial SDK submission must not read as "done"). Idempotent.
      const coveredAll = ratingsToInsert.length >= otherPropositions.length;
      if (coveredAll) {
        const { error: completionError } = await supabase
          .from("rating_completions")
          .insert({
            round_id: currentRound.id,
            participant_id: authResult.participantId,
            chat_id,
          });
        if (completionError && completionError.code !== "23505") {
          console.error("[AGENT-RATE] Error inserting completion:", completionError);
          return corsErrorResponse(
            "Failed to save completion",
            req,
            500,
            AgentErrorCodes.DB_ERROR
          );
        }
      }

      console.log(
        `[AGENT-RATE] Agent ${authResult.agentName} cast ${pairRows.length} pairwise votes (matches mode)${coveredAll ? " and completed" : ""}`
      );

      return corsJsonResponse(
        {
          success: true,
          rated_count: ratingsToInsert.length,
          total_to_rate: otherPropositions.length,
          is_complete: coveredAll,
        },
        req,
        200
      );
    }

    // Grid mode: upsert ratings (update if exists, insert if not)
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
