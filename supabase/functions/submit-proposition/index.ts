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
// 2. Translates content to English using Gemini 2.0 Flash
// 3. Normalizes the text (lowercase, trim whitespace)
// 4. Checks for existing propositions with same normalized English translation
// 5. If unique, inserts proposition and translations
// 6. If duplicate, returns 409 with duplicate info
//
// AUTH: verify_jwt = true in config.toml — gateway verifies JWT signatures.
// Function validates participant ownership after gateway auth.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import OpenAI from "npm:openai@4.77.0";
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
// Initialize OpenAI client pointing to Gemini 2.0 Flash (free tier, ~1-2s responses)
const openai = new OpenAI({
  apiKey: Deno.env.get("GEMINI_API_KEY") ?? "",
  baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
});

// Initialize Supabase client with service role for DB operations
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Request body schema
const RequestSchema = z.object({
  content: z.string().min(1, "Content is required"),
  round_id: z.number().int().positive("Round ID must be a positive integer"),
  participant_id: z.number().int().positive("Participant ID must be a positive integer"),
  category: z.string().nullable().optional(),
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
 * Translate content to English and Spanish using Kimi K2.5
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
      const message = await openai.chat.completions.create({
        model: "gemini-2.0-flash",
        max_tokens: 256,
        messages: [
          {
            role: "user",
            content: prompt,
          },
        ],
      });

      // Extract text from response
      const responseText = message.choices[0]?.message?.content ?? "";

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
 * Service role keys are accepted for internal edge-function-to-edge-function calls.
 */
async function validateAuth(req: Request): Promise<{ user: { id: string }; isServiceRole?: boolean } | { error: string }> {
  const authHeader = req.headers.get("Authorization") || req.headers.get("authorization");
  const token = authHeader?.replace("Bearer ", "");

  if (!token) {
    return { error: "Unauthorized - no token" };
  }

  // Check if token is the service role key (for internal calls from agent-propose)
  const envServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (envServiceKey && token === envServiceKey) {
    return { user: { id: "service_role" }, isServiceRole: true };
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
 * already exists in the round (translation-based dedup)
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

/**
 * Check if a proposition with the same raw normalized content
 * already exists in the round (no translations, raw text comparison)
 */
async function findDuplicateRaw(
  roundId: number,
  normalizedContent: string
): Promise<{ id: number; content: string } | null> {
  const { data, error } = await supabase.rpc("find_duplicate_proposition_raw", {
    p_round_id: roundId,
    p_normalized_content: normalizedContent,
  });

  if (error) {
    console.error("[SUBMIT-PROPOSITION] Error checking for raw duplicates:", error);
    throw new Error(`Database error: ${error.message}`);
  }

  console.log("[SUBMIT-PROPOSITION] Raw duplicate check result:", JSON.stringify(data));

  if (data && data.length > 0) {
    return {
      id: data[0].proposition_id,
      content: data[0].content,
    };
  }

  return null;
}

// =============================================================================
// TRANSLATION SETTINGS HELPER
// =============================================================================

interface TranslationSettings {
  chat_id: number;
  translations_enabled: boolean;
  translation_languages: string[];
}

/**
 * Get translation settings for the chat that owns a given round
 */
async function getTranslationSettings(roundId: number): Promise<TranslationSettings | null> {
  const { data, error } = await supabase.rpc("get_chat_translation_settings", {
    p_round_id: roundId,
  });

  if (error) {
    console.error("[SUBMIT-PROPOSITION] Error getting translation settings:", error);
    throw new Error(`Database error: ${error.message}`);
  }

  if (data && data.length > 0) {
    return data[0] as TranslationSettings;
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

    const { content: rawContent2, round_id, participant_id, category } = validationResult.data;
    // Strip any leading [category_tag] prefix — LLM artifact that should never persist in stored content
    const content = rawContent2.replace(/^\[\w+\]\s*/, "").trim();

    // Verify participant ownership and active status
    // Service role calls (from agent-propose) are trusted — only check active status
    const { data: participant, error: participantErr } = await supabase
      .from("participants")
      .select("user_id, status")
      .eq("id", participant_id)
      .single();

    if (participantErr || !participant) {
      return corsErrorResponse("Participant not found", req, 403);
    }
    if (!authResult.isServiceRole && participant.user_id !== authResult.user.id) {
      return corsErrorResponse("Not your participant", req, 403);
    }
    if (participant.status !== "active") {
      return corsErrorResponse("Participant not active", req, 403);
    }

    // Step 0: Check if participant is funded for this round
    const { data: isFunded, error: fundedError } = await supabase
      .rpc("is_participant_funded", { p_round_id: round_id, p_participant_id: participant_id });

    if (fundedError) {
      console.error("[SUBMIT-PROPOSITION] Funding check error:", fundedError);
      return corsErrorResponse(`Funding check failed: ${fundedError.message}`, req, 500);
    }

    // If round has funding records and participant is NOT funded, reject
    // (If no funding records exist yet, allow — backward compat for pre-credits rounds)
    if (isFunded === false) {
      const { data: fundedCount } = await supabase
        .rpc("get_funded_participant_count", { p_round_id: round_id });

      if (fundedCount && fundedCount > 0) {
        console.log("[SUBMIT-PROPOSITION] Participant not funded, rejecting");
        return corsErrorResponse("Insufficient credits — spectating this round", req, 403, "NOT_FUNDED");
      }
    }

    // Step 0.5: Get chat translation settings for this round
    const translationSettings = await getTranslationSettings(round_id);
    const translationsOn = translationSettings?.translations_enabled ?? false;
    console.log("[SUBMIT-PROPOSITION] Translations enabled:", translationsOn);

    if (translationsOn) {
      // =====================================================================
      // TRANSLATIONS ON: translate → normalize English → dedup via translations
      // =====================================================================

      // Step 1: Translate content to English (and Spanish)
      // Agent propositions (service role) are already in English — skip LLM translation
      let translations: Translations;
      if (authResult.isServiceRole) {
        console.log("[SUBMIT-PROPOSITION] Service role call — skipping LLM translation");
        translations = { en: content, es: "" };
      } else {
        console.log("[SUBMIT-PROPOSITION] Translating content...");
        translations = await getTranslations(content);
      }
      console.log("[SUBMIT-PROPOSITION] Translations:", JSON.stringify(translations));

      // Step 2: Normalize the English translation
      const normalizedEnglish = normalizeText(translations.en);
      console.log("[SUBMIT-PROPOSITION] Normalized English:", normalizedEnglish);

      // Step 3: Check for duplicates via English translation
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

      // Step 4: Auto-detect category if not provided
      let effectiveCategory = category || null;
      if (!effectiveCategory && translationSettings) {
        const { data: allowed } = await supabase.rpc("get_chat_allowed_categories", {
          p_chat_id: translationSettings.chat_id,
        });
        if (allowed && allowed.length === 1) {
          effectiveCategory = allowed[0];
          console.log("[SUBMIT-PROPOSITION] Auto-detected category:", effectiveCategory);
        }
      }

      // Step 5: Insert the proposition
      console.log("[SUBMIT-PROPOSITION] Inserting new proposition...");
      const { data: proposition, error: insertError } = await supabase
        .from("propositions")
        .insert({
          round_id,
          participant_id,
          content,
          category: effectiveCategory,
        })
        .select()
        .single();

      if (insertError) {
        console.error("[SUBMIT-PROPOSITION] Insert error:", insertError);
        return corsErrorResponse(`Failed to create proposition: ${insertError.message}`, req, 500);
      }

      console.log("[SUBMIT-PROPOSITION] Proposition created:", proposition.id);

      // Step 6: Insert translations
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
      }

      console.log("[SUBMIT-PROPOSITION] Success - returning proposition");
      return corsJsonResponse({ proposition }, req, 200);
    } else {
      // =====================================================================
      // TRANSLATIONS OFF: raw dedup via LOWER(TRIM(content)), no LLM calls
      // =====================================================================

      // Step 1: Normalize raw content
      const normalizedContent = normalizeText(content);
      console.log("[SUBMIT-PROPOSITION] Normalized raw content:", normalizedContent);

      // Step 2: Check for duplicates via raw content
      console.log("[SUBMIT-PROPOSITION] Checking for raw duplicates in round:", round_id);
      const duplicate = await findDuplicateRaw(round_id, normalizedContent);

      if (duplicate) {
        console.log("[SUBMIT-PROPOSITION] Raw duplicate found:", duplicate.id);
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

      // Step 3: Auto-detect category if not provided
      let effectiveCategory = category || null;
      if (!effectiveCategory && translationSettings) {
        const { data: allowed } = await supabase.rpc("get_chat_allowed_categories", {
          p_chat_id: translationSettings.chat_id,
        });
        if (allowed && allowed.length === 1) {
          effectiveCategory = allowed[0];
          console.log("[SUBMIT-PROPOSITION] Auto-detected category:", effectiveCategory);
        }
      }

      // Step 4: Insert the proposition (no translations)
      console.log("[SUBMIT-PROPOSITION] Inserting new proposition (no translations)...");
      const { data: proposition, error: insertError } = await supabase
        .from("propositions")
        .insert({
          round_id,
          participant_id,
          content,
          category: effectiveCategory,
        })
        .select()
        .single();

      if (insertError) {
        console.error("[SUBMIT-PROPOSITION] Insert error:", insertError);
        return corsErrorResponse(`Failed to create proposition: ${insertError.message}`, req, 500);
      }

      console.log("[SUBMIT-PROPOSITION] Proposition created (no translations):", proposition.id);
      return corsJsonResponse({ proposition }, req, 200);
    }
  } catch (error) {
    console.error("[SUBMIT-PROPOSITION] Error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500
    );
  }
});
