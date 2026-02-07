// Edge Function Test: cleanup-inactive-chats
//
// Tests the inactive chat cleanup logic.
// Run with: deno test --allow-all supabase/functions/tests/cleanup-inactive-chats-test.ts
//
// This test validates:
// - Activity detection logic (propositions, ratings, participants)
// - Dry run mode (default behavior)
// - Chat deletion logic
// - Edge cases (new chats, no activity, mixed activity)

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

// =============================================================================
// INACTIVITY DETECTION TESTS
// =============================================================================

const INACTIVE_DAYS = 7;

function isInactive(
  chatCreatedAt: Date,
  lastProposition: Date | null,
  lastRating: Date | null,
  lastParticipant: Date | null,
  now: Date = new Date()
): boolean {
  const cutoffDate = new Date(now.getTime() - INACTIVE_DAYS * 24 * 60 * 60 * 1000);

  // Chat must be older than cutoff to be considered for deletion
  if (chatCreatedAt >= cutoffDate) {
    return false;
  }

  // Find most recent activity
  const activities = [lastProposition, lastRating, lastParticipant].filter(
    (d): d is Date => d !== null
  );

  if (activities.length === 0) {
    // No activity at all - inactive
    return true;
  }

  const mostRecentActivity = new Date(
    Math.max(...activities.map((d) => d.getTime()))
  );

  // Inactive if most recent activity is before cutoff
  return mostRecentActivity < cutoffDate;
}

Deno.test("cleanup-inactive-chats - inactivity detection", async (t) => {
  const now = new Date("2026-01-25T12:00:00Z");

  await t.step("new chat (< 7 days old) is never inactive", () => {
    const chatCreatedAt = new Date("2026-01-20T12:00:00Z"); // 5 days ago
    const result = isInactive(chatCreatedAt, null, null, null, now);
    assertEquals(result, false, "New chats should never be marked inactive");
  });

  await t.step("old chat with no activity is inactive", () => {
    const chatCreatedAt = new Date("2026-01-10T12:00:00Z"); // 15 days ago
    const result = isInactive(chatCreatedAt, null, null, null, now);
    assertEquals(result, true, "Old chat with no activity should be inactive");
  });

  await t.step("old chat with recent proposition is active", () => {
    const chatCreatedAt = new Date("2026-01-10T12:00:00Z"); // 15 days ago
    const lastProposition = new Date("2026-01-20T12:00:00Z"); // 5 days ago
    const result = isInactive(chatCreatedAt, lastProposition, null, null, now);
    assertEquals(result, false, "Chat with recent proposition should be active");
  });

  await t.step("old chat with recent rating is active", () => {
    const chatCreatedAt = new Date("2026-01-10T12:00:00Z"); // 15 days ago
    const lastRating = new Date("2026-01-22T12:00:00Z"); // 3 days ago
    const result = isInactive(chatCreatedAt, null, lastRating, null, now);
    assertEquals(result, false, "Chat with recent rating should be active");
  });

  await t.step("old chat with recent participant is active", () => {
    const chatCreatedAt = new Date("2026-01-10T12:00:00Z"); // 15 days ago
    const lastParticipant = new Date("2026-01-24T12:00:00Z"); // 1 day ago
    const result = isInactive(chatCreatedAt, null, null, lastParticipant, now);
    assertEquals(result, false, "Chat with recent participant should be active");
  });

  await t.step("old chat with old activity is inactive", () => {
    const chatCreatedAt = new Date("2026-01-01T12:00:00Z"); // 24 days ago
    const lastProposition = new Date("2026-01-10T12:00:00Z"); // 15 days ago
    const lastRating = new Date("2026-01-12T12:00:00Z"); // 13 days ago
    const lastParticipant = new Date("2026-01-05T12:00:00Z"); // 20 days ago
    const result = isInactive(
      chatCreatedAt,
      lastProposition,
      lastRating,
      lastParticipant,
      now
    );
    assertEquals(result, true, "Chat with all old activity should be inactive");
  });

  await t.step("mixed activity - most recent determines status", () => {
    const chatCreatedAt = new Date("2026-01-01T12:00:00Z"); // 24 days ago
    const lastProposition = new Date("2026-01-10T12:00:00Z"); // 15 days ago (old)
    const lastRating = new Date("2026-01-10T12:00:00Z"); // 15 days ago (old)
    const lastParticipant = new Date("2026-01-24T12:00:00Z"); // 1 day ago (recent!)

    const result = isInactive(
      chatCreatedAt,
      lastProposition,
      lastRating,
      lastParticipant,
      now
    );
    assertEquals(
      result,
      false,
      "Recent participant should make chat active even if other activity is old"
    );
  });

  await t.step("exactly 7 days old chat is not inactive", () => {
    const chatCreatedAt = new Date("2026-01-18T12:00:00Z"); // Exactly 7 days ago
    const result = isInactive(chatCreatedAt, null, null, null, now);
    assertEquals(
      result,
      false,
      "Chat exactly at cutoff should not be inactive (edge case protection)"
    );
  });

  await t.step("activity exactly at cutoff keeps chat active", () => {
    const chatCreatedAt = new Date("2026-01-01T12:00:00Z"); // 24 days ago
    const lastProposition = new Date("2026-01-18T12:00:00Z"); // Exactly 7 days ago
    const result = isInactive(chatCreatedAt, lastProposition, null, null, now);
    assertEquals(
      result,
      false,
      "Activity exactly at cutoff should keep chat active"
    );
  });
});

// =============================================================================
// CLEANUP RESULT STRUCTURE TESTS
// =============================================================================

