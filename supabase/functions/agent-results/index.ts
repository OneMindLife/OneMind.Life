/**
 * Edge Function: agent-results
 *
 * Get results from completed rounds.
 *
 * GET /agent-results?chat_id=87
 * Headers: Authorization: Bearer onemind_sk_...
 *
 * Returns:
 * - 200: { chat_id, consensus_reached, consecutive_sole_wins, last_round, consensus_history }
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

  // Rate limit by agent ID
  const rateLimiter = new RateLimiter(supabase);
  const rateLimit = await rateLimiter.check({
    key: `agent:results:${authResult.agentId}`,
    ...AgentRateLimits.results,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-RESULTS] Rate limited agent: ${authResult.agentName}`);
    return rateLimitResponse(rateLimit);
  }

  try {
    console.log(
      `[AGENT-RESULTS] Agent ${authResult.agentName} checking results for chat ${chatId}`
    );

    // Get chat settings
    const { data: chat, error: chatError } = await supabase
      .from("chats")
      .select("id, name, confirmation_rounds")
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

    const roundsForConsensus = chat.confirmation_rounds ?? 2;

    // Get all completed cycles with their winning propositions
    const { data: completedCycles, error: cyclesError } = await supabase
      .from("cycles")
      .select(
        `
        id,
        winning_proposition_id,
        completed_at,
        propositions!cycles_winning_proposition_id_fkey (
          id,
          content
        )
      `
      )
      .eq("chat_id", chatId)
      .not("completed_at", "is", null)
      .order("completed_at", { ascending: false });

    if (cyclesError) {
      console.error("[AGENT-RESULTS] Error getting cycles:", cyclesError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // Get current (active) cycle
    const { data: currentCycle, error: currentCycleError } = await supabase
      .from("cycles")
      .select("id")
      .eq("chat_id", chatId)
      .is("completed_at", null)
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (currentCycleError) {
      console.error("[AGENT-RESULTS] Error getting current cycle:", currentCycleError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // Get last completed round with winner info
    let lastRound = null;
    let consecutiveSoleWins = 0;

    if (currentCycle) {
      // Get completed rounds from current cycle to check consecutive wins
      const { data: completedRounds, error: roundsError } = await supabase
        .from("rounds")
        .select(
          `
          id,
          custom_id,
          completed_at,
          round_winners (
            proposition_id,
            global_score,
            is_sole_winner,
            propositions (
              id,
              content
            )
          )
        `
        )
        .eq("cycle_id", currentCycle.id)
        .not("completed_at", "is", null)
        .order("custom_id", { ascending: false });

      if (roundsError) {
        console.error("[AGENT-RESULTS] Error getting rounds:", roundsError);
      } else if (completedRounds && completedRounds.length > 0) {
        // Get the last completed round
        const lastCompletedRound = completedRounds[0];
        const winners = lastCompletedRound.round_winners || [];

        lastRound = {
          id: lastCompletedRound.id,
          round_number: lastCompletedRound.custom_id,
          completed_at: lastCompletedRound.completed_at,
          winners: winners.map((w: { proposition_id: number; global_score: number; is_sole_winner: boolean; propositions: { id: number; content: string } }) => ({
            proposition_id: w.proposition_id,
            content: w.propositions?.content,
            global_score: w.global_score,
            is_sole_winner: w.is_sole_winner,
          })),
        };

        // Count consecutive sole wins for the same proposition
        if (winners.length === 1 && winners[0].is_sole_winner) {
          const winningPropId = winners[0].proposition_id;
          consecutiveSoleWins = 1;

          // Check previous rounds
          for (let i = 1; i < completedRounds.length; i++) {
            const round = completedRounds[i];
            const roundWinners = round.round_winners || [];

            if (
              roundWinners.length === 1 &&
              roundWinners[0].is_sole_winner &&
              roundWinners[0].proposition_id === winningPropId
            ) {
              consecutiveSoleWins++;
            } else {
              break;
            }
          }
        }
      }
    }

    // Format consensus history
    const consensusHistory = completedCycles.map((cycle: { id: number; completed_at: string; winning_proposition_id: number; propositions: { id: number; content: string } }) => ({
      cycle_id: cycle.id,
      completed_at: cycle.completed_at,
      winning_proposition: cycle.propositions
        ? {
            id: cycle.propositions.id,
            content: cycle.propositions.content,
          }
        : null,
    }));

    // Check if consensus has been reached in current cycle
    const consensusReached = consecutiveSoleWins >= roundsForConsensus;

    return corsJsonResponse(
      {
        chat_id: chatId,
        consensus_reached: consensusReached,
        consecutive_sole_wins: consecutiveSoleWins,
        rounds_for_consensus: roundsForConsensus,
        last_round: lastRound,
        consensus_history: consensusHistory,
      },
      req,
      200
    );
  } catch (error) {
    console.error("[AGENT-RESULTS] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
