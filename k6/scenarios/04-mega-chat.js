// Mega Chat: 5,000 users in a single chat with realistic propose→rate flow
// Run: k6 run k6/scenarios/04-mega-chat.js
//
// This scenario tests a single chat under extreme concurrency.
// Each VU signs up, joins the mega chat, then loops through:
//   - Fetch round state once per iteration (2 GETs: cycle + round)
//   - Act based on phase (propose or rate)
//   - Sleep until phase_ends_at + buffer, then re-check
//
// Uses sleep-until-phase-end instead of polling (matches Realtime behavior).
// Real users receive state via WebSocket; k6 simulates the same idle pattern.
//
// Prerequisites:
//   - LOAD_TEST_MODE=true (disables LLM calls in edge functions)
//   - Auth rate limit >= 6000 signups/hour in Supabase Dashboard

import { sleep } from "k6";
import { Counter, Trend } from "k6/metrics";
import { getOrCreateAuth, setDisplayName } from "../helpers/auth.js";
import {
  joinChatRpc,
  getDashboard,
  createMegaChat,
  findMegaChat,
  submitProposition,
  upsertSingleRating,
} from "../helpers/supabase.js";
import { generateProposition, generateRealisticRatings } from "../helpers/data.js";
import {
  getRoundState,
  getPropositionsForRating,
} from "../helpers/round-poller.js";

// Custom metrics
const propositionsSubmitted = new Counter("propositions_submitted");
const ratingsUpserted = new Counter("ratings_upserted");
const phasePolls = new Counter("phase_polls");
const roundAdvances = new Counter("round_advances");
const propLatency = new Trend("proposition_submit_duration", true);
const singleRatingLatency = new Trend("single_rating_duration", true);

export const options = {
  stages: [
    { duration: "2m", target: 100 },    // Warm up, first joins
    { duration: "3m", target: 100 },    // Hold, chat auto-starts at 50
    { duration: "5m", target: 1000 },   // Ramp
    { duration: "5m", target: 1000 },   // Hold, measure
    { duration: "5m", target: 3000 },   // Ramp
    { duration: "5m", target: 3000 },   // Hold, measure
    { duration: "5m", target: 5000 },   // Ramp to target
    { duration: "10m", target: 5000 },  // Hold at 5,000
    { duration: "5m", target: 0 },      // Cool down
  ],
  thresholds: {
    "http_req_failed": ["rate<0.05"],                          // <5% error rate
    "http_req_duration": ["p(95)<5000", "p(99)<15000"],        // Overall
    "http_req_duration{name:signup}": ["p(95)<3000"],
    "http_req_duration{name:submit_proposition}": ["p(95)<8000"],
    "http_req_duration{name:upsert_grid_ranking}": ["p(95)<3000"],
    "http_req_duration{name:dashboard}": ["p(95)<5000"],
    "http_req_duration{name:join_chat}": ["p(95)<3000"],
    "http_req_duration{name:get_round_state}": ["p(95)<3000"],
  },
};

// Per-VU state (module-level = VU-scoped in k6)
let _displayName = null;
let _participantId = null;
let _megaChatId = null;
let _lastRoundId = null;
let _setupFailed = false;  // Permanent failure flag — stops retry storm
let _findRetries = 0;
let _joinRetries = 0;

const MAX_FIND_RETRIES = 15;
const MAX_JOIN_RETRIES = 5;

/**
 * Calculate seconds to sleep until phase_ends_at + jittered buffer.
 * Adds 2-10s random jitter to avoid thundering herd when all VUs
 * wake simultaneously (causes connection pool saturation + statement timeouts).
 * Clamped between 5s (minimum) and 300s (maximum).
 */
function sleepUntilPhaseEnd(phaseEndsAt) {
  if (!phaseEndsAt) return 30; // No end time → default 30s

  const nowMs = Date.now();
  const endsAtMs = new Date(phaseEndsAt).getTime();
  const remainingSec = (endsAtMs - nowMs) / 1000;

  // Add 2-10s random jitter so VUs wake up staggered over ~8s window
  const jitter = 2 + Math.random() * 8;
  const sleepTime = remainingSec + jitter;

  // Clamp: min 5s (avoid busy-loop), max 300s (avoid stuck VUs)
  return Math.max(5, Math.min(300, sleepTime));
}

