// Edge Function: cleanup-inactive-chats
// Runs on a weekly schedule (every 7 days) to delete inactive chats
//
// Definition of "inactive": No activity for 7 days, where activity is:
// - New propositions submitted
// - New ratings submitted
// - New participants joined
//
// Safety: Chats younger than 7 days are never deleted

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Secret for cron job authentication
const CRON_SECRET = Deno.env.get("CRON_SECRET");

if (!CRON_SECRET) {
  console.warn("CRON_SECRET not set - only service role auth will work");
}

// Inactivity threshold in days
const INACTIVE_DAYS = 7;

interface InactiveChat {
  id: number;
  name: string;
  created_at: string;
  last_activity: string | null;
}

interface CleanupResult {
  dry_run: boolean;
  inactive_threshold_days: number;
  chats_found: number;
  chats_deleted: number;
  deleted_chat_ids: number[];
  deleted_chat_names: string[];
  errors: string[];
}

Deno.serve(async (req: Request) => {
  // ==========================================================================
  // AUTH VERIFICATION
  // Only allow requests from cron job (with secret) or service role
  // ==========================================================================
  const authHeader = req.headers.get("Authorization");
  const cronSecret = req.headers.get("X-Cron-Secret");

  const isValidCron = CRON_SECRET && cronSecret === CRON_SECRET;
  const token = authHeader?.replace("Bearer ", "");
  const isServiceRole = token === supabaseServiceKey;

  // Allow local development
  const isLocalDev = supabaseUrl.includes("localhost") ||
                     supabaseUrl.includes("127.0.0.1") ||
                     supabaseUrl.includes("kong:8000");

  if (!isValidCron && !isServiceRole && !isLocalDev) {
    console.log("Auth failed:", {
      hasAuthHeader: !!authHeader,
      hasCronSecret: !!cronSecret,
      isLocalDev,
    });
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // ==========================================================================
  // PARSE REQUEST OPTIONS
  // ==========================================================================
  let dryRun = true; // Default to dry run for safety
  try {
    const body = await req.json().catch(() => ({}));
    if (body.dry_run === false) {
      dryRun = false;
    }
  } catch {
    // Keep default dry_run = true
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);
  const now = new Date();
  const cutoffDate = new Date(now.getTime() - INACTIVE_DAYS * 24 * 60 * 60 * 1000);

  const result: CleanupResult = {
    dry_run: dryRun,
    inactive_threshold_days: INACTIVE_DAYS,
    chats_found: 0,
    chats_deleted: 0,
    deleted_chat_ids: [],
    deleted_chat_names: [],
    errors: [],
  };

  // Start cron execution logging
  let executionId: number | null = null;
  try {
    const { data } = await supabase.rpc("cron_execution_start", {
      p_job_name: "cleanup-inactive-chats",
      p_metadata: { triggered_at: now.toISOString(), dry_run: dryRun },
    });
    executionId = data;
  } catch (e) {
    console.warn("Failed to log cron start:", e);
  }

  try {
    // ==========================================================================
    // FIND INACTIVE CHATS
    // ==========================================================================
    // A chat is inactive if it has no activity in the last 7 days.
    // Activity = propositions, ratings, or participant joins.
    // Chats younger than 7 days are never considered inactive.
    // ==========================================================================

    const { data: inactiveChats, error: queryError } = await supabase.rpc(
      "find_inactive_chats",
      { p_inactive_days: INACTIVE_DAYS }
    );

    if (queryError) {
      // If the RPC doesn't exist, use inline query
      console.warn("RPC not found, using inline query:", queryError.message);

      const { data: chats, error: inlineError } = await supabase
        .from("chats")
        .select("id, name, created_at")
        .lt("created_at", cutoffDate.toISOString());

      if (inlineError) {
        throw inlineError;
      }

      // Filter to find truly inactive chats
      const inactiveChatList: InactiveChat[] = [];

      for (const chat of chats || []) {
        const lastActivity = await getLastActivity(supabase, chat.id, cutoffDate);

        if (!lastActivity) {
          inactiveChatList.push({
            id: chat.id,
            name: chat.name,
            created_at: chat.created_at,
            last_activity: null,
          });
        }
      }

      result.chats_found = inactiveChatList.length;

      if (!dryRun && inactiveChatList.length > 0) {
        await deleteChats(supabase, inactiveChatList, result);
      } else {
        result.deleted_chat_ids = inactiveChatList.map(c => c.id);
        result.deleted_chat_names = inactiveChatList.map(c => c.name);
      }
    } else {
      // RPC succeeded
      result.chats_found = inactiveChats?.length || 0;

      if (!dryRun && inactiveChats && inactiveChats.length > 0) {
        await deleteChats(supabase, inactiveChats, result);
      } else if (inactiveChats) {
        result.deleted_chat_ids = inactiveChats.map((c: InactiveChat) => c.id);
        result.deleted_chat_names = inactiveChats.map((c: InactiveChat) => c.name);
      }
    }

    // Log summary
    console.log(`Cleanup complete: ${result.chats_found} inactive chats found, ` +
                `${result.chats_deleted} deleted (dry_run=${dryRun})`);

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
// GET LAST ACTIVITY FOR A CHAT
// =============================================================================
// Returns null if no activity within cutoff, otherwise returns the date

async function getLastActivity(
  supabase: ReturnType<typeof createClient>,
  chatId: number,
  cutoffDate: Date
): Promise<Date | null> {
  const cutoffStr = cutoffDate.toISOString();

  // Check for recent propositions
  const { data: recentProposition } = await supabase
    .from("propositions")
    .select("created_at, rounds!inner(cycles!inner(chat_id))")
    .eq("rounds.cycles.chat_id", chatId)
    .gte("created_at", cutoffStr)
    .limit(1)
    .maybeSingle();

  if (recentProposition) {
    return new Date(recentProposition.created_at);
  }

  // Check for recent ratings (via propositions)
  const { data: recentRating } = await supabase
    .from("ratings")
    .select("created_at, propositions!inner(rounds!inner(cycles!inner(chat_id)))")
    .eq("propositions.rounds.cycles.chat_id", chatId)
    .gte("created_at", cutoffStr)
    .limit(1)
    .maybeSingle();

  if (recentRating) {
    return new Date(recentRating.created_at);
  }

  // Check for recent participants
  const { data: recentParticipant } = await supabase
    .from("participants")
    .select("created_at")
    .eq("chat_id", chatId)
    .gte("created_at", cutoffStr)
    .limit(1)
    .maybeSingle();

  if (recentParticipant) {
    return new Date(recentParticipant.created_at);
  }

  return null;
}

// =============================================================================
// DELETE INACTIVE CHATS
// =============================================================================

async function deleteChats(
  supabase: ReturnType<typeof createClient>,
  chats: InactiveChat[],
  result: CleanupResult
): Promise<void> {
  for (const chat of chats) {
    try {
      console.log(`Deleting inactive chat: ${chat.id} (${chat.name})`);

      const { error } = await supabase
        .from("chats")
        .delete()
        .eq("id", chat.id);

      if (error) {
        result.errors.push(`Failed to delete chat ${chat.id}: ${error.message}`);
      } else {
        result.chats_deleted++;
        result.deleted_chat_ids.push(chat.id);
        result.deleted_chat_names.push(chat.name);
      }
    } catch (err) {
      result.errors.push(`Error deleting chat ${chat.id}: ${err.message}`);
    }
  }
}
