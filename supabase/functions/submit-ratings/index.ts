/**
 * Edge Function: submit-ratings
 *
 * Submit complete ratings for a round. One-time submission per participant.
 * Enforces binary rating: must include at least one 100 AND one 0.
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { z } from "npm:zod@3.23.8";
import {
  getCorsHeaders,
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";

// Environment
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Schemas
const RatingItemSchema = z.object({
 proposition_id: z.number().int().positive(),
 grid_position: z.number().min(0).max(100),
});

const RequestSchema = z.object({
 round_id: z.number().int().positive(),
 participant_id: z.number().int().positive(),
 ratings: z.array(RatingItemSchema).min(2, "At least 2 ratings required for binary"),
});

Deno.serve(async (req: Request) => {
 if (req.method === "OPTIONS") {
  return handleCorsPreFlight(req);
 }

 if (req.method !== "POST") {
  return corsErrorResponse("Method not allowed", req, 405);
 }

 try {
  // --- AUTH: Validate JWT and participant ownership ---
  const authHeader = req.headers.get("authorization")?.replace("Bearer ", "");
  if (!authHeader) {
    return corsErrorResponse("Unauthorized", req, 401);
  }

  const { data: { user }, error: authErr } = await supabase.auth.getUser(authHeader);
  if (authErr || !user) {
    return corsErrorResponse("Invalid token", req, 401);
  }

  const body = await req.json();

  // Validate request
  const result = RequestSchema.safeParse(body);
  if (!result.success) {
   return corsErrorResponse(
    `Validation error: ${result.error.errors.map(e => e.message).join(", ")}`,
    req,
    400,
    "INVALID_REQUEST",
   );
  }

  const { round_id, participant_id, ratings } = result.data;

  // --- Verify participant ownership and active status ---
  const { data: participant, error: participantErr } = await supabase
    .from("participants")
    .select("user_id, status")
    .eq("id", participant_id)
    .single();

  if (participantErr || !participant || participant.user_id !== user.id) {
    return corsErrorResponse("Not your participant", req, 403);
  }
  if (participant.status !== "active") {
    return corsErrorResponse("Participant not active", req, 403);
  }

  // 1. Check round exists and is in rating phase
  const { data: round, error: roundErr } = await supabase
   .from("rounds")
   .select("phase, phase_ends_at")
   .eq("id", round_id)
   .single();

  if (roundErr || !round) {
   return corsErrorResponse("Round not found", req, 404, "ROUND_NOT_FOUND");
  }

  if (round.phase !== "rating") {
   return corsErrorResponse(
    `Cannot rate during "${round.phase}" phase`,
    req,
    400,
    "WRONG_PHASE",
   );
  }

  if (round.phase_ends_at && new Date() >= new Date(round.phase_ends_at)) {
   return corsErrorResponse("Rating phase has ended", req, 400, "PHASE_ENDED");
  }

  // 2. Check not already submitted
  const { data: existing } = await supabase
   .from("round_participant_submissions")
   .select("submitted_at")
   .eq("round_id", round_id)
   .eq("participant_id", participant_id)
   .maybeSingle();

  if (existing) {
   return corsErrorResponse(
    "Already submitted ratings for this round",
    req,
    409,
    "ALREADY_SUBMITTED",
   );
  }

  // 3. Check duplicates
  const propIds = ratings.map(r => r.proposition_id);
  if (new Set(propIds).size !== propIds.length) {
   return corsErrorResponse(
    "Duplicate proposition IDs in ratings",
    req,
    400,
    "DUPLICATE_PROPOSITION",
   );
  }

  // 4. Binary check - must have at least one 100 AND one 0
  const hasZero = ratings.some(r => r.grid_position === 0);
  const hasHundred = ratings.some(r => r.grid_position === 100);
  if (!hasZero || !hasHundred) {
   return corsErrorResponse(
    "Binary rating required: must include one 100 (best) and one 0 (worst)",
    req,
    400,
    "BINARY_REQUIRED",
   );
  }

  // 5. Get propositions to check ownership
  const { data: props, error: propsErr } = await supabase
   .from("propositions")
   .select("id, participant_id")
   .eq("round_id", round_id)
   .in("id", propIds);

  if (propsErr) {
   return corsErrorResponse("Failed to fetch propositions", req, 500, "DB_ERROR");
  }

  const propMap = new Map(props?.map(p => [p.id, p.participant_id]));

  // Check all propositions exist
  for (const id of propIds) {
   if (!propMap.has(id)) {
    return corsErrorResponse(
     `Proposition ${id} not found in round`,
     req,
     404,
     "PROPOSITION_NOT_FOUND",
    );
   }
  }

  // 6. Check not rating own propositions
  for (const rating of ratings) {
   const propOwner = propMap.get(rating.proposition_id);
   if (propOwner === participant_id) {
    return corsErrorResponse(
     `Cannot rate your own proposition ${rating.proposition_id}`,
     req,
     400,
     "CANNOT_RATE_OWN",
    );
   }
  }

  // 7. Insert all ratings
  const ratingsToInsert = ratings.map(r => ({
   round_id,
   participant_id,
   proposition_id: r.proposition_id,
   grid_position: r.grid_position,
  }));

  const { error: insertErr } = await supabase
   .from("grid_rankings")
   .insert(ratingsToInsert);

  if (insertErr) {
   console.error("Insert error:", insertErr);
   return corsErrorResponse("Failed to save ratings", req, 500, "DB_ERROR");
  }

  // 8. Record submission
  await supabase
   .from("round_participant_submissions")
   .insert({ round_id, participant_id });

  return corsJsonResponse({
   success: true,
   round_id,
   participant_id,
   ratings_submitted: ratings.length,
   message: "Ratings submitted successfully"
  }, req, 200);

 } catch (err) {
  console.error("Error:", err);
  return corsErrorResponse(
   err instanceof Error ? err.message : "Internal error",
   req,
   500,
   "INTERNAL_ERROR",
  );
 }
});
