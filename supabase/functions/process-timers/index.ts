// Edge Function: process-timers
// Runs on a schedule (every minute) to handle timer-based phase transitions
//
// Responsibilities:
// 1. Check for expired timers and advance/extend phases
// 2. Check for auto-advance thresholds being met
// 3. Handle auto-start when participant count reached

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { shouldAutoAdvance, shouldAutoAdvanceRating } from "../_shared/auto-advance.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Secret for cron job authentication (optional for local dev - service role also works)
const CRON_SECRET = Deno.env.get("CRON_SECRET");

if (!CRON_SECRET) {
  console.warn("CRON_SECRET not set - only service role auth will work");
}

interface Chat {
  id: number;
  proposing_duration_seconds: number;
  rating_duration_seconds: number;
  proposing_minimum: number;
  rating_minimum: number;
  proposing_threshold_percent: number | null;
  proposing_threshold_count: number | null;
  rating_threshold_percent: number | null;
  rating_threshold_count: number | null;
  start_mode: string;
  rating_start_mode: string; // 'auto' or 'manual' - controls how rating starts after proposing
  auto_start_participant_count: number;
  // Adaptive duration settings (uses early advance thresholds for calculation)
  adaptive_duration_enabled: boolean;
  adaptive_adjustment_percent: number;
  min_phase_duration_seconds: number;
  max_phase_duration_seconds: number;
}

interface Round {
  id: number;
  cycle_id: number;
  custom_id: number;
  phase: string;
  phase_started_at: string | null;
  phase_ends_at: string | null;
}

interface ProcessResult {
  rounds_checked: number;
  phases_advanced: number;
  timers_extended: number;
  auto_started: number;
  errors: string[];
}

// =============================================================================
// ROUND-MINUTE TIMER ALIGNMENT
// =============================================================================
// Calculate phase end time rounded up to next :00 seconds.
// Aligns timer expiration with cron job schedule (every minute at :00).
// Example: now=1:00:42, duration=60s → 1:02:00 (not 1:01:42)
// =============================================================================

function calculateRoundMinuteEnd(now: Date, durationSeconds: number): Date {
  // Truncate milliseconds first to avoid extra rounding
  const nowTruncated = new Date(now);
  nowTruncated.setMilliseconds(0);

  const minEnd = new Date(nowTruncated.getTime() + durationSeconds * 1000);
  // If already at :00, use that; otherwise round up to next minute
  if (minEnd.getSeconds() === 0) {
    return minEnd;
  }
  // Round up: set seconds and ms to 0, add 1 minute
  const rounded = new Date(minEnd);
  rounded.setSeconds(0, 0);
  rounded.setMinutes(rounded.getMinutes() + 1);
  return rounded;
}

