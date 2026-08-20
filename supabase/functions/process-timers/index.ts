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
import {
  autoAdvanceGateOpen,
  distinctRaterCount,
  matchesTimerMinimumMet,
  shouldEarlyAdvanceMatches,
} from "../_shared/matches-advance.ts";
import {
  treeIdleSeconds,
  treeProposingAction,
  treeRatingAction,
} from "../_shared/tree-advance.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Secret for cron job authentication (optional for local dev - service role also works)
const CRON_SECRET = Deno.env.get("CRON_SECRET");

if (!CRON_SECRET) {
  console.warn("CRON_SECRET not set - only service role auth will work");
}

interface Chat {
  id: number;
  name: string;
  proposing_duration_seconds: number;
  rating_duration_seconds: number;
  proposing_minimum: number;
  rating_minimum: number;
  proposing_threshold_percent: number | null;
  proposing_threshold_count: number | null;
  rating_threshold_percent: number | null;
  rating_threshold_count: number | null;
  rating_mode: string; // 'grid' or 'matches'
  start_mode: string;
  rating_start_mode: string; // 'auto' or 'manual' - controls how rating starts after proposing
  auto_start_participant_count: number;
  // Adaptive duration settings (uses early advance thresholds for calculation)
  adaptive_duration_enabled: boolean;
  adaptive_adjustment_percent: number;
  min_phase_duration_seconds: number;
  max_phase_duration_seconds: number;
  // Pause state — process-timers must skip paused chats
  host_paused: boolean;
  schedule_paused: boolean;
  // Never-empty AI-seat-filled arena: advance proposing on the timer once the
  // agent board is votable (see checkMinimumMet), so a present human always gets
  // the full proposing window and pure-agent/lurking rounds never stall.
  is_arena: boolean;
  // Repository mode: never seal. At rating-expiry we reopen proposing instead
  // of completing the round, so the chat is always alive (Grow/Sort). See the
  // never_seals column (20260715 repository_mode_never_seals).
  never_seals: boolean;
}

