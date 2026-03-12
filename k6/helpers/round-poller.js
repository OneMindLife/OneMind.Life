// Round state polling via PostgREST and SECURITY DEFINER RPCs.
// Provides helpers to query current round state for the mega-chat scenario.

import { check } from "k6";
import { restRequest } from "./supabase.js";

/**
 * Get full round state + submission status in one RPC call.
 * Replaces 4 separate RLS-evaluated queries (cycle, round, proposition check, rating check).
 * Returns { cycle_id, round_id, phase, phase_ends_at, custom_id,
 *           has_submitted_proposition, has_submitted_ratings } or null.
 */
export function getRoundState(token, chatId, participantId) {
  const res = restRequest(
    "POST",
    "/rpc/get_round_state_for_participant",
    token,
    { p_chat_id: chatId, p_participant_id: participantId },
    "get_round_state"
  );

  check(res, { "get_round_state: status 200": (r) => r.status === 200 });

  if (res.status !== 200) return null;

  try {
    const data = JSON.parse(res.body);
    return data && data.length > 0 ? data[0] : null;
  } catch {
    return null;
  }
}

/**
 * Get participant record for a user in a chat.
 * Returns { id, display_name, status } or null.
 */
export function getMyParticipant(token, chatId, userId) {
  const res = restRequest(
    "GET",
    `/participants?chat_id=eq.${chatId}&user_id=eq.${userId}&select=id,display_name,status&limit=1`,
    token,
    null,
    "get_participant"
  );

  check(res, { "get_participant: status 200": (r) => r.status === 200 });

  if (res.status !== 200) return null;

  try {
    const data = JSON.parse(res.body);
    return data && data.length > 0 ? data[0] : null;
  } catch {
    return null;
  }
}

/**
 * Get the current (most recent) cycle for a chat.
 * Returns { id } or null.
 */
export function getCurrentCycle(token, chatId) {
  const res = restRequest(
    "GET",
    `/cycles?chat_id=eq.${chatId}&order=created_at.desc&limit=1&select=id`,
    token,
    null,
    "get_cycle"
  );

  check(res, { "get_cycle: status 200": (r) => r.status === 200 });

  if (res.status !== 200) return null;

  try {
    const data = JSON.parse(res.body);
    return data && data.length > 0 ? data[0] : null;
  } catch {
    return null;
  }
}

/**
 * Get the current (most recent) round for a cycle.
 * Returns { id, phase, phase_ends_at, custom_id } or null.
 */
export function getCurrentRound(token, cycleId) {
  const res = restRequest(
    "GET",
    `/rounds?cycle_id=eq.${cycleId}&order=custom_id.desc&limit=1&select=id,phase,phase_ends_at,custom_id`,
    token,
    null,
    "get_round"
  );

  check(res, { "get_round: status 200": (r) => r.status === 200 });

  if (res.status !== 200) return null;

  try {
    const data = JSON.parse(res.body);
    return data && data.length > 0 ? data[0] : null;
  } catch {
    return null;
  }
}

/**
 * Get propositions for rating — excludes the caller's own propositions.
 * Uses a SECURITY DEFINER RPC to avoid per-row RLS evaluation,
 * which causes statement_timeout under concurrent load.
 * Returns [{ id, content }, ...] or [].
 */
export function getPropositionsForRating(token, roundId, myParticipantId) {
  const res = restRequest(
    "POST",
    `/rpc/get_propositions_for_rating`,
    token,
    { p_round_id: roundId, p_participant_id: myParticipantId },
    "get_propositions"
  );

  check(res, { "get_propositions: status 200": (r) => r.status === 200 });

  if (res.status !== 200) return [];

  try {
    return JSON.parse(res.body) || [];
  } catch {
    return [];
  }
}

/**
 * Check if this participant has already submitted a proposition this round.
 * Returns true if already submitted.
 */
export function hasSubmittedProposition(token, roundId, participantId) {
  const res = restRequest(
    "GET",
    `/propositions?round_id=eq.${roundId}&participant_id=eq.${participantId}&carried_from_id=is.null&select=id&limit=1`,
    token,
    null,
    "check_proposition"
  );

  check(res, { "check_proposition: status 200": (r) => r.status === 200 });

  if (res.status !== 200) return false;

  try {
    const data = JSON.parse(res.body);
    return data && data.length > 0;
  } catch {
    return false;
  }
}

/**
 * Check if this participant has already submitted ratings this round.
 * Returns true if already submitted.
 */
export function hasSubmittedRatings(token, roundId, participantId) {
  const res = restRequest(
    "GET",
    `/grid_rankings?round_id=eq.${roundId}&participant_id=eq.${participantId}&select=id&limit=1`,
    token,
    null,
    "check_ratings"
  );

  check(res, { "check_ratings: status 200": (r) => r.status === 200 });

  if (res.status !== 200) return false;

  try {
    const data = JSON.parse(res.body);
    return data && data.length > 0;
  } catch {
    return false;
  }
}
