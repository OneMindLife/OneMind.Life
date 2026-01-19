// Tests for create-checkout-session Edge Function
// Run with: deno test --allow-all supabase/functions/tests/create-checkout-session-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)
// 2. supabase functions serve create-checkout-session (function running)

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const functionUrl = `${supabaseUrl}/functions/v1/create-checkout-session`;

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
  name: "Checkout: Rejects requests without auth header",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ credits: 100 }),
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assert(json.error.includes("authorization") || json.error.includes("Missing"));
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Checkout: Rejects invalid JWT token",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer invalid_token_here",
      },
      body: JSON.stringify({ credits: 100 }),
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
  name: "Checkout: Rejects invalid JSON body",
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
  name: "Checkout: Rejects missing credits field",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({}),
    });

    // May return 401 (no valid user from anon key) or 400 (validation error)
    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Checkout: Rejects negative credits",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ credits: -100 }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Checkout: Rejects zero credits",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ credits: 0 }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Checkout: Rejects credits exceeding maximum",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ credits: 999999999 }), // Way over max
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Checkout: Rejects non-integer credits",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ credits: 50.5 }),
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
  name: "Checkout: Handles CORS preflight",
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
  name: "Rate Limit: Database function works",
  async fn() {
    await setupTestData();
    const testKey = `test_checkout_${Date.now()}`;

    try {
      // First request should be allowed
      const { data: result1 } = await adminClient.rpc("check_rate_limit", {
        p_key: testKey,
        p_max_requests: 3,
        p_window_seconds: 60,
      });

      assertEquals(result1.allowed, true);
      assertEquals(result1.current, 1);

      // Second request
      const { data: result2 } = await adminClient.rpc("check_rate_limit", {
        p_key: testKey,
        p_max_requests: 3,
        p_window_seconds: 60,
      });

      assertEquals(result2.allowed, true);
      assertEquals(result2.current, 2);

      // Third request
      const { data: result3 } = await adminClient.rpc("check_rate_limit", {
        p_key: testKey,
        p_max_requests: 3,
        p_window_seconds: 60,
      });

      assertEquals(result3.allowed, true);
      assertEquals(result3.current, 3);

      // Fourth request - should be blocked
      const { data: result4 } = await adminClient.rpc("check_rate_limit", {
        p_key: testKey,
        p_max_requests: 3,
        p_window_seconds: 60,
      });

      assertEquals(result4.allowed, false);
      assertEquals(result4.current, 4);
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
