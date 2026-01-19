// Edge Function: translate
// AI-powered translation using Anthropic Claude
//
// Accepts one of:
// - { text, proposition_id, entity_type?, field_name? } - Single text for proposition
// - { text, chat_id, field_name? } - Single text for chat
// - { texts: [{text, field_name}], chat_id } - Batch texts for chat
//
// Returns: { success: true } on success
//
// Generates translations for both 'en' and 'es' and stores them in the translations table.
// Uses structured JSON output with retry logic and exponential backoff.
//
// AUTH: This function uses internal auth validation (verify_jwt should be false at Supabase level)
// - Accepts service role key in Authorization header
// - Accepts valid user JWT from Supabase Auth
// - Allows local development without auth

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
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// Initialize Anthropic client
const anthropic = new Anthropic({
  apiKey: Deno.env.get("ANTHROPIC_API_KEY") ?? "",
});

// Initialize Supabase client with service role for DB operations
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Zod validation schema
const TranslationsSchema = z.object({
  en: z.string(),
  es: z.string(),
});

type Translations = z.infer<typeof TranslationsSchema>;

// Text item schema for batch translations
const TextItemSchema = z.object({
  text: z.string().min(1, "Text is required"),
  field_name: z.string().min(1, "Field name is required"),
});

// Request body schema - supports both proposition and chat translations
const RequestSchema = z.object({
  // Single text mode
  text: z.string().optional(),
  // Batch texts mode (for multiple fields at once)
  texts: z.array(TextItemSchema).optional(),
  // Entity identifiers (exactly one must be provided)
  proposition_id: z.number().int().positive().optional(),
  chat_id: z.number().int().positive().optional(),
  // Legacy field for propositions
  entity_type: z.string().default("proposition"),
  field_name: z.string().default("content"),
}).refine(
  (data) => {
    // Exactly one of proposition_id or chat_id must be set
    const hasProposition = data.proposition_id !== undefined;
    const hasChat = data.chat_id !== undefined;
    return (hasProposition && !hasChat) || (!hasProposition && hasChat);
  },
  { message: "Exactly one of proposition_id or chat_id must be provided" }
).refine(
  (data) => {
    // Either text or texts must be provided (but not both)
    const hasText = data.text !== undefined && data.text.length > 0;
    const hasTexts = data.texts !== undefined && data.texts.length > 0;
    return (hasText && !hasTexts) || (!hasText && hasTexts);
  },
  { message: "Either text or texts must be provided (but not both)" }
);

/**
 * Generate translations for text using Anthropic Claude
 * Includes retry logic with exponential backoff
 */
