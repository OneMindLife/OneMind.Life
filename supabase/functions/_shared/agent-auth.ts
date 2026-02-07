/**
 * Shared authentication module for Agent API endpoints
 *
 * Validates API keys and provides agent context for Edge Functions.
 * All agent endpoints should use this for consistent authentication.
 *
 * Security: API keys are hashed with SHA-256 before storage and lookup.
 * The plaintext key is only returned once during registration.
 */

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

/**
 * Hash an API key using SHA-256
 * Returns hex-encoded hash matching the database function
 */
export async function hashApiKey(key: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(key);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Environment variables
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/**
 * Result of agent authentication
 */
export interface AgentAuthResult {
  valid: boolean;
  error?: string;
  errorCode?: "INVALID_API_KEY" | "MISSING_AUTH" | "DEACTIVATED" | "DB_ERROR";
  agentId?: string;
  agentName?: string;
  userId?: string; // The pseudo-user ID for RLS
}

/**
 * Result of participant validation
 */
export interface ParticipantAuthResult extends AgentAuthResult {
  participantId?: number;
}

/**
 * Extract API key from Authorization header
 * Expects: "Bearer onemind_sk_..."
 */
function extractApiKey(req: Request): string | null {
  const authHeader =
    req.headers.get("Authorization") || req.headers.get("authorization");
  if (!authHeader) return null;

  // Support both "Bearer <key>" and just "<key>"
  const key = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7)
    : authHeader;

  // Validate key format
  if (!key.startsWith("onemind_sk_")) return null;

  return key;
}

/**
 * Create a Supabase client with service role key
 * Used for database operations that bypass RLS
 */
export function getServiceClient(): SupabaseClient {
  return createClient(supabaseUrl, supabaseServiceKey);
}

/**
 * Validate an agent API key and return agent info
 *
 * @param req - The incoming request with Authorization header
 * @param supabase - Optional Supabase client (creates one if not provided)
 * @returns AgentAuthResult with validation status and agent info
 */
export async function validateAgentAuth(
  req: Request,
  supabase?: SupabaseClient
): Promise<AgentAuthResult> {
  const apiKey = extractApiKey(req);

  if (!apiKey) {
    return {
      valid: false,
      error: "Missing or invalid Authorization header. Expected: Bearer onemind_sk_...",
      errorCode: "MISSING_AUTH",
    };
  }

  const client = supabase || getServiceClient();

  try {
    // Use the validation function we created in the migration
    const { data, error } = await client.rpc("validate_agent_api_key", {
      p_api_key: apiKey,
    });

    if (error) {
      console.error("[AGENT-AUTH] Database error:", error);
      return {
        valid: false,
        error: "Authentication error",
        errorCode: "DB_ERROR",
      };
    }

    // The function returns a single row
    const result = data?.[0];

    if (!result || !result.is_valid) {
      return {
        valid: false,
        error: "Invalid or deactivated API key",
        errorCode: "INVALID_API_KEY",
      };
    }

    // Update last_used_at in background (don't await)
    client.rpc("touch_agent_api_key", { p_api_key: apiKey }).then(() => {
      // Intentionally not awaited - fire and forget
    });

    return {
      valid: true,
      agentId: result.agent_id,
      agentName: result.agent_name,
      userId: result.user_id,
    };
  } catch (err) {
    console.error("[AGENT-AUTH] Unexpected error:", err);
    return {
      valid: false,
      error: "Authentication error",
      errorCode: "DB_ERROR",
    };
  }
}

/**
 * Validate agent auth AND verify they are a participant in a specific chat
 *
 * @param req - The incoming request
 * @param chatId - The chat ID to check participation for
 * @param supabase - Optional Supabase client
 * @returns ParticipantAuthResult with validation status and participant info
 */
export async function validateAgentParticipant(
  req: Request,
  chatId: number,
  supabase?: SupabaseClient
): Promise<ParticipantAuthResult> {
  // First validate the API key
  const authResult = await validateAgentAuth(req, supabase);

  if (!authResult.valid) {
    return authResult;
  }

  const client = supabase || getServiceClient();

  try {
    // Check if agent is a participant in this chat
    const { data: participant, error } = await client
      .from("participants")
      .select("id")
      .eq("chat_id", chatId)
      .eq("user_id", authResult.userId)
      .eq("status", "active")
      .single();

    if (error || !participant) {
      return {
        ...authResult,
        valid: false,
        error: "Not a participant in this chat",
        errorCode: "INVALID_API_KEY", // Reuse code for "forbidden"
      };
    }

    return {
      ...authResult,
      participantId: participant.id,
    };
  } catch (err) {
    console.error("[AGENT-AUTH] Error checking participant:", err);
    return {
      ...authResult,
      valid: false,
      error: "Error verifying participation",
      errorCode: "DB_ERROR",
    };
  }
}

/**
 * Error codes for agent API responses
 */
export const AgentErrorCodes = {
  // Auth errors (4xx)
  INVALID_API_KEY: "INVALID_API_KEY",
  MISSING_AUTH: "MISSING_AUTH",
  NOT_PARTICIPANT: "NOT_PARTICIPANT",

  // Rate limiting (429)
  RATE_LIMITED: "RATE_LIMITED",

  // Validation errors (400)
  INVALID_REQUEST: "INVALID_REQUEST",
  WRONG_PHASE: "WRONG_PHASE",
  PHASE_ENDED: "PHASE_ENDED",
  LIMIT_REACHED: "LIMIT_REACHED",
  CONTENT_TOO_LONG: "CONTENT_TOO_LONG",
  INVALID_RATING: "INVALID_RATING",
  CANNOT_RATE_OWN: "CANNOT_RATE_OWN",
  MALICIOUS_CONTENT: "MALICIOUS_CONTENT",

  // Conflict errors (409)
  DUPLICATE: "DUPLICATE",
  ALREADY_PARTICIPANT: "ALREADY_PARTICIPANT",
  AGENT_NAME_TAKEN: "AGENT_NAME_TAKEN",

  // Not found errors (404)
  CHAT_NOT_FOUND: "CHAT_NOT_FOUND",

  // Server errors (500)
  DB_ERROR: "DB_ERROR",
  INTERNAL_ERROR: "INTERNAL_ERROR",
} as const;

export type AgentErrorCode = (typeof AgentErrorCodes)[keyof typeof AgentErrorCodes];

/**
 * Rate limit configurations for agent API endpoints
 * Key format: "agent:<endpoint>:<identifier>"
 */
export const AgentRateLimits = {
  // Registration: 5 requests per hour per IP (prevent mass agent creation)
  register: { maxRequests: 5, windowSeconds: 3600 },

  // Chat creation: 10 per hour per agent
  createChat: { maxRequests: 10, windowSeconds: 3600 },

  // Joining: 30 per hour per agent
  joinChat: { maxRequests: 30, windowSeconds: 3600 },
  joinByCode: { maxRequests: 30, windowSeconds: 3600 },

  // Actions: 60 per hour per agent (matches phase duration)
  propose: { maxRequests: 60, windowSeconds: 3600 },
  rate: { maxRequests: 60, windowSeconds: 3600 },

  // Polling: higher limits for frequent checking
  chatState: { maxRequests: 120, windowSeconds: 60 }, // 120/min
  results: { maxRequests: 60, windowSeconds: 60 }, // 60/min
  listChats: { maxRequests: 30, windowSeconds: 60 }, // 30/min
} as const;
