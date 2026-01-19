// Tests for process-auto-refill Edge Function
// Run with: deno test --allow-all supabase/functions/tests/process-auto-refill-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)
// 2. supabase functions serve process-auto-refill (function running)
// 3. CRON_SECRET env var set

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
const functionUrl = `${supabaseUrl}/functions/v1/process-auto-refill`;

let adminClient: SupabaseClient;

// =============================================================================
// TEST HELPERS
// =============================================================================

async function setupTestData() {
  adminClient = createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function createTestUserWithCredits(options: {
  creditBalance?: number;
  stripeCustomerId?: string;
  stripePaymentMethodId?: string;
}): Promise<string> {
  const userId = crypto.randomUUID();

  await adminClient.from("user_credits").insert({
    user_id: userId,
    credit_balance: options.creditBalance ?? 0,
    stripe_customer_id: options.stripeCustomerId ?? null,
    stripe_payment_method_id: options.stripePaymentMethodId ?? null,
  });

  return userId;
}

async function cleanupTestUser(userId: string) {
  await adminClient
    .from("auto_refill_queue")
    .delete()
    .eq("user_id", userId);

  await adminClient
    .from("credit_transactions")
    .delete()
    .eq("user_id", userId);

  await adminClient
    .from("user_credits")
    .delete()
    .eq("user_id", userId);
}

// =============================================================================
// TESTS: AUTHENTICATION
// =============================================================================

Deno.test({
  name: "Auto-Refill: Rejects requests without auth header",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assertEquals(json.error, "Unauthorized");
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Auto-Refill: Rejects invalid cron secret",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer wrong_secret",
      },
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assertEquals(json.error, "Unauthorized");
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Auto-Refill: Accepts valid cron secret (empty queue)",
  async fn() {
    if (!cronSecret) {
      console.log("Skipping: CRON_SECRET not set");
      return;
    }

    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${cronSecret}`,
      },
    });

    assertEquals(response.status, 200);
    const json = await response.json();
    // Either "No pending auto-refills" or a result object
    assert(json.message === "No pending auto-refills" || json.result !== undefined);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: DATABASE - AUTO-REFILL QUEUE
// =============================================================================

Deno.test({
  name: "Database: Auto-refill queue can be created",
  async fn() {
    await setupTestData();
    const userId = await createTestUserWithCredits({});

    try {
      const { error: insertError } = await adminClient
        .from("auto_refill_queue")
        .insert({
          user_id: userId,
          credits_to_add: 100,
          status: "pending",
        });

      assertEquals(insertError, null);

      // Verify queue item
      const { data: queueItems } = await adminClient
        .from("auto_refill_queue")
        .select("*")
        .eq("user_id", userId);

      assertExists(queueItems);
      assertEquals(queueItems.length, 1);
      assertEquals(queueItems[0].credits_to_add, 100);
      assertEquals(queueItems[0].status, "pending");
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Database: Auto-refill queue status can be updated",
  async fn() {
    await setupTestData();
    const userId = await createTestUserWithCredits({});

    try {
      // Create queue item
      const { data: insertData } = await adminClient
        .from("auto_refill_queue")
        .insert({
          user_id: userId,
          credits_to_add: 50,
          status: "pending",
        })
        .select()
        .single();

      const queueId = insertData!.id;

      // Update to processing
      await adminClient
        .from("auto_refill_queue")
        .update({ status: "processing" })
        .eq("id", queueId);

      // Verify update
      const { data: processing } = await adminClient
        .from("auto_refill_queue")
        .select("status")
        .eq("id", queueId)
        .single();

      assertEquals(processing?.status, "processing");

      // Update to completed
      await adminClient
        .from("auto_refill_queue")
        .update({
          status: "completed",
          stripe_payment_intent_id: "pi_test",
          processed_at: new Date().toISOString(),
        })
        .eq("id", queueId);

      // Verify completed
      const { data: completed } = await adminClient
        .from("auto_refill_queue")
        .select("*")
        .eq("id", queueId)
        .single();

      assertEquals(completed?.status, "completed");
      assertEquals(completed?.stripe_payment_intent_id, "pi_test");
      assertExists(completed?.processed_at);
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Database: Auto-refill queue can track failures",
  async fn() {
    await setupTestData();
    const userId = await createTestUserWithCredits({});

    try {
      // Create queue item
      const { data: insertData } = await adminClient
        .from("auto_refill_queue")
        .insert({
          user_id: userId,
          credits_to_add: 100,
          status: "pending",
        })
        .select()
        .single();

      const queueId = insertData!.id;

      // Update to failed
      const errorMessage = "Payment method declined";
      await adminClient
        .from("auto_refill_queue")
        .update({
          status: "failed",
          error_message: errorMessage,
          processed_at: new Date().toISOString(),
        })
        .eq("id", queueId);

      // Verify failure
      const { data: failed } = await adminClient
        .from("auto_refill_queue")
        .select("*")
        .eq("id", queueId)
        .single();

      assertEquals(failed?.status, "failed");
      assertEquals(failed?.error_message, errorMessage);
      assertExists(failed?.processed_at);
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Database: Auto-refill last error is stored on user_credits",
  async fn() {
    await setupTestData();
    const userId = await createTestUserWithCredits({});

    try {
      const errorMessage = "Card declined";

      // Update user credits with error
      await adminClient
        .from("user_credits")
        .update({ auto_refill_last_error: errorMessage })
        .eq("user_id", userId);

      // Verify error is stored
      const { data: userCredits } = await adminClient
        .from("user_credits")
        .select("auto_refill_last_error")
        .eq("user_id", userId)
        .single();

      assertEquals(userCredits?.auto_refill_last_error, errorMessage);

      // Clear error
      await adminClient
        .from("user_credits")
        .update({ auto_refill_last_error: null })
        .eq("user_id", userId);

      // Verify cleared
      const { data: cleared } = await adminClient
        .from("user_credits")
        .select("auto_refill_last_error")
        .eq("user_id", userId)
        .single();

      assertEquals(cleared?.auto_refill_last_error, null);
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: DATABASE - AUTO-REFILL SETTINGS
// =============================================================================

Deno.test({
  name: "Database: Auto-refill settings can be configured",
  async fn() {
    await setupTestData();
    const userId = await createTestUserWithCredits({
      stripeCustomerId: "cus_test",
      stripePaymentMethodId: "pm_test",
    });

    try {
      // Enable auto-refill
      await adminClient
        .from("user_credits")
        .update({
          auto_refill_enabled: true,
          auto_refill_threshold: 10,
          auto_refill_amount: 100,
        })
        .eq("user_id", userId);

      // Verify settings
      const { data: userCredits } = await adminClient
        .from("user_credits")
        .select("auto_refill_enabled, auto_refill_threshold, auto_refill_amount")
        .eq("user_id", userId)
        .single();

      assertEquals(userCredits?.auto_refill_enabled, true);
      assertEquals(userCredits?.auto_refill_threshold, 10);
      assertEquals(userCredits?.auto_refill_amount, 100);
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});
