// Tests for setup-payment-method Edge Function
// Run with: deno test --allow-all supabase/functions/tests/setup-payment-method-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)
// 2. supabase functions serve setup-payment-method (function running)

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const functionUrl = `${supabaseUrl}/functions/v1/setup-payment-method`;

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
  name: "Setup Payment: Rejects requests without auth header",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assert(json.error.includes("authorization") || json.error.includes("Missing"));
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Setup Payment: Rejects invalid JWT token",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer invalid_token_here",
      },
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assert(json.error.includes("Invalid") || json.error.includes("expired"));
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: CORS
// =============================================================================

Deno.test({
  name: "Setup Payment: Handles CORS preflight",
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
// TESTS: RATE LIMITING
// =============================================================================

Deno.test({
  name: "Rate Limit: Setup payment rate limit key works",
  async fn() {
    await setupTestData();
    const testKey = `test_setup_payment_${Date.now()}`;

    try {
      // First request should be allowed
      const { data: result1 } = await adminClient.rpc("check_rate_limit", {
        p_key: testKey,
        p_max_requests: 10,
        p_window_seconds: 60,
      });

      assertEquals(result1.allowed, true);
      assertEquals(result1.current, 1);

      // Multiple rapid requests
      for (let i = 2; i <= 10; i++) {
        const { data: result } = await adminClient.rpc("check_rate_limit", {
          p_key: testKey,
          p_max_requests: 10,
          p_window_seconds: 60,
        });
        assertEquals(result.allowed, true);
        assertEquals(result.current, i);
      }

      // 11th request should be blocked
      const { data: result11 } = await adminClient.rpc("check_rate_limit", {
        p_key: testKey,
        p_max_requests: 10,
        p_window_seconds: 60,
      });

      assertEquals(result11.allowed, false);
    } finally {
      // Clean up
      await adminClient
        .from("rate_limits")
        .delete()
        .eq("key", testKey);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: DATABASE - STRIPE CUSTOMER ID HANDLING
// =============================================================================

Deno.test({
  name: "Database: get_or_create_user_credits creates record",
  async fn() {
    await setupTestData();
    const userId = crypto.randomUUID();

    try {
      // Call get_or_create
      const { error: createError } = await adminClient.rpc(
        "get_or_create_user_credits",
        { p_user_id: userId }
      );

      assertEquals(createError, null);

      // Verify record was created
      const { data: userCredits } = await adminClient
        .from("user_credits")
        .select("*")
        .eq("user_id", userId)
        .single();

      assertExists(userCredits);
      assertEquals(userCredits.credit_balance, 0);
    } finally {
      // Clean up
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
  name: "Database: stripe_customer_id can be updated",
  async fn() {
    await setupTestData();
    const userId = crypto.randomUUID();

    try {
      // Create user credits
      await adminClient.rpc("get_or_create_user_credits", {
        p_user_id: userId,
      });

      // Update with customer ID
      const testCustomerId = `cus_test_${Date.now()}`;
      const { error: updateError } = await adminClient
        .from("user_credits")
        .update({ stripe_customer_id: testCustomerId })
        .eq("user_id", userId);

      assertEquals(updateError, null);

      // Verify update
      const { data: userCredits } = await adminClient
        .from("user_credits")
        .select("stripe_customer_id")
        .eq("user_id", userId)
        .single();

      assertEquals(userCredits?.stripe_customer_id, testCustomerId);
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
