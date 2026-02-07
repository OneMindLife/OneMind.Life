// Edge Function: submit-proposition
// Synchronous proposition submission with duplicate detection
//
// Accepts:
// - { content, round_id, participant_id }
//
// Returns:
// - 200 with proposition data on success
// - 409 with { error, code: 'DUPLICATE_PROPOSITION', duplicate_proposition_id } if duplicate
//
// This function:
// 1. Validates JWT (gateway-verified) and participant ownership
// 2. Translates content to English using Claude Haiku
// 3. Normalizes the text (lowercase, trim whitespace)
// 4. Checks for existing propositions with same normalized English translation
// 5. If unique, inserts proposition and translations
// 6. If duplicate, returns 409 with duplicate info
//
// AUTH: verify_jwt = true in config.toml — gateway verifies JWT signatures.
// Function validates participant ownership after gateway auth.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk@0.39.0";
import { z } from "npm:zod@3.23.8";
import {
  getCorsHeaders,
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";

// Environment variables
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Initialize Anthropic client
const anthropic = new Anthropic({
  apiKey: Deno.env.get("ANTHROPIC_API_KEY") ?? "",
});

// Initialize Supabase client with service role for DB operations
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Request body schema
const RequestSchema = z.object({
  content: z.string().min(1, "Content is required"),
  round_id: z.number().int().positive("Round ID must be a positive integer"),
  participant_id: z.number().int().positive("Participant ID must be a positive integer"),
});

// Zod schema for translations (en and es only for now)
const TranslationsSchema = z.object({
  en: z.string(),
  es: z.string(),
});

type Translations = z.infer<typeof TranslationsSchema>;

// =============================================================================
// TRANSLATION HELPER
// =============================================================================

/**
 * Translate content to English and Spanish using Claude Haiku
 */
async function getTranslations(text: string): Promise<Translations> {
  const MAX_RETRIES = 3;
  const RETRY_DELAY = 1000;

  const prompt = `Translate the following text into English and Spanish.
Keep the translations natural and preserve the original meaning.
If the text is already in one of these languages, still provide both translations.

Text to translate:
${text}

Return ONLY a JSON object with exactly these keys (no markdown, no explanation):
{"en": "English translation", "es": "Spanish translation"}`;

  let attempts = 0;

  while (attempts < MAX_RETRIES) {
    try {
      const message = await anthropic.messages.create({
        model: "claude-3-haiku-20240307",
        max_tokens: 1024,
        messages: [
          {
            role: "user",
            content: prompt,
          },
        ],
      });

      // Extract text from response
      const responseText = message.content[0].type === "text"
        ? message.content[0].text
        : "";

      // Clean up the response - remove any markdown code blocks
      let cleanedResponse = responseText.trim();
      if (cleanedResponse.startsWith("```json")) {
        cleanedResponse = cleanedResponse.slice(7);
      } else if (cleanedResponse.startsWith("```")) {
        cleanedResponse = cleanedResponse.slice(3);
      }
      if (cleanedResponse.endsWith("```")) {
        cleanedResponse = cleanedResponse.slice(0, -3);
      }
      cleanedResponse = cleanedResponse.trim();

      // Validate JSON format
      if (!cleanedResponse.startsWith("{") || !cleanedResponse.endsWith("}")) {
        throw new Error("Response is not in valid JSON format");
      }

      // Parse and validate with Zod
      const parsed = JSON.parse(cleanedResponse);
      return TranslationsSchema.parse(parsed);
    } catch (error) {
      attempts++;
      console.error(`[SUBMIT-PROPOSITION] Translation attempt ${attempts} failed:`, error);

      if (attempts === MAX_RETRIES) {
        throw new Error(
          `Translation failed after ${MAX_RETRIES} attempts: ${error instanceof Error ? error.message : "Unknown error"}`
        );
      }

      // Exponential backoff
      await new Promise((resolve) =>
        setTimeout(resolve, RETRY_DELAY * Math.pow(2, attempts - 1))
      );
    }
  }

  throw new Error("Translation failed unexpectedly");
}

// =============================================================================
// AUTH VALIDATION HELPER
// =============================================================================

/**
 * Validate the request JWT and return the authenticated user.
 * Gateway already verified the JWT signature (verify_jwt = true).
 * This function validates via getUser() and returns the user object.
 */
async function validateAuth(req: Request): Promise<{ user: { id: string } } | { error: string }> {
  const authHeader = req.headers.get("Authorization") || req.headers.get("authorization");
  const token = authHeader?.replace("Bearer ", "");

  if (!token) {
    return { error: "Unauthorized - no token" };
  }

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return { error: "Invalid token" };
  }

  return { user: { id: user.id } };
}

// =============================================================================
// DUPLICATE DETECTION
// =============================================================================

/**
 * Normalize text for comparison: lowercase and trim whitespace
 */
