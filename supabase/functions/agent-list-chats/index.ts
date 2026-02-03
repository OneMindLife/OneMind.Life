/**
 * Edge Function: agent-list-chats
 *
 * List public chats available for agents to join, with optional search.
 *
 * GET /agent-list-chats?search=keyword&limit=20&offset=0
 * Headers: Authorization: Bearer onemind_sk_...
 *
 * Query params:
 * - search: Optional search term (searches name, description, initial_message)
 * - limit: Max results (default 20, max 100)
 * - offset: Pagination offset (default 0)
 * - include_joined: Include chats agent has already joined (default false)
 *
 * Returns:
 * - 200: { chats: [...], total: number, limit: number, offset: number }
 * - 401: Invalid API key
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";
import {
  validateAgentAuth,
  getServiceClient,
  AgentErrorCodes,
  AgentRateLimits,
} from "../_shared/agent-auth.ts";
import { RateLimiter, rateLimitResponse } from "../_shared/rate-limiter.ts";

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  // Only accept GET
  if (req.method !== "GET") {
    return corsErrorResponse("Method not allowed", req, 405);
  }

  // Validate API key
  const supabase = getServiceClient();
  const authResult = await validateAgentAuth(req, supabase);

  if (!authResult.valid) {
    return corsErrorResponse(
      authResult.error || "Unauthorized",
      req,
      401,
      authResult.errorCode
    );
  }

  // Rate limit by agent ID (prevent scraping)
  const rateLimiter = new RateLimiter(supabase);
  const rateLimit = await rateLimiter.check({
    key: `agent:list-chats:${authResult.agentId}`,
    ...AgentRateLimits.listChats,
  });

  if (!rateLimit.allowed) {
    console.log(`[AGENT-LIST-CHATS] Rate limited agent: ${authResult.agentName}`);
    return rateLimitResponse(rateLimit);
  }

  try {
    // Parse query parameters
    const url = new URL(req.url);
    const search = url.searchParams.get("search")?.trim() || "";
    const limitParam = url.searchParams.get("limit");
    const offsetParam = url.searchParams.get("offset");
    const includeJoinedParam = url.searchParams.get("include_joined");

    let limit = 20;
    if (limitParam) {
      const parsed = parseInt(limitParam, 10);
      if (!isNaN(parsed) && parsed > 0 && parsed <= 100) {
        limit = parsed;
      }
    }

    let offset = 0;
    if (offsetParam) {
      const parsed = parseInt(offsetParam, 10);
      if (!isNaN(parsed) && parsed >= 0) {
        offset = parsed;
      }
    }

    const includeJoined = includeJoinedParam === "true";

    console.log(
      `[AGENT-LIST-CHATS] Agent ${authResult.agentName} searching: "${search}" (limit=${limit}, offset=${offset})`
    );

    // Build the query for public chats
    let query = supabase
      .from("chats")
      .select(
        `
        id,
        name,
        description,
        initial_message,
        invite_code,
        is_official,
        proposing_duration_seconds,
        rating_duration_seconds,
        propositions_per_user,
        confirmation_rounds,
        start_mode,
        auto_start_participant_count,
        created_at,
        last_activity_at,
        participants!inner (
          id,
          user_id,
          status
        )
      `,
        { count: "exact" }
      )
      .eq("access_method", "code") // Public chats only
      .eq("require_approval", false) // Open access only
      .eq("is_active", true);

    // Apply search filter if provided
    if (search) {
      // Search in name, description, and initial_message
      query = query.or(
        `name.ilike.%${search}%,description.ilike.%${search}%,initial_message.ilike.%${search}%`
      );
    }

    // Order by activity and limit
    query = query
      .order("last_activity_at", { ascending: false, nullsFirst: false })
      .range(offset, offset + limit - 1);

    const { data: chats, error: queryError, count } = await query;

    if (queryError) {
      console.error("[AGENT-LIST-CHATS] Query error:", queryError);
      return corsErrorResponse(
        "Database error",
        req,
        500,
        AgentErrorCodes.DB_ERROR
      );
    }

    // Process chats to add participant count and filter if needed
    interface ChatRow {
      id: number;
      name: string;
      description: string | null;
      initial_message: string;
      invite_code: string;
      is_official: boolean;
      proposing_duration_seconds: number;
      rating_duration_seconds: number;
      propositions_per_user: number;
      confirmation_rounds: number;
      start_mode: string;
      auto_start_participant_count: number;
      created_at: string;
      last_activity_at: string | null;
      participants: Array<{ id: number; user_id: string; status: string }>;
    }

    const processedChats = (chats as ChatRow[] || [])
      .map((chat) => {
        const activeParticipants = chat.participants.filter(
          (p) => p.status === "active"
        );
        const isJoined = activeParticipants.some(
          (p) => p.user_id === authResult.userId
        );

        return {
          id: chat.id,
          name: chat.name,
          description: chat.description,
          initial_message: chat.initial_message,
          invite_code: chat.invite_code,
          is_official: chat.is_official,
          participant_count: activeParticipants.length,
          proposing_duration_seconds: chat.proposing_duration_seconds,
          rating_duration_seconds: chat.rating_duration_seconds,
          propositions_per_user: chat.propositions_per_user,
          confirmation_rounds: chat.confirmation_rounds,
          start_mode: chat.start_mode,
          auto_start_participant_count: chat.auto_start_participant_count,
          created_at: chat.created_at,
          last_activity_at: chat.last_activity_at,
          is_joined: isJoined,
        };
      })
      .filter((chat) => includeJoined || !chat.is_joined);

    return corsJsonResponse(
      {
        chats: processedChats,
        total: count ?? 0,
        limit,
        offset,
        search: search || null,
      },
      req,
      200
    );
  } catch (error) {
    console.error("[AGENT-LIST-CHATS] Unexpected error:", error);
    return corsErrorResponse(
      error instanceof Error ? error.message : "Unknown error",
      req,
      500,
      AgentErrorCodes.INTERNAL_ERROR
    );
  }
});