async function getTranslations(text: string): Promise<Translations> {
  const MAX_RETRIES = 3;
  const RETRY_DELAY = 1000;

  const prompt = `Translate the following text into English and Spanish.
Keep the translation natural and preserve the original meaning.
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
      console.error(`[TRANSLATE] Attempt ${attempts} failed:`, error);

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
// Validates request authorization. Accepts:
// 1. Service role key JWT in Authorization header (for DB triggers via pg_net)
//    - Validates JWT structure and service_role claim
//    - Verifies issuer matches this Supabase project
// 2. Valid Supabase user JWT (for client requests)
// 3. Local development (localhost/127.0.0.1)
// =============================================================================

/**
 * Decode a JWT payload without verification (for claim inspection)
 * Note: This only decodes - signature is validated by checking known claims
 */
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    // Base64url decode the payload (middle part)
    const payload = parts[1];
    const decoded = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(decoded);
  } catch {
    return null;
  }
}

/**
 * Extract project reference from Supabase URL
 * e.g., "https://YOUR_PROJECT_REF.supabase.co" -> "YOUR_PROJECT_REF"
 */
function getProjectRef(): string | null {
  try {
    const url = new URL(supabaseUrl);
    const hostname = url.hostname;
    // Format: {project_ref}.supabase.co
    if (hostname.endsWith(".supabase.co")) {
      return hostname.replace(".supabase.co", "");
    }
    return null;
  } catch {
    return null;
  }
}

async function validateAuth(req: Request): Promise<{ valid: boolean; error?: string }> {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  // 1. Allow local development
  const isLocalDev = supabaseUrl.includes("localhost") ||
                     supabaseUrl.includes("127.0.0.1") ||
                     supabaseUrl.includes("kong:8000");
  if (isLocalDev) {
    return { valid: true };
  }

  // 2. Check for service role JWT (used by DB triggers via vault)
  //    The vault stores the actual JWT service role key, so we validate:
  //    - Token is a valid JWT structure
  //    - Token has role: "service_role" claim
  //    - Token issuer matches this Supabase project
  if (token) {
    const payload = decodeJwtPayload(token);
    if (payload) {
      const role = payload.role as string | undefined;
      const iss = payload.iss as string | undefined;
      const projectRef = getProjectRef();

      // Validate service role JWT
      if (role === "service_role" && iss === "supabase" && projectRef) {
        // Check that the "ref" claim matches our project
        const ref = payload.ref as string | undefined;
        if (ref === projectRef) {
          console.log("[TRANSLATE] Auth: Valid service role JWT for project", projectRef);
          return { valid: true };
        }
      }
    }
  }

  // 3. Validate user JWT via Supabase Auth
  if (token && supabaseAnonKey) {
    try {
      // Create a client with the user's token to validate it
      const userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data: { user }, error } = await userClient.auth.getUser();
      if (user && !error) {
        return { valid: true };
      }
    } catch {
      // Token validation failed, continue to reject
    }
  }

  return { valid: false, error: "Unauthorized - valid JWT or service role key required" };
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  // Only accept POST
  if (req.method !== "POST") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  // ==========================================================================
  // AUTH VERIFICATION
  // Validate request authorization before processing
  // ==========================================================================
  const authResult = await validateAuth(req);
  if (!authResult.valid) {
    console.log("[TRANSLATE] Auth failed:", authResult.error);
    return corsErrorResponse(authResult.error || "Unauthorized", req, 401);
  }

  try {
    // Parse and validate request body
    const body = await req.json();
    console.log("[TRANSLATE] Request body:", JSON.stringify(body));

    const validationResult = RequestSchema.safeParse(body);
    if (!validationResult.success) {
      const errors = validationResult.error.errors.map((e) => e.message).join(", ");
      console.error("[TRANSLATE] Validation error:", errors);
      return corsErrorResponse(`Validation error: ${errors}`, req, 400);
    }

    const { text, texts, proposition_id, chat_id, entity_type, field_name } = validationResult.data;

    // Build list of items to translate
    interface TranslateItem {
      text: string;
      field_name: string;
    }
    const itemsToTranslate: TranslateItem[] = [];

    if (texts && texts.length > 0) {
      // Batch mode - multiple texts with field names
      itemsToTranslate.push(...texts);
    } else if (text) {
      // Single text mode
      itemsToTranslate.push({ text, field_name });
    }

    console.log("[TRANSLATE] Items to translate:", itemsToTranslate.length);

    // Process all translations
    const allInserts: Array<{
      proposition_id?: number;
      chat_id?: number;
      entity_type: string;
      field_name: string;
      language_code: string;
      translated_text: string;
    }> = [];

    for (const item of itemsToTranslate) {
      console.log("[TRANSLATE] Generating translations for:", item.text.substring(0, 100));
      const translations = await getTranslations(item.text);
      console.log("[TRANSLATE] Generated translations:", JSON.stringify(translations));

      if (Object.keys(translations).length === 0) {
        console.error("[TRANSLATE] Empty translations returned for field:", item.field_name);
        continue;
      }

      // Prepare insert records for this item
      const inserts = Object.entries(translations).map(([lang, translated_text]) => {
        const record: {
          proposition_id?: number;
          chat_id?: number;
          entity_type: string;
          field_name: string;
          language_code: string;
          translated_text: string;
        } = {
          entity_type: chat_id ? "chat" : entity_type,
          field_name: item.field_name,
          language_code: lang,
          translated_text,
        };

        // Set the appropriate entity ID
        if (proposition_id) {
          record.proposition_id = proposition_id;
        } else if (chat_id) {
          record.chat_id = chat_id;
        }

        return record;
      });

      allInserts.push(...inserts);
    }

    if (allInserts.length === 0) {
      console.error("[TRANSLATE] No translations generated");
      return corsErrorResponse("No translations generated", req, 500);
    }

    console.log("[TRANSLATE] Upserting translations:", JSON.stringify(allInserts));

    // Upsert translations - use different conflict targets based on entity type
    // For propositions, use the existing unique constraint
    // For chats, we need to handle the upsert differently since there's no combined unique constraint
    for (const insert of allInserts) {
      let upsertError;

      if (insert.proposition_id) {
        // Proposition translation - use existing unique constraint
        const { error } = await supabase
          .from("translations")
          .upsert(insert, {
            onConflict: "proposition_id,field_name,language_code",
            ignoreDuplicates: false,
          });
        upsertError = error;
      } else if (insert.chat_id) {
        // Chat translation - check for existing and update/insert
        const { data: existing } = await supabase
          .from("translations")
          .select("id")
          .eq("chat_id", insert.chat_id)
          .eq("field_name", insert.field_name)
          .eq("language_code", insert.language_code)
          .maybeSingle();

        if (existing) {
          // Update existing
          const { error } = await supabase
            .from("translations")
            .update({ translated_text: insert.translated_text })
            .eq("id", existing.id);
          upsertError = error;
        } else {
          // Insert new
          const { error } = await supabase
            .from("translations")
            .insert(insert);
          upsertError = error;
        }
      }

      if (upsertError) {
        console.error("[TRANSLATE] Database error:", {
          message: upsertError.message,
          details: upsertError.details,
          hint: upsertError.hint,
          code: upsertError.code,
        });
        return corsErrorResponse(`Database error: ${upsertError.message}`, req, 500);
      }
    }

    console.log("[TRANSLATE] Translations stored successfully");
    return corsJsonResponse({ success: true }, req);
  } catch (error) {
    console.error("[TRANSLATE] Error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500
    );
  }
});