Deno.serve(async (req: Request) => {
  // ==========================================================================
  // AUTH VERIFICATION
  // Only allow requests from cron job (with secret) or service role
  // ==========================================================================
  const authHeader = req.headers.get("Authorization");
  const cronSecret = req.headers.get("X-Cron-Secret");

  // Check if it's a valid cron request or service role request
  const isValidCron = CRON_SECRET && cronSecret === CRON_SECRET;

  // For service role check, extract token from "Bearer <token>" and compare
  const token = authHeader?.replace("Bearer ", "");
  const isServiceRole = token === supabaseServiceKey;

  // Also allow local development (localhost or internal Docker URLs)
  const isLocalDev = supabaseUrl.includes("localhost") ||
                     supabaseUrl.includes("127.0.0.1") ||
                     supabaseUrl.includes("kong:8000");

  if (!isValidCron && !isServiceRole && !isLocalDev) {
    console.log("Auth failed:", {
      hasAuthHeader: !!authHeader,
      hasCronSecret: !!cronSecret,
      isLocalDev,
      urlPrefix: supabaseUrl.substring(0, 30)
    });
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);
  const now = new Date();

  const result: ProcessResult = {
    rounds_checked: 0,
    phases_advanced: 0,
    timers_extended: 0,
    auto_started: 0,
    errors: [],
  };

  // Start cron execution logging
  let executionId: number | null = null;
  try {
    const { data } = await supabase.rpc("cron_execution_start", {
      p_job_name: "process-timers",
      p_metadata: { triggered_at: now.toISOString() },
    });
    executionId = data;
  } catch (e) {
    console.warn("Failed to log cron start:", e);
  }

  try {
    // 1. Process expired timers
    await processExpiredTimers(supabase, now, result);

    // 2. Check auto-advance thresholds
    await processAutoAdvance(supabase, now, result);

    // 3. Check auto-start for waiting rounds
    await processAutoStart(supabase, result);

    // Log successful completion
    if (executionId) {
      try {
        await supabase.rpc("cron_execution_complete", {
          p_execution_id: executionId,
          p_status: "success",
          p_result_code: 200,
        });
      } catch (e) {
        console.warn("Failed to log cron complete:", e);
      }
    }

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    result.errors.push(`Fatal error: ${error.message}`);

    // Log error completion
    if (executionId) {
      try {
        await supabase.rpc("cron_execution_complete", {
          p_execution_id: executionId,
          p_status: "error",
          p_result_code: 500,
          p_error_message: error.message,
        });
      } catch (e) {
        console.warn("Failed to log cron error:", e);
      }
    }

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});

// =============================================================================
// PROCESS EXPIRED TIMERS
// =============================================================================

async function processExpiredTimers(
  supabase: ReturnType<typeof createClient>,
  now: Date,
  result: ProcessResult
) {
  // Find all rounds with expired timers
  const { data: expiredRounds, error } = await supabase
    .from("rounds")
    .select(
      `
      id,
      cycle_id,
      custom_id,
      phase,
      phase_started_at,
      phase_ends_at,
      cycles!inner (
        chat_id,
        chats!inner (
          id,
          start_mode,
          rating_start_mode,
          proposing_duration_seconds,
          rating_duration_seconds,
          proposing_minimum,
          rating_minimum,
          adaptive_duration_enabled,
          adaptive_adjustment_percent,
          min_phase_duration_seconds,
          max_phase_duration_seconds
        )
      )
    `
    )
    .in("phase", ["proposing", "rating"])
    .not("phase_ends_at", "is", null)
    .lt("phase_ends_at", now.toISOString())
    .is("completed_at", null);

  if (error) {
    result.errors.push(`Error fetching expired rounds: ${error.message}`);
    return;
  }

  if (!expiredRounds || expiredRounds.length === 0) {
    return;
  }

  result.rounds_checked = expiredRounds.length;

  for (const round of expiredRounds) {
    try {
      const chat = (round as any).cycles.chats as Chat;

      // Skip auto-advance for manual mode - host controls everything
      if (chat.start_mode === "manual") {
        continue;
      }

      const isProposing = round.phase === "proposing";

      // Check if minimum is met
      const minimumMet = await checkMinimumMet(
        supabase,
        round.id,
        chat,
        isProposing
      );

      if (minimumMet) {
        // Advance to next phase
        await advancePhase(supabase, round, chat);
        result.phases_advanced++;
      } else {
        // Extend timer
        await extendTimer(supabase, round, chat, isProposing);
        result.timers_extended++;
      }
    } catch (err) {
      result.errors.push(
        `Error processing round ${round.id}: ${err.message}`
      );
    }
  }
}

// =============================================================================
// CHECK MINIMUM MET
// =============================================================================

async function checkMinimumMet(
  supabase: ReturnType<typeof createClient>,
  roundId: number,
  chat: Chat,
  isProposing: boolean
): Promise<boolean> {
  if (isProposing) {
    // Count NEW HUMAN propositions for this round (exclude carried forward AND AI)
    // AI propositions (participant_id IS NULL) don't count toward minimum
    const { count: propositionCount, error } = await supabase
      .from("propositions")
      .select("id", { count: "exact", head: true })
      .eq("round_id", roundId)
      .is("carried_from_id", null)
      .not("participant_id", "is", null);

    if (error) throw error;

    // Always enforce proposing_minimum as the floor - no dynamic adjustment
    // This ensures meaningful consensus (at least 3 propositions to compare)
    // If not enough participants/propositions, timer extends until more join
    return (propositionCount || 0) >= chat.proposing_minimum;
  } else {
    // Rating phase: check average raters per proposition using grid_rankings
    const { data: propositions, error: propError } = await supabase
      .from("propositions")
      .select("id")
      .eq("round_id", roundId);

    if (propError) throw propError;
    if (!propositions || propositions.length === 0) return false;

    // Count grid rankings for this round (each ranking = one user rating one proposition)
    const { count: totalRankings, error: rankingError } = await supabase
      .from("grid_rankings")
      .select("id", { count: "exact", head: true })
      .eq("round_id", roundId);

    if (rankingError) throw rankingError;

    const avgRatersPerProposition =
      (totalRankings || 0) / propositions.length;
    return avgRatersPerProposition >= chat.rating_minimum;
  }
}

// =============================================================================
// ADVANCE PHASE
// =============================================================================

async function advancePhase(
  supabase: ReturnType<typeof createClient>,
  round: Round,
  chat: Chat
) {
  const now = new Date();

  if (round.phase === "proposing") {
    // Check if rating_start_mode is manual - go to waiting instead of rating
    if (chat.rating_start_mode === "manual") {
      console.log(`Round ${round.id}: rating_start_mode=manual, advancing to waiting`);
      const { error } = await supabase
        .from("rounds")
        .update({
          phase: "waiting",
          phase_started_at: now.toISOString(),
          phase_ends_at: null, // No timer in waiting phase
        })
        .eq("id", round.id);

      if (error) throw error;
      return;
    }

    // Advance to rating phase (round up to next :00 for cron alignment)
    const phaseEndsAt = calculateRoundMinuteEnd(now, chat.rating_duration_seconds);

    const { error } = await supabase
      .from("rounds")
      .update({
        phase: "rating",
        phase_started_at: now.toISOString(),
        phase_ends_at: phaseEndsAt.toISOString(),
      })
      .eq("id", round.id);

    if (error) throw error;
  } else if (round.phase === "rating") {
    // Calculate winner and complete round
    await calculateWinnerAndComplete(supabase, round);
  }
}

// =============================================================================
// CALCULATE WINNER AND COMPLETE (using MOVDA algorithm)
// =============================================================================
// Supports multiple tied winners:
// - All tied propositions are stored in round_winners table
// - is_sole_winner flag indicates if win counts toward consensus
// - winning_proposition_id stores oldest among ties for backward compat
// =============================================================================

async function calculateWinnerAndComplete(
  supabase: ReturnType<typeof createClient>,
  round: Round
) {
  // Get all propositions for this round (ordered by creation time for tie-breaker)
  const { data: propositions, error: propError } = await supabase
    .from("propositions")
    .select("id, created_at")
    .eq("round_id", round.id)
    .order("created_at", { ascending: true });

  if (propError) throw propError;
  if (!propositions || propositions.length === 0) {
    throw new Error("No propositions to calculate winner");
  }

  // Calculate MOVDA scores for this round
  // This processes all grid_rankings and computes Elo-style ratings
  const { error: movdaError } = await supabase.rpc(
    "calculate_movda_scores_for_round",
    { p_round_id: round.id }
  );

  if (movdaError) {
    console.error(`MOVDA calculation error: ${movdaError.message}`);
    throw movdaError;
  }

  // Get MOVDA scores from proposition_global_scores
  const { data: scores, error: scoresError } = await supabase
    .from("proposition_global_scores")
    .select("proposition_id, global_score")
    .eq("round_id", round.id)
    .order("global_score", { ascending: false });

  if (scoresError) throw scoresError;

  let primaryWinnerId: number;
  let isSoleWinner: boolean;
  let tiedWinners: Array<{ proposition_id: number; global_score: number }>;

  if (!scores || scores.length === 0) {
    // No grid rankings submitted - fall back to oldest proposition (sole winner)
    console.warn(`No MOVDA scores for round ${round.id}, using oldest proposition`);
    primaryWinnerId = propositions[0].id;
    isSoleWinner = true;
    tiedWinners = [{ proposition_id: propositions[0].id, global_score: 0 }];
  } else {
    // Find ALL propositions tied for first place
    const topScore = scores[0].global_score;
    const SCORE_TOLERANCE = 0.001;
    tiedWinners = scores.filter(
      (s) => Math.abs(s.global_score - topScore) < SCORE_TOLERANCE
    );

    isSoleWinner = tiedWinners.length === 1;

    if (isSoleWinner) {
      primaryWinnerId = tiedWinners[0].proposition_id;
      console.log(`Sole winner: proposition ${primaryWinnerId} with score ${topScore}`);
    } else {
      // Multiple tied winners - primary is oldest for backward compat
      const tiedIds = new Set(tiedWinners.map((w) => w.proposition_id));
      const oldestTied = propositions.find((p) => tiedIds.has(p.id));
      primaryWinnerId = oldestTied?.id || tiedWinners[0].proposition_id;
      console.log(
        `TIE DETECTED: ${tiedWinners.length} propositions tied at ${topScore}. ` +
        `Primary (oldest): ${primaryWinnerId}. ` +
        `All tied: [${tiedWinners.map((w) => w.proposition_id).join(", ")}]`
      );
    }
  }

  // Insert ALL tied winners into round_winners table
  const { error: insertError } = await supabase.from("round_winners").insert(
    tiedWinners.map((w) => ({
      round_id: round.id,
      proposition_id: w.proposition_id,
      rank: 1,
      global_score: w.global_score,
    }))
  );

  if (insertError) {
    console.error(`Failed to insert round_winners: ${insertError.message}`);
    throw insertError;
  }

  // Update round with winner and is_sole_winner flag
  // This triggers on_round_winner_set which handles consecutive wins logic
  // NOTE: Trigger only counts toward consensus if is_sole_winner = TRUE
  const { error } = await supabase
    .from("rounds")
    .update({
      winning_proposition_id: primaryWinnerId,
      is_sole_winner: isSoleWinner,
      completed_at: new Date().toISOString(),
    })
    .eq("id", round.id);

  if (error) throw error;

  console.log(
    `Round ${round.id} complete. ` +
    `Winner(s): ${tiedWinners.length}, ` +
    `Primary: ${primaryWinnerId}, ` +
    `Sole: ${isSoleWinner}`
  );

  // Apply adaptive duration adjustment for next round
  await applyAdaptiveDuration(supabase, round.id);
}

// =============================================================================
// APPLY ADAPTIVE DURATION
// =============================================================================
// After a round completes, adjust phase durations based on participation:
// - If participation >= threshold: decrease duration by X%
// - If participation < threshold: increase duration by X%
// =============================================================================

async function applyAdaptiveDuration(
  supabase: ReturnType<typeof createClient>,
  roundId: number
) {
  try {
    const { data, error } = await supabase.rpc("apply_adaptive_duration", {
      p_round_id: roundId,
    });

    if (error) {
      console.error(`Adaptive duration error: ${error.message}`);
      return;
    }

    if (data && data.length > 0) {
      const result = data[0];
      if (result.adjustment_applied !== "disabled") {
        console.log(
          `Adaptive duration applied for round ${roundId}: ` +
          `participation=${result.participation_used}/${result.threshold}, ` +
          `adjustment=${result.adjustment_applied}, ` +
          `new_proposing=${result.new_proposing_duration}s, ` +
          `new_rating=${result.new_rating_duration}s`
        );
      }
    }
  } catch (err) {
    // Don't fail round completion if adaptive duration fails
    console.error(`Adaptive duration exception: ${err.message}`);
  }
}

// =============================================================================
// EXTEND TIMER
// =============================================================================

async function extendTimer(
  supabase: ReturnType<typeof createClient>,
  round: Round,
  chat: Chat,
  isProposing: boolean
) {
  const now = new Date();
  const extensionSeconds = isProposing
    ? chat.proposing_duration_seconds
    : chat.rating_duration_seconds;

  // Round up to next :00 for cron alignment
  const newPhaseEndsAt = calculateRoundMinuteEnd(now, extensionSeconds);

  const { error } = await supabase
    .from("rounds")
    .update({
      phase_ends_at: newPhaseEndsAt.toISOString(),
    })
    .eq("id", round.id);

  if (error) throw error;
}

// =============================================================================
// PROCESS AUTO-ADVANCE (EARLY ADVANCE WHEN THRESHOLDS MET)
// =============================================================================

async function processAutoAdvance(
  supabase: ReturnType<typeof createClient>,
  now: Date,
  result: ProcessResult
) {
  // Find all active rounds that haven't expired yet
  const { data: activeRounds, error } = await supabase
    .from("rounds")
    .select(
      `
      id,
      cycle_id,
      custom_id,
      phase,
      phase_started_at,
      phase_ends_at,
      cycles!inner (
        chat_id,
        chats!inner (
          id,
          proposing_minimum,
          rating_minimum,
          proposing_threshold_percent,
          proposing_threshold_count,
          rating_threshold_percent,
          rating_threshold_count,
          rating_duration_seconds,
          rating_start_mode
        )
      )
    `
    )
    .in("phase", ["proposing", "rating"])
    .gt("phase_ends_at", now.toISOString())
    .is("completed_at", null);

  if (error) {
    result.errors.push(`Error fetching active rounds: ${error.message}`);
    return;
  }

  if (!activeRounds || activeRounds.length === 0) {
    return;
  }

  for (const round of activeRounds) {
    try {
      const chat = (round as any).cycles.chats as Chat;
      const isProposing = round.phase === "proposing";

      // Check if auto-advance thresholds are configured
      const thresholdPercent = isProposing
        ? chat.proposing_threshold_percent
        : chat.rating_threshold_percent;
      const thresholdCount = isProposing
        ? chat.proposing_threshold_count
        : chat.rating_threshold_count;

      // Skip if no thresholds configured
      if (thresholdPercent === null && thresholdCount === null) {
        continue;
      }

      // Check if thresholds are met
      const thresholdsMet = await checkThresholdsMet(
        supabase,
        round,
        chat,
        isProposing
      );

      // Also check minimum is met
      const minimumMet = await checkMinimumMet(
        supabase,
        round.id,
        chat,
        isProposing
      );

      if (thresholdsMet && minimumMet) {
        await advancePhase(supabase, round as Round, chat);
        result.phases_advanced++;
      }
    } catch (err) {
      result.errors.push(
        `Error checking auto-advance for round ${round.id}: ${err.message}`
      );
    }
  }
}

// =============================================================================
// CHECK THRESHOLDS MET
// =============================================================================

async function checkThresholdsMet(
  supabase: ReturnType<typeof createClient>,
  round: any,
  chat: Chat,
  isProposing: boolean
): Promise<boolean> {
  const chatId = (round as any).cycles.chat_id;

  // Get participant count
  const { count: participantCount, error: partError } = await supabase
    .from("participants")
    .select("id", { count: "exact", head: true })
    .eq("chat_id", chatId)
    .eq("status", "active");

  if (partError) throw partError;
  if (!participantCount || participantCount === 0) return false;

  const thresholdPercent = isProposing
    ? chat.proposing_threshold_percent
    : chat.rating_threshold_percent;
  const thresholdCount = isProposing
    ? chat.proposing_threshold_count
    : chat.rating_threshold_count;

  // Get participated count based on phase
  let participatedCount: number;
  let skipCount = 0;

  if (isProposing) {
    // Count unique HUMAN proposers (exclude carried forward AND AI)
    // AI propositions (participant_id IS NULL) don't count toward threshold
    const { data: propositions, error } = await supabase
      .from("propositions")
      .select("participant_id")
      .eq("round_id", round.id)
      .is("carried_from_id", null)
      .not("participant_id", "is", null);

    if (error) throw error;

    const uniqueSubmitters = new Set(propositions?.map((p) => p.participant_id)).size;

    // Count skips for this round
    const { count: skips, error: skipError } = await supabase
      .from("round_skips")
      .select("id", { count: "exact", head: true })
      .eq("round_id", round.id);

    if (skipError) throw skipError;
    skipCount = skips || 0;

    // Participated = unique submitters + skippers
    participatedCount = uniqueSubmitters + skipCount;

    // For count threshold, use dynamic adjustment
    // effective_threshold = MIN(host_setting, max_possible)
    const maxPossible = participantCount - skipCount;

    // Calculate percent-based requirement
    const percentRequired = thresholdPercent !== null
      ? Math.ceil((participantCount * thresholdPercent) / 100)
      : 0;

    // Calculate effective count threshold
    const effectiveCountThreshold = thresholdCount !== null
      ? Math.min(thresholdCount, maxPossible)
      : 0;

    // Check if thresholds met:
    // 1. Participated (submitters + skippers) >= percent requirement
    // 2. Propositions (uniqueSubmitters) >= effective count threshold
    const percentMet = participatedCount >= percentRequired;
    const countMet = uniqueSubmitters >= effectiveCountThreshold;

    console.log(`[checkThresholdsMet] Round ${round.id}: ${uniqueSubmitters} submitters + ${skipCount} skips = ${participatedCount} participated. ` +
                `Percent: ${participatedCount} >= ${percentRequired}? ${percentMet}. Count: ${uniqueSubmitters} >= ${effectiveCountThreshold}? ${countMet}`);

    return percentMet && countMet;
  } else {
    // Count unique raters
    const { data: propositions, error: propError } = await supabase
      .from("propositions")
      .select("id")
      .eq("round_id", round.id);

    if (propError) throw propError;
    if (!propositions || propositions.length === 0) return false;

    const { data: ratings, error: ratingError } = await supabase
      .from("ratings")
      .select("participant_id")
      .in(
        "proposition_id",
        propositions.map((p) => p.id)
      );

    if (ratingError) throw ratingError;

    participatedCount = new Set(ratings?.map((r) => r.participant_id)).size;

    // Use rating-specific helper that caps threshold to (participants - 1)
    // since users can't rate their own propositions
    return shouldAutoAdvanceRating(
      { thresholdPercent, thresholdCount },
      { totalParticipants: participantCount, participatedCount }
    );
  }
}

// =============================================================================
// PROCESS AUTO-START (START PHASE WHEN PARTICIPANT COUNT REACHED)
// =============================================================================

async function processAutoStart(
  supabase: ReturnType<typeof createClient>,
  result: ProcessResult
) {
  // Find all waiting rounds with auto-start enabled
  const { data: waitingRounds, error } = await supabase
    .from("rounds")
    .select(
      `
      id,
      cycle_id,
      cycles!inner (
        chat_id,
        chats!inner (
          id,
          start_mode,
          auto_start_participant_count,
          proposing_duration_seconds
        )
      )
    `
    )
    .eq("phase", "waiting")
    .is("completed_at", null);

  if (error) {
    result.errors.push(`Error fetching waiting rounds: ${error.message}`);
    return;
  }

  if (!waitingRounds || waitingRounds.length === 0) {
    return;
  }

  for (const round of waitingRounds) {
    try {
      const chat = (round as any).cycles.chats as Chat;

      // Skip if not auto-start mode
      if (chat.start_mode !== "auto") {
        continue;
      }

      // Check if this round has NEW propositions (not carried forward) - if so, it's waiting for RATING
      // (from rating_start_mode=manual), not waiting for proposing to START
      // Carried forward propositions are from the previous round's winner and don't count
      const { count: propositionCount, error: propError } = await supabase
        .from("propositions")
        .select("id", { count: "exact", head: true })
        .eq("round_id", round.id)
        .is("carried_from_id", null); // Only count NEW propositions, not carried forward

      if (propError) throw propError;

      if ((propositionCount || 0) > 0) {
        // Round has NEW propositions - it's waiting for rating, not auto-start
        console.log(`Round ${round.id}: has ${propositionCount} new propositions, skipping auto-start (waiting for rating)`);
        continue;
      }

      const chatId = (round as any).cycles.chat_id;

      // Count active participants
      const { count: participantCount, error: partError } = await supabase
        .from("participants")
        .select("id", { count: "exact", head: true })
        .eq("chat_id", chatId)
        .eq("status", "active");

      if (partError) throw partError;

      // Check if threshold reached
      if ((participantCount || 0) >= chat.auto_start_participant_count) {
        const now = new Date();
        // Round up to next :00 for cron alignment
        const phaseEndsAt = calculateRoundMinuteEnd(now, chat.proposing_duration_seconds);

        const { error: updateError } = await supabase
          .from("rounds")
          .update({
            phase: "proposing",
            phase_started_at: now.toISOString(),
            phase_ends_at: phaseEndsAt.toISOString(),
          })
          .eq("id", round.id);

        if (updateError) throw updateError;

        result.auto_started++;
      }
    } catch (err) {
      result.errors.push(
        `Error checking auto-start for round ${round.id}: ${err.message}`
      );
    }
  }
}