function isChatPaused(chat: Chat): boolean {
  return chat.host_paused || chat.schedule_paused;
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
// Calculate phase end time snapped to a :00 second boundary.
// Aligns timer expiration with cron job schedule (every minute at :00).
//
// A phase can only END on a cron tick, so the achievable end times are the
// minute boundaries either side of (now + duration). We snap to the NEARER
// one when the overshoot is small: the cron invocation itself starts a second
// or two after :00, so `now + 60s` lands at :01-ish and always rounding UP
// silently doubled every 1-minute phase to ~2 minutes. Beyond the tolerance we
// still round up, so genuine cron lag never truncates a phase to a sliver.
// Example: now=1:00:01, duration=60s → 1:01:00 (59s), not 1:02:00 (119s)
// Example: now=1:00:42, duration=60s → 1:02:00 (78s) — past tolerance, round up
// Keep in sync with the SQL twin `calculate_round_minute_end()`.
// =============================================================================

// Max seconds we'll shave off a phase to land on the earlier boundary.
const PHASE_END_ALIGN_TOLERANCE_SECONDS = 15;

function calculateRoundMinuteEnd(now: Date, durationSeconds: number): Date {
  // Truncate milliseconds first to avoid extra rounding
  const nowTruncated = new Date(now);
  nowTruncated.setMilliseconds(0);

  const minEnd = new Date(nowTruncated.getTime() + durationSeconds * 1000);
  // If already at :00, use that
  if (minEnd.getSeconds() === 0) {
    return minEnd;
  }

  const floored = new Date(minEnd);
  floored.setSeconds(0, 0);

  // Within tolerance: snap back to the earlier boundary, but never to a time
  // that's already past (short durations can floor into the past).
  if (
    minEnd.getSeconds() <= PHASE_END_ALIGN_TOLERANCE_SECONDS &&
    floored.getTime() > now.getTime()
  ) {
    return floored;
  }

  // Otherwise round up: next minute boundary
  const rounded = new Date(floored);
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
// C15 TREE-NODE ROUNDS (child cycles) — clock-only window flips
// =============================================================================
// A node round lives on the chat-wide 12h/12h clock (docs/ONEMIND_CONCEPT.md
// C15). At its window end:
//   proposing: >= 2 props -> open the vote (next window); fewer -> idle to the
//     NEXT proposing window (skip over the voting window: + rating + proposing
//     durations). Props persist; the AI's single prop alone can't advance it.
//   rating: >= 1 real (non-skip) vote -> seal via complete_round_with_winner
//     (child cycles seal quietly — on_cycle_winner_set is gated); no votes ->
//     idle to the next voting window.

async function processTreeNodeRound(
  supabase: ReturnType<typeof createClient>,
  // deno-lint-ignore no-explicit-any
  round: any,
  chat: Chat,
  result: ProcessResult
) {
  const now = new Date();
  const idleSecs = treeIdleSeconds(
    chat.proposing_duration_seconds,
    chat.rating_duration_seconds,
  );

  if (round.phase === "proposing") {
    const { count: propCount } = await supabase
      .from("propositions")
      .select("id", { count: "exact", head: true })
      .eq("round_id", round.id);

    if (treeProposingAction(propCount ?? 0) === "open_vote") {
      const ratingEnd = calculateRoundMinuteEnd(now, chat.rating_duration_seconds);
      const { error } = await supabase
        .from("rounds")
        .update({
          phase: "rating",
          phase_started_at: now.toISOString(),
          phase_ends_at: ratingEnd.toISOString(),
        })
        .eq("id", round.id)
        .eq("phase", "proposing");
      if (error) throw error;
      result.phases_advanced++;
    } else {
      // Idle to the next proposing window (skip the voting window entirely).
      const nextEnd = calculateRoundMinuteEnd(now, idleSecs);
      const { error } = await supabase
        .from("rounds")
        .update({ phase_ends_at: nextEnd.toISOString() })
        .eq("id", round.id);
      if (error) throw error;
      result.timers_extended++;
    }
    return;
  }

  if (round.phase === "rating") {
    const { count: voteCount } = await supabase
      .from("pairwise_comparisons")
      .select("id", { count: "exact", head: true })
      .eq("round_id", round.id)
      .eq("is_skip", false);

    if (treeRatingAction(voteCount ?? 0) === "seal") {
      if (chat.never_seals) {
        // Repository mode: never complete a thread. Reopen proposing so it keeps
        // growing then re-ranking — the thread stays alive, no sealed winner.
        const proposingEnd = calculateRoundMinuteEnd(
          now,
          chat.proposing_duration_seconds,
        );
        const { error } = await supabase
          .from("rounds")
          .update({
            phase: "proposing",
            phase_started_at: now.toISOString(),
            phase_ends_at: proposingEnd.toISOString(),
          })
          .eq("id", round.id)
          .eq("phase", "rating");
        if (error) throw error;
      } else {
        const { error } = await supabase.rpc("complete_round_with_winner", {
          p_round_id: round.id,
        });
        if (error) throw error;
      }
      result.phases_advanced++;
    } else {
      // No attention this window — idle to the next voting window.
      const nextEnd = calculateRoundMinuteEnd(now, idleSecs);
      const { error } = await supabase
        .from("rounds")
        .update({ phase_ends_at: nextEnd.toISOString() })
        .eq("id", round.id);
      if (error) throw error;
      result.timers_extended++;
    }
  }
}

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
        parent_proposition_id,
        chats!inner (
          id,
          name,
          start_mode,
          rating_start_mode,
          proposing_duration_seconds,
          rating_duration_seconds,
          proposing_minimum,
          rating_minimum,
          rating_mode,
          adaptive_duration_enabled,
          adaptive_adjustment_percent,
          min_phase_duration_seconds,
          max_phase_duration_seconds,
          host_paused,
          schedule_paused,
          is_arena,
          never_seals
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

      // Skip paused chats — auto-pause safety prevents runaway agent rounds
      if (isChatPaused(chat)) {
        console.log(`Round ${round.id}: skipping expired timer — chat ${chat.id} is paused`);
        continue;
      }

      // C15 tree-node rounds (child cycles) are clock-only: they flip with
      // the chat-wide window, need >= 2 props to open a vote and >= 1 real
      // vote to seal — otherwise they idle to the next same-phase window.
      // Chat-level minimums/thresholds/deadline rules don't apply to them.
      if ((round as any).cycles.parent_proposition_id) {
        await processTreeNodeRound(supabase, round, chat, result);
        continue;
      }

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
        // Below minimum. For continuous-chat R2+ proposing, the deadline rules
        // may still resolve the round (carried leader wins unchallenged, or
        // rating opens on a sub-minimum votable set) instead of extending
        // forever. Gates (grace window, quick-chat exclusion, R1 exclusion)
        // live in the SQL function; 'none' means extend as before.
        let resolved = false;
        if (isProposing) {
          const { data: outcome, error: resolveError } = await supabase.rpc(
            "maybe_resolve_expired_proposing",
            { p_round_id: round.id }
          );
          if (resolveError) {
            console.error(
              `Round ${round.id}: maybe_resolve_expired_proposing failed: ${resolveError.message}`
            );
          } else if (outcome === "converged" || outcome === "advanced") {
            console.log(
              `Round ${round.id}: deadline rule resolved proposing phase (${outcome})`
            );
            result.phases_advanced++;
            resolved = true;
          }
        }
        if (!resolved) {
          // Extend timer
          await extendTimer(supabase, round, chat, isProposing);
          result.timers_extended++;
        }
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

// Matches (pairwise) mode: rating progress is measured PER-RATER, not per
// proposition. A rater is "done" if they have a completion marker (finished
// their matches), grid coverage (grid raters / agents grid-rate), or skipped.
// Used for both the timer-expiry minimum and the early-advance threshold so
// pure-human matches rounds advance (their votes go to pairwise_comparisons,
// which the grid_rankings-based checks never see).
async function getMatchesRatingProgress(
  supabase: ReturnType<typeof createClient>,
  roundId: number,
  chatId: number
): Promise<{ done: number; eligible: number }> {
  const [comps, grids, skips, eligibleRpc] = await Promise.all([
    supabase.from("rating_completions").select("participant_id").eq("round_id", roundId),
    supabase.from("grid_rankings").select("participant_id").eq("round_id", roundId),
    supabase.from("rating_skips").select("participant_id").eq("round_id", roundId),
    supabase.rpc("get_rating_eligible_count", { p_chat_id: chatId }),
  ]);
  const done = distinctRaterCount(
    (comps.data ?? []) as { participant_id: number | null }[],
    (grids.data ?? []) as { participant_id: number | null }[],
    (skips.data ?? []) as { participant_id: number | null }[],
  );
  const eligible = (eligibleRpc.error || eligibleRpc.data == null)
    ? done
    : (eligibleRpc.data as number);
  return { done, eligible };
}

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
    if ((propositionCount || 0) >= chat.proposing_minimum) return true;

    // Arena rooms are kept alive by AI seat-fill. Their proposing early-advance is
    // disabled (thresholds NULL) so a present human always gets the full proposing
    // window instead of the phase flipping to rating the instant the agents fill it.
    // But that means a pure-agent or lurking-human round would otherwise extend
    // forever here (maybe_resolve_expired_proposing needs a human challenger/affirm).
    // Advance on the timer once the agent-filled board is votable so the loop never
    // stalls. Votable = >=2 NEW props (agent or human; carried excluded).
    if (chat.is_arena) {
      const { count: votableCount } = await supabase
        .from("propositions")
        .select("id", { count: "exact", head: true })
        .eq("round_id", roundId)
        .is("carried_from_id", null);
      return (votableCount || 0) >= 2;
    }
    return false;
  } else {
    // Matches mode: advance at timer expiry once at least one rater has
    // finished (pairwise votes never touch grid_rankings, so the avg-raters
    // check below would wrongly extend a pure-human matches round forever).
    if (chat.rating_mode === "matches") {
      // Timer-paced: seal once the timer expires as long as there is at least
      // one vote to score. The configured scoring strategy (Bradley-Terry by
      // default) yields a definitive winner from WHATEVER votes exist, so a
      // round never hangs waiting for full coverage. No votes at all → extend
      // (don't seal an empty round).
      const { count, error: cErr } = await supabase
        .from("pairwise_comparisons")
        .select("id", { count: "exact", head: true })
        .eq("round_id", roundId);
      if (cErr) {
        console.error(`Round ${roundId}: vote count failed: ${cErr.message}`);
        return false;
      }
      return (count || 0) >= 1;
    }
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

    // Push notification is sent by the notify_push_round DB trigger (fires on
    // the phase UPDATE above, whichever driver performs it).
  } else if (round.phase === "rating") {
    if (chat.never_seals) {
      // Repository mode: never complete. Reopen proposing so the list keeps
      // growing then re-ranking — always alive, never a sealed winner.
      const proposingEnd = calculateRoundMinuteEnd(
        now,
        chat.proposing_duration_seconds,
      );
      const { error } = await supabase
        .from("rounds")
        .update({
          phase: "proposing",
          phase_started_at: now.toISOString(),
          phase_ends_at: proposingEnd.toISOString(),
        })
        .eq("id", round.id)
        .eq("phase", "rating");
      if (error) throw error;
    } else {
      // Calculate winner and complete round
      await calculateWinnerAndComplete(supabase, round);
    }
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

  // Persist per-user voting/proposing/combined ranks for the leaderboard.
  // The SQL `complete_round_with_winner` function calls this too; the
  // early-advance trigger takes that path, but this timer path bypassed it
  // for months — leaving rounds that ended on-time with no rank rows.
  // store_round_ranks is idempotent (ON CONFLICT DO UPDATE).
  const { error: ranksError } = await supabase.rpc("store_round_ranks", {
    p_round_id: round.id,
  });
  if (ranksError) {
    // Don't block completion — log and move on. Ranks can be backfilled.
    console.error(`store_round_ranks failed for round ${round.id}: ${ranksError.message}`);
  }

  console.log(
    `Round ${round.id} complete. ` +
    `Winner(s): ${tiedWinners.length}, ` +
    `Primary: ${primaryWinnerId}, ` +
    `Sole: ${isSoleWinner}`
  );

  // Apply adaptive duration adjustment for next round
  await applyAdaptiveDuration(supabase, round.id);

  // Push notifications (winner / next round opening) are sent by the
  // notify_push_round DB trigger, which fires on the round INSERT/UPDATE
  // regardless of which driver performed it.
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
          name,
          proposing_minimum,
          rating_minimum,
          proposing_threshold_percent,
          proposing_threshold_count,
          rating_threshold_percent,
          rating_threshold_count,
          rating_mode,
          rating_duration_seconds,
          rating_start_mode,
          host_paused,
          schedule_paused,
          is_arena,
          never_seals
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

      // Skip paused chats — auto-pause safety prevents runaway agent rounds
      if (isChatPaused(chat)) {
        continue;
      }

      const isProposing = round.phase === "proposing";

      // Check if auto-advance thresholds are configured
      const thresholdPercent = isProposing
        ? chat.proposing_threshold_percent
        : chat.rating_threshold_percent;
      const thresholdCount = isProposing
        ? chat.proposing_threshold_count
        : chat.rating_threshold_count;

      // Skip if no auto-advance thresholds are configured (toggle OFF). Applies
      // uniformly to grid AND matches rating: a matches chat with rating
      // auto-advance turned off is timer-paced (the timer-expiry path still
      // advances it once the phase ends — see checkMinimumMet/matchesTimerMinimumMet).
      // When ON, checkThresholdsMet → shouldEarlyAdvanceMatches advances on full
      // turnout. Matches the DB trigger matches_preview_maybe_finalize.
      if (!autoAdvanceGateOpen({
        isProposing,
        ratingMode: chat.rating_mode,
        thresholdPercent,
        thresholdCount,
      })) {
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

  // Use funded participant count (unfunded spectators don't count toward thresholds)
  const { data: fundedCount, error: fundedError } = await supabase
    .rpc("get_funded_participant_count", { p_round_id: round.id });

  if (fundedError) throw fundedError;

  // Fallback to active participant count if no funding records (backward compat)
  let participantCount = fundedCount || 0;
  if (participantCount === 0) {
    const { count, error: partError } = await supabase
      .from("participants")
      .select("id", { count: "exact", head: true })
      .eq("chat_id", chatId)
      .eq("status", "active");

    if (partError) throw partError;
    participantCount = count || 0;
  }

  if (participantCount === 0) return false;

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
    // 2. Acted (submitters + skippers) >= effective count threshold — a skipper has
    //    acted, so it counts toward the count threshold too (matches the DB triggers and
    //    the percent check). The separate minimum gate still requires real propositions.
    const percentMet = participatedCount >= percentRequired;
    const countMet = participatedCount >= effectiveCountThreshold;

    console.log(`[checkThresholdsMet] Round ${round.id}: ${uniqueSubmitters} submitters + ${skipCount} skips = ${participatedCount} participated. ` +
                `Percent: ${participatedCount} >= ${percentRequired}? ${percentMet}. Count(acted): ${participatedCount} >= ${effectiveCountThreshold}? ${countMet}`);

    return percentMet && countMet;
  } else {
    // Matches mode: early-advance once every eligible rater has finished their
    // matches (per-rater completion, not per-proposition coverage).
    if (chat.rating_mode === "matches") {
      const { done, eligible } = await getMatchesRatingProgress(supabase, round.id, chatId);
      const advance = shouldEarlyAdvanceMatches(done, eligible);
      console.log(`[checkThresholdsMet] Matches round ${round.id}: ${done}/${eligible} raters done → ${advance}`);
      return advance;
    }
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

    // Use rating-eligible count (excludes agents when rating_agent_count = 0)
    const { data: eligibleCount, error: eligibleError } = await supabase
      .rpc("get_rating_eligible_count", { p_chat_id: chatId });

    const ratingParticipantCount = (eligibleError || !eligibleCount)
      ? participantCount  // fallback to total if RPC fails
      : eligibleCount;

    // Use rating-specific helper that caps threshold to (participants - 1)
    // since users can't rate their own propositions — except in conditional
    // self-inclusion rounds (<= 2 props), which propositionCount signals.
    return shouldAutoAdvanceRating(
      { thresholdPercent, thresholdCount },
      {
        totalParticipants: ratingParticipantCount,
        participatedCount,
        propositionCount: propositions.length,
      }
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
          proposing_duration_seconds,
          host_paused,
          schedule_paused,
          is_arena,
          never_seals
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

      // Skip paused chats
      if (isChatPaused(chat)) {
        continue;
      }

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
        // Check if chat has enough credits to start
        const { data: canStart, error: creditError } = await supabase
          .rpc("can_round_start", { p_chat_id: chatId });

        if (creditError) throw creditError;

        if (!canStart) {
          console.log(`Round ${round.id}: participant threshold met but insufficient credits, staying paused`);
          continue;
        }

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

        // Fund participants for this round
        const { data: fundedCount, error: fundError } = await supabase
          .rpc("fund_round_participants", { p_round_id: round.id, p_chat_id: chatId });

        if (fundError) {
          console.error(`Error funding participants for round ${round.id}:`, fundError);
        } else {
          console.log(`Round ${round.id}: funded ${fundedCount} participants`);
        }

        result.auto_started++;
      }
    } catch (err) {
      result.errors.push(
        `Error checking auto-start for round ${round.id}: ${err.message}`
      );
    }
  }
}
