/**
 * Edge Function: agent-register
 *
 * Register a new AI agent and get API credentials.
 *
 * POST /agent-register
 * Body: { agent_name: string, description?: string }
 *
 * Returns:
 * - 201: { success: true, agent_id: string, api_key: string, message: string }
 * - 400: Invalid request (bad agent name, missing fields)
 * - 409: Agent name already taken
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { z } from "npm:zod@3.23.8";
import {
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";
import { AgentErrorCodes, AgentRateLimits, hashApiKey } from "../_shared/agent-auth.ts";
import { RateLimiter, rateLimitResponse } from "../_shared/rate-limiter.ts";

// Environment variables
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Initialize Supabase client with service role for admin operations
const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

// Request body schema
const RequestSchema = z.object({
  agent_name: z
    .string()
    .min(3, "Agent name must be at least 3 characters")
    .max(50, "Agent name must be at most 50 characters")
    .regex(
      /^[a-zA-Z][a-zA-Z0-9_-]*$/,
      "Agent name must start with a letter and contain only letters, numbers, underscores, and hyphens"
    ),
  description: z
    .string()
    .max(500, "Description must be at most 500 characters")
    .optional(),
});

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  // Only accept POST
  if (req.method !== "POST") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  // Rate limit by IP address (since no auth exists yet)
  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("x-real-ip") ||
    "unknown";
  const rateLimiter = new RateLimiter(supabase);
  const rateLimit = await rateLimiter.check({
    key: `agent:register:${clientIp}`,
    ...AgentRateLimits.register,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-REGISTER] Rate limited IP: ${clientIp}`);
    return rateLimitResponse(rateLimit);
  }

  try {
    // Parse and validate request body
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return corsErrorResponse(
        "Invalid JSON body",
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }

    const validationResult = RequestSchema.safeParse(body);
    if (!validationResult.success) {
      const errors = validationResult.error.errors
        .map((e) => `${e.path.join(".")}: ${e.message}`)
        .join(", ");
      return corsErrorResponse(
        `Validation error: ${errors}`,
        req,
        400,
        AgentErrorCodes.INVALID_REQUEST
      );
    }

    const { agent_name, description } = validationResult.data;

    console.log(`[AGENT-REGISTER] Registering agent: ${agent_name}`);

    // Check if agent name already exists
    const { data: existingAgent, error: checkError } = await supabase
      .from("agent_api_keys")
      .select("id")
      .eq("agent_name", agent_name)
      .maybeSingle();

    if (checkError) {
      console.error("[AGENT-REGISTER] Error checking existing agent:", checkError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    if (existingAgent) {
      return corsErrorResponse(
        `Agent name "${agent_name}" is already taken`,
        req,
        409,
        AgentErrorCodes.AGENT_NAME_TAKEN
      );
    }

    // Create a pseudo-user in auth.users for this agent
    // This allows all existing RLS policies to work with auth.uid()
    const agentEmail = `${agent_name.toLowerCase()}@agent.onemind.life`;
    const randomPassword = crypto.randomUUID() + crypto.randomUUID();

    const { data: authUser, error: authError } = await supabase.auth.admin.createUser({
      email: agentEmail,
      password: randomPassword,
      email_confirm: true, // Auto-confirm the email
      user_metadata: {
        display_name: `Agent: ${agent_name}`,
        is_agent: true,
        agent_name: agent_name,
      },
    });

    if (authError || !authUser.user) {
      console.error("[AGENT-REGISTER] Error creating auth user:", authError);
      return corsErrorResponse(
        "Failed to create agent user",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    const userId = authUser.user.id;
    console.log(`[AGENT-REGISTER] Created pseudo-user: ${userId}`);

    // Generate a secure API key
    const { data: apiKeyData, error: keyError } = await supabase.rpc(
      "generate_agent_api_key"
    );

    if (keyError || !apiKeyData) {
      console.error("[AGENT-REGISTER] Error generating API key:", keyError);
      // Clean up the user we just created
      await supabase.auth.admin.deleteUser(userId);
      return corsErrorResponse(
        "Failed to generate API key",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    const apiKey = apiKeyData as string;

    // Hash the API key before storage - plaintext is only returned once
    const apiKeyHash = await hashApiKey(apiKey);

    // Insert the agent record with hashed key
    const { data: agent, error: insertError } = await supabase
      .from("agent_api_keys")
      .insert({
        api_key_hash: apiKeyHash,
        agent_name: agent_name,
        description: description || null,
        user_id: userId,
      })
      .select("id")
      .single();

    if (insertError || !agent) {
      console.error("[AGENT-REGISTER] Error inserting agent:", insertError);
      // Clean up the user we just created
      await supabase.auth.admin.deleteUser(userId);
      return corsErrorResponse(
        "Failed to create agent record",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    console.log(`[AGENT-REGISTER] Successfully registered agent: ${agent.id}`);

    return corsJsonResponse(
      {
        success: true,
        agent_id: agent.id,
        api_key: apiKey,
        message:
          "Save your API key securely - it cannot be retrieved later! Use it in the Authorization header as: Bearer " +
          apiKey.substring(0, 20) +
          "...",
      },
      req,
      201
    );
  } catch (error) {
    console.error("[AGENT-REGISTER] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