export default function () {
  const vuId = __VU;
  const iter = __ITER;

  // Permanently failed VUs sleep and exit — no more retries
  if (_setupFailed) {
    sleep(30 + Math.random() * 30);
    return;
  }

  // ==========================================================================
  // SETUP (once per VU): Sign up → Set name → Join mega chat → Cache state
  // ==========================================================================
  const auth = getOrCreateAuth();
  if (!auth) {
    console.error(`VU ${vuId}: Signup failed, sleeping`);
    sleep(5 + Math.random() * 10);
    return;
  }

  const { access_token, user_id } = auth;

  if (!_displayName) {
    // Jitter on first iteration to spread signup load
    sleep(Math.random() * 3);
    _displayName = setDisplayName(access_token, vuId);
    sleep(0.3);
  }

  // Find or create the mega chat (VU 1 creates, others find)
  if (!_megaChatId) {
    if (vuId === 1 && iter === 0) {
      // First VU creates the mega chat
      const existing = findMegaChat(access_token);
      if (existing) {
        _megaChatId = existing.id;
        console.log(`VU ${vuId}: Found existing mega chat ${_megaChatId}`);
      } else {
        const chat = createMegaChat(access_token);
        if (chat) {
          _megaChatId = chat.id;
          console.log(`VU ${vuId}: Created mega chat ${_megaChatId}`);
        }
      }
    } else {
      // Exponential backoff: 2s, 4s, 8s, 16s, ...
      const backoff = Math.min(60, Math.pow(2, _findRetries) * (1 + Math.random()));
      sleep(backoff);
      const existing = findMegaChat(access_token);
      if (existing) {
        _megaChatId = existing.id;
      }
    }

    if (!_megaChatId) {
      _findRetries++;
      if (_findRetries >= MAX_FIND_RETRIES) {
        console.error(`VU ${vuId}: Gave up finding mega chat after ${MAX_FIND_RETRIES} retries`);
        _setupFailed = true;
      }
      return;
    }
  }

  // Join the mega chat + get participant_id in one RPC call
  if (!_participantId) {
    const participant = joinChatRpc(access_token, _megaChatId, _displayName);
    if (participant) {
      _participantId = participant.id;
    } else {
      _joinRetries++;
      if (_joinRetries >= MAX_JOIN_RETRIES) {
        console.error(`VU ${vuId}: Gave up joining after ${MAX_JOIN_RETRIES} retries`);
        _setupFailed = true;
      }
      // Exponential backoff
      sleep(Math.min(30, Math.pow(2, _joinRetries) * (1 + Math.random())));
      return;
    }
  }

  // ==========================================================================
  // PER-ITERATION: Single RPC for state → Act → Sleep until phase ends
  // ==========================================================================

  // 1. Fetch round state + submission status in one RPC call
  //    Replaces 4 separate RLS-evaluated queries (cycle, round, prop check, rating check)
  const state = getRoundState(access_token, _megaChatId, _participantId);
  phasePolls.add(1);

  if (!state) {
    // Chat hasn't started yet or no cycle/round
    sleep(5);
    return;
  }

  // Track round changes
  if (_lastRoundId && _lastRoundId !== state.round_id) {
    roundAdvances.add(1);
    console.log(`VU ${vuId}: Round advanced ${_lastRoundId} → ${state.round_id} (phase: ${state.phase})`);
  }
  _lastRoundId = state.round_id;

  // 2. Act based on phase
  if (state.phase === "proposing") {
    if (!state.has_submitted_proposition) {
      const content = generateProposition(vuId, iter);

      const start = Date.now();
      const res = submitProposition(access_token, state.round_id, _participantId, content);
      propLatency.add(Date.now() - start);

      if (res.status === 200) {
        propositionsSubmitted.add(1);
      }
    }

    sleep(sleepUntilPhaseEnd(state.phase_ends_at));

  } else if (state.phase === "rating") {
    if (!state.has_submitted_ratings) {
      const propositions = getPropositionsForRating(access_token, state.round_id, _participantId);
      if (propositions.length > 0) {
        const ratings = generateRealisticRatings(propositions, vuId);

        for (let i = 0; i < ratings.length; i++) {
          const r = ratings[i];
          const start = Date.now();
          upsertSingleRating(
            access_token,
            state.round_id,
            _participantId,
            r.proposition_id,
            r.grid_position,
          );
          singleRatingLatency.add(Date.now() - start);
          ratingsUpserted.add(1);

          if (i < ratings.length - 1) {
            sleep(1 + Math.random() * 2);
          }
        }
      }
    }

    sleep(sleepUntilPhaseEnd(state.phase_ends_at));

  } else {
    sleep(sleepUntilPhaseEnd(state.phase_ends_at));
  }

  // 3. Dashboard check (every 5th iteration ≈ every ~10 min)
  if (iter % 5 === 0) {
    getDashboard(access_token, user_id);
  }
}
