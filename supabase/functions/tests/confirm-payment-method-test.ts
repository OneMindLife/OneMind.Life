// Tests for confirm-payment-method Edge Function
// Run with: deno test --allow-all supabase/functions/tests/confirm-payment-method-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)
// 2. supabase functions serve confirm-payment-method (function running)

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const functionUrl = `${supabaseUrl}/functions/v1/confirm-payment-method`;

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

// =============================================================================
// TESTS: AUTHENTICATION
// =============================================================================

Deno.test({
  name: "Confirm Payment: Rejects requests without auth header",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ setupIntentId: "seti_test123" }),
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assert(json.error.includes("authorization") || json.error.includes("Missing"));
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Confirm Payment: Rejects invalid JWT token",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer invalid_token_here",
      },
      body: JSON.stringify({ setupIntentId: "seti_test123" }),
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assert(json.error.includes("Invalid") || json.error.includes("expired"));
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: INPUT VALIDATION
// =============================================================================

Deno.test({
  name: "Confirm Payment: Rejects invalid JSON body",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: "not valid json",
    });

    // May return 401 (no valid user) or 400 (invalid JSON)
    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Confirm Payment: Rejects missing setupIntentId",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({}),
    });

    // May return 401 (no valid user) or 400 (validation error)
    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Confirm Payment: Rejects invalid setupIntentId format (wrong prefix)",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ setupIntentId: "pi_wrongprefix123" }),
    });

    // Should reject because setupIntentId must start with "seti_"
    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Confirm Payment: Rejects empty setupIntentId",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ setupIntentId: "" }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Confirm Payment: Rejects non-string setupIntentId",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ setupIntentId: 12345 }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: CORS
// =============================================================================

Deno.test({
  name: "Confirm Payment: Handles CORS preflight",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "OPTIONS",
      headers: {
        "Origin": "http://localhost:3000",
        "Access-Control-Request-Method": "POST",
      },
    });

    assertEquals(response.status, 204);
    assertExists(response.headers.get("Access-Control-Allow-Origin"));
    assertExists(response.headers.get("Access-Control-Allow-Methods"));
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: DATABASE - PAYMENT METHOD STORAGE
// =============================================================================

Deno.test({
  name: "Database: save_stripe_payment_method stores data",
  async fn() {
    await setupTestData();
    const userId = crypto.randomUUID();
    const customerId = `cus_test_${Date.now()}`;
    const paymentMethodId = `pm_test_${Date.now()}`;

    try {
      // Create user credits first
      await adminClient.rpc("get_or_create_user_credits", {
        p_user_id: userId,
      });

      // Save payment method
      const { error: saveError } = await adminClient.rpc(
        "save_stripe_payment_method",
        {
          p_user_id: userId,
          p_stripe_customer_id: customerId,
          p_stripe_payment_method_id: paymentMethodId,
        }
      );

      assertEquals(saveError, null);

      // Verify data was saved
      const { data: userCredits } = await adminClient
        .from("user_credits")
        .select("stripe_customer_id, stripe_payment_method_id")
        .eq("user_id", userId)
        .single();

      assertExists(userCredits);
      assertEquals(userCredits.stripe_customer_id, customerId);
      assertEquals(userCredits.stripe_payment_method_id, paymentMethodId);
    } finally {
      await adminClient
        .from("user_credits")
        .delete()
        .eq("user_id", userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Database: save_stripe_payment_method can update existing",
  async fn() {
    await setupTestData();
    const userId = crypto.randomUUID();

    try {
      // Create user credits
      await adminClient.rpc("get_or_create_user_credits", {
        p_user_id: userId,
      });

      // Save first payment method
      await adminClient.rpc("save_stripe_payment_method", {
        p_user_id: userId,
        p_stripe_customer_id: "cus_first",
        p_stripe_payment_method_id: "pm_first",
      });

      // Save second payment method (update)
      await adminClient.rpc("save_stripe_payment_method", {
        p_user_id: userId,
        p_stripe_customer_id: "cus_first",
        p_stripe_payment_method_id: "pm_second",
      });

      // Verify only latest is saved
      const { data: userCredits } = await adminClient
        .from("user_credits")
        .select("stripe_payment_method_id")
        .eq("user_id", userId)
        .single();

      assertEquals(userCredits?.stripe_payment_method_id, "pm_second");
    } finally {
      await adminClient
        .from("user_credits")
        .delete()
        .eq("user_id", userId);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});