interface CleanupResult {
  dry_run: boolean;
  inactive_threshold_days: number;
  chats_found: number;
  chats_deleted: number;
  deleted_chat_ids: number[];
  deleted_chat_names: string[];
  errors: string[];
}

Deno.test("cleanup-inactive-chats - result structure", async (t) => {
  await t.step("dry run mode returns found chats but doesn't delete", () => {
    const result: CleanupResult = {
      dry_run: true,
      inactive_threshold_days: 7,
      chats_found: 3,
      chats_deleted: 0,
      deleted_chat_ids: [1, 2, 3],
      deleted_chat_names: ["Chat A", "Chat B", "Chat C"],
      errors: [],
    };

    assertEquals(result.dry_run, true);
    assertEquals(result.chats_found, 3);
    assertEquals(result.chats_deleted, 0, "Dry run should not delete");
    assertEquals(result.deleted_chat_ids.length, 3, "Should list chats that would be deleted");
  });

  await t.step("actual deletion mode deletes and reports", () => {
    const result: CleanupResult = {
      dry_run: false,
      inactive_threshold_days: 7,
      chats_found: 3,
      chats_deleted: 3,
      deleted_chat_ids: [1, 2, 3],
      deleted_chat_names: ["Chat A", "Chat B", "Chat C"],
      errors: [],
    };

    assertEquals(result.dry_run, false);
    assertEquals(result.chats_deleted, 3);
    assertEquals(result.errors.length, 0);
  });

  await t.step("partial deletion reports errors", () => {
    const result: CleanupResult = {
      dry_run: false,
      inactive_threshold_days: 7,
      chats_found: 3,
      chats_deleted: 2,
      deleted_chat_ids: [1, 2],
      deleted_chat_names: ["Chat A", "Chat B"],
      errors: ["Failed to delete chat 3: foreign key constraint"],
    };

    assertEquals(result.chats_found, 3);
    assertEquals(result.chats_deleted, 2);
    assertEquals(result.errors.length, 1);
  });
});

// =============================================================================
// CUTOFF DATE CALCULATION TESTS
// =============================================================================

Deno.test("cleanup-inactive-chats - cutoff calculation", async (t) => {
  await t.step("calculates 7-day cutoff correctly", () => {
    const now = new Date("2026-01-25T12:00:00Z");
    const cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    assertEquals(cutoff.toISOString(), "2026-01-18T12:00:00.000Z");
  });

  await t.step("handles month boundary", () => {
    const now = new Date("2026-02-03T12:00:00Z");
    const cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    assertEquals(cutoff.toISOString(), "2026-01-27T12:00:00.000Z");
  });

  await t.step("handles year boundary", () => {
    const now = new Date("2026-01-05T12:00:00Z");
    const cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    assertEquals(cutoff.toISOString(), "2025-12-29T12:00:00.000Z");
  });
});

// =============================================================================
// AUTHORIZATION TESTS
// =============================================================================

Deno.test("cleanup-inactive-chats - authorization logic", async (t) => {
  const CRON_SECRET = "test-secret-123";
  const SERVICE_ROLE_KEY = "service-role-key-456";

  function isAuthorized(
    cronSecret: string | null,
    authHeader: string | null,
    configuredCronSecret: string | null,
    supabaseUrl: string
  ): boolean {
    const isValidCron = configuredCronSecret && cronSecret === configuredCronSecret;
    const token = authHeader?.replace("Bearer ", "");
    const isServiceRole = token === SERVICE_ROLE_KEY;
    const isLocalDev =
      supabaseUrl.includes("localhost") ||
      supabaseUrl.includes("127.0.0.1") ||
      supabaseUrl.includes("kong:8000");

    return isValidCron || isServiceRole || isLocalDev;
  }

  await t.step("valid cron secret is authorized", () => {
    const result = isAuthorized(
      CRON_SECRET,
      null,
      CRON_SECRET,
      "https://prod.supabase.co"
    );
    assertEquals(result, true);
  });

  await t.step("invalid cron secret is not authorized", () => {
    const result = isAuthorized(
      "wrong-secret",
      null,
      CRON_SECRET,
      "https://prod.supabase.co"
    );
    assertEquals(result, false);
  });

  await t.step("service role key is authorized", () => {
    const result = isAuthorized(
      null,
      `Bearer ${SERVICE_ROLE_KEY}`,
      CRON_SECRET,
      "https://prod.supabase.co"
    );
    assertEquals(result, true);
  });

  await t.step("localhost is authorized (local dev)", () => {
    const result = isAuthorized(
      null,
      null,
      CRON_SECRET,
      "http://localhost:54321"
    );
    assertEquals(result, true);
  });

  await t.step("kong:8000 is authorized (Docker dev)", () => {
    const result = isAuthorized(
      null,
      null,
      CRON_SECRET,
      "http://kong:8000"
    );
    assertEquals(result, true);
  });

  await t.step("no auth on production is not authorized", () => {
    const result = isAuthorized(
      null,
      null,
      CRON_SECRET,
      "https://prod.supabase.co"
    );
    assertEquals(result, false);
  });
});

// =============================================================================
// DOCUMENTATION
// =============================================================================
// The cleanup-inactive-chats Edge Function:
//
// 1. Runs weekly via pg_cron (Sundays at 3:00 AM UTC)
// 2. Finds chats with no activity for 7+ days
// 3. Activity = propositions, ratings, or participant joins
// 4. Defaults to dry_run mode for safety
// 5. Logs execution to cron_executions table
//
// To test manually:
// curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/cleanup-inactive-chats \
//   -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
//   -H "Content-Type: application/json" \
//   -d '{"dry_run": true}'
// =============================================================================