function normalizeText(text: string): string {
  return text.toLowerCase().trim();
}

/**
 * Check if a proposition with the same normalized English translation
 * already exists in the round
 */
async function findDuplicate(
  roundId: number,
  normalizedEnglish: string
): Promise<{ id: number; content: string } | null> {
  // Use raw SQL for reliable join and filtering
  // This avoids potential issues with PostgREST's embedded resource filtering
  const { data, error } = await supabase.rpc("find_duplicate_proposition", {
    p_round_id: roundId,
    p_normalized_english: normalizedEnglish,
  });

  if (error) {
    console.error("[SUBMIT-PROPOSITION] Error checking for duplicates:", error);
    throw new Error(`Database error: ${error.message}`);
  }

  console.log("[SUBMIT-PROPOSITION] Duplicate check result:", JSON.stringify(data));

  if (data && data.length > 0) {
    return {
      id: data[0].proposition_id,
      content: data[0].content,
    };
  }

  return null;
}

// =============================================================================
// MAIN HANDLER
// =============================================================================

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  // Only accept POST
  if (req.method !== "POST") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  // Auth verification
  const authResult = await validateAuth(req);
  if ("error" in authResult) {
    console.log("[SUBMIT-PROPOSITION] Auth failed:", authResult.error);
    return corsErrorResponse(authResult.error, req, 401);
  }

  try {
    // Parse and validate request body
    const body = await req.json();
    console.log("[SUBMIT-PROPOSITION] Request body:", JSON.stringify(body));

    const validationResult = RequestSchema.safeParse(body);
    if (!validationResult.success) {
      const errors = validationResult.error.errors.map((e) => `${e.path.join(".")}: ${e.message}`).join(", ");
      console.error("[SUBMIT-PROPOSITION] Validation error:", errors);
      return corsErrorResponse(`Validation error: ${errors}`, req, 400);
    }

    const { content, round_id, participant_id } = validationResult.data;

    // Verify participant ownership and active status
    const { data: participant, error: participantErr } = await supabase
      .from("participants")
      .select("user_id, status")
      .eq("id", participant_id)
      .single();

    if (participantErr || !participant || participant.user_id !== authResult.user.id) {
      return corsErrorResponse("Not your participant", req, 403);
    }
    if (participant.status !== "active") {
      return corsErrorResponse("Participant not active", req, 403);
    }

    // Step 1: Translate content to English (and Spanish)
    console.log("[SUBMIT-PROPOSITION] Translating content...");
    const translations = await getTranslations(content);
    console.log("[SUBMIT-PROPOSITION] Translations:", JSON.stringify(translations));

    // Step 2: Normalize the English translation
    const normalizedEnglish = normalizeText(translations.en);
    console.log("[SUBMIT-PROPOSITION] Normalized English:", normalizedEnglish);

    // Step 3: Check for duplicates
    console.log("[SUBMIT-PROPOSITION] Checking for duplicates in round:", round_id);
    const duplicate = await findDuplicate(round_id, normalizedEnglish);

    if (duplicate) {
      console.log("[SUBMIT-PROPOSITION] Duplicate found:", duplicate.id);
      return corsJsonResponse(
        {
          error: "A proposition with the same content already exists in this round",
          code: "DUPLICATE_PROPOSITION",
          duplicate_proposition_id: duplicate.id,
        },
        req,
        409
      );
    }

    // Step 4: Insert the proposition
    console.log("[SUBMIT-PROPOSITION] Inserting new proposition...");
    const { data: proposition, error: insertError } = await supabase
      .from("propositions")
      .insert({
        round_id,
        participant_id,
        content,
      })
      .select()
      .single();

    if (insertError) {
      console.error("[SUBMIT-PROPOSITION] Insert error:", insertError);
      return corsErrorResponse(`Failed to create proposition: ${insertError.message}`, req, 500);
    }

    console.log("[SUBMIT-PROPOSITION] Proposition created:", proposition.id);

    // Step 5: Insert translations
    const translationInserts = Object.entries(translations).map(([lang, translated_text]) => ({
      proposition_id: proposition.id,
      entity_type: "proposition",
      field_name: "content",
      language_code: lang,
      translated_text,
    }));

    console.log("[SUBMIT-PROPOSITION] Inserting translations...");
    const { error: translationError } = await supabase
      .from("translations")
      .upsert(translationInserts, {
        onConflict: "proposition_id,field_name,language_code",
        ignoreDuplicates: false,
      });

    if (translationError) {
      console.error("[SUBMIT-PROPOSITION] Translation insert error:", translationError);
      // Don't fail the request if translations fail - they can be regenerated
      // The proposition was already created successfully
    }

    console.log("[SUBMIT-PROPOSITION] Success - returning proposition");
    return corsJsonResponse({ proposition }, req, 200);
  } catch (error) {
    console.error("[SUBMIT-PROPOSITION] Error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500
    );
  }
});
