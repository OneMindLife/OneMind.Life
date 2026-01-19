// Tests for stripe-webhook Edge Function
// Run with: deno test --allow-all supabase/functions/tests/stripe-webhook-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)
// 2. supabase functions serve stripe-webhook (function running)
//
// Note: Full integration tests require valid Stripe test keys

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const functionUrl = `${supabaseUrl}/functions/v1/stripe-webhook`;

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

async function cleanupTestUser(userId: string) {
  // Clean up credit transactions
  await adminClient
    .from("credit_transactions")
    .delete()
    .eq("user_id", userId);

  // Clean up user credits
  await adminClient
    .from("user_credits")
    .delete()
    .eq("user_id", userId);
}

async function createTestUser() {
  const userId = crypto.randomUUID();

  // Create user credits record
  const { error } = await adminClient
    .from("user_credits")
    .insert({
      user_id: userId,
      credit_balance: 0,
    });

  if (error) throw error;
  return userId;
}

// =============================================================================
// TESTS: HTTP METHOD VALIDATION
// =============================================================================

Deno.test({
  name: "Webhook: Rejects non-POST requests",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "GET",
    });

    assertEquals(response.status, 405);
    const text = await response.text();
    assertEquals(text, "Method not allowed");
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Webhook: Rejects requests without stripe-signature",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });

    assertEquals(response.status, 400);
    const text = await response.text();
    assertEquals(text, "Missing stripe-signature header");
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Webhook: Rejects invalid signature",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "stripe-signature": "t=12345,v1=invalid_signature",
      },
      body: JSON.stringify({
        id: "evt_test",
        type: "checkout.session.completed",
      }),
    });

    assertEquals(response.status, 400);
    const json = await response.json();
    assertEquals(json.code, "INVALID_SIGNATURE");
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: DATABASE IDEMPOTENCY
// =============================================================================

Deno.test({
  name: "Database: add_purchased_credits is idempotent",
  async fn() {
    await setupTestData();
    const userId = await createTestUser();
    const sessionId = `test_session_${Date.now()}`;

    try {
      // First call - should succeed
      const { data: result1, error: error1 } = await adminClient.rpc(
        "add_purchased_credits",
        {
          p_user_id: userId,
          p_credit_amount: 100,
          p_stripe_checkout_session_id: sessionId,
          p_stripe_payment_intent_id: "pi_test_123",
          p_stripe_event_id: "evt_test_123",
        }
      );

      assertEquals(error1, null);
      assertExists(result1);
      assertEquals(result1.credit_balance, 100);

      // Second call with same session - should fail with unique constraint
      const { error: error2 } = await adminClient.rpc(
        "add_purchased_credits",
        {
          p_user_id: userId,
          p_credit_amount: 100,
          p_stripe_checkout_session_id: sessionId, // Same session ID
          p_stripe_payment_intent_id: "pi_test_456",
          p_stripe_event_id: "evt_test_456",
        }
      );

      // Should fail due to unique constraint
      assertExists(error2);
      assert(
        error2.code === "23505" || error2.message?.includes("unique"),
        `Expected unique constraint violation, got: ${error2.message}`
      );

      // Verify balance wasn't double-credited
      const { data: credits } = await adminClient
        .from("user_credits")
        .select("credit_balance")
        .eq("user_id", userId)
        .single();

      assertEquals(credits?.credit_balance, 100);
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Database: add_purchased_credits creates transaction record",
  async fn() {
    await setupTestData();
    const userId = await createTestUser();
    const sessionId = `test_session_txn_${Date.now()}`;

    try {
      await adminClient.rpc("add_purchased_credits", {
        p_user_id: userId,
        p_credit_amount: 50,
        p_stripe_checkout_session_id: sessionId,
        p_stripe_payment_intent_id: "pi_test_txn",
        p_stripe_event_id: "evt_test_txn",
      });

      // Verify transaction was created
      const { data: transactions } = await adminClient
        .from("credit_transactions")
        .select("*")
        .eq("user_id", userId)
        .eq("stripe_checkout_session_id", sessionId);

      assertExists(transactions);
      assertEquals(transactions.length, 1);
      assertEquals(transactions[0].credit_amount, 50);
      assertEquals(transactions[0].transaction_type, "purchase");
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Database: Credits can be added multiple times with different sessions",
  async fn() {
    await setupTestData();
    const userId = await createTestUser();

    try {
      // First purchase
      await adminClient.rpc("add_purchased_credits", {
        p_user_id: userId,
        p_credit_amount: 100,
        p_stripe_checkout_session_id: `session_1_${Date.now()}`,
        p_stripe_payment_intent_id: "pi_1",
      });

      // Second purchase (different session)
      await adminClient.rpc("add_purchased_credits", {
        p_user_id: userId,
        p_credit_amount: 50,
        p_stripe_checkout_session_id: `session_2_${Date.now()}`,
        p_stripe_payment_intent_id: "pi_2",
      });

      // Verify total balance
      const { data: credits } = await adminClient
        .from("user_credits")
        .select("credit_balance")
        .eq("user_id", userId)
        .single();

      assertEquals(credits?.credit_balance, 150);
    } finally {
      await cleanupTestUser(userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: WEBHOOK EVENT LOGGING
// =============================================================================

Deno.test({
  name: "Database: Webhook events can be logged",
  async fn() {
    await setupTestData();
    const eventId = `evt_test_log_${Date.now()}`;

    try {
      const { error } = await adminClient.rpc("log_stripe_webhook_event", {
        p_event_id: eventId,
        p_event_type: "checkout.session.completed",
        p_status: "success",
        p_error_message: null,
        p_metadata: { test: true },
      });

      assertEquals(error, null);

      // Verify event was logged
      const { data: events } = await adminClient
        .from("stripe_webhook_events")
        .select("*")
        .eq("event_id", eventId);

      assertExists(events);
      assertEquals(events.length, 1);
      assertEquals(events[0].status, "success");
    } finally {
      // Clean up
      await adminClient
        .from("stripe_webhook_events")
        .delete()
        .eq("event_id", eventId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Database: Duplicate webhook events are handled",
  async fn() {
    await setupTestData();
    const eventId = `evt_test_dup_${Date.now()}`;

    try {
      // First log
      await adminClient.rpc("log_stripe_webhook_event", {
        p_event_id: eventId,
        p_event_type: "checkout.session.completed",
        p_status: "success",
        p_error_message: null,
        p_metadata: { attempt: 1 },
      });

      // Second log with same event ID - should update or be ignored
      const { error } = await adminClient.rpc("log_stripe_webhook_event", {
        p_event_id: eventId,
        p_event_type: "checkout.session.completed",
        p_status: "duplicate",
        p_error_message: null,
        p_metadata: { attempt: 2 },
      });

      // Should not error (upsert behavior)
      assertEquals(error, null);
    } finally {
      await adminClient
        .from("stripe_webhook_events")
        .delete()
        .eq("event_id", eventId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});
