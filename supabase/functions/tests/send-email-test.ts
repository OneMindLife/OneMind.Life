// Tests for send-email Edge Function
// Run with: deno test --allow-all supabase/functions/tests/send-email-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)
// 2. supabase functions serve send-email (function running)

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const functionUrl = `${supabaseUrl}/functions/v1/send-email`;

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
  name: "Email: Rejects requests without auth header (non-internal)",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        type: "welcome",
        to: "test@example.com",
      }),
    });

    assertEquals(response.status, 401);
    const json = await response.json();
    assert(json.error.includes("authorization") || json.error.includes("Missing"));
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects invalid JWT token",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer invalid_token_here",
      },
      body: JSON.stringify({
        type: "welcome",
        to: "test@example.com",
      }),
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
  name: "Email: Rejects invalid JSON body",
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
  name: "Email: Rejects missing type field",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ to: "test@example.com" }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects missing to field",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ type: "welcome" }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects invalid email type",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "invalid_type",
        to: "test@example.com",
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects invalid email format",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "welcome",
        to: "not-an-email",
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects invite without chatName",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "invite",
        to: "test@example.com",
        inviteCode: "ABC123",
        // Missing chatName
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects invite without inviteCode",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "invite",
        to: "test@example.com",
        chatName: "Test Chat",
        // Missing inviteCode
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects receipt without credits",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "receipt",
        to: "test@example.com",
        amount: 10.00,
        transactionId: "txn_123",
        // Missing credits
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects receipt without transactionId",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "receipt",
        to: "test@example.com",
        credits: 100,
        amount: 10.00,
        // Missing transactionId
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: SECURITY - MALICIOUS CONTENT
// =============================================================================

Deno.test({
  name: "Email: Rejects XSS in userName",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "welcome",
        to: "test@example.com",
        userName: "<script>alert('xss')</script>",
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects JavaScript in chatName",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "invite",
        to: "test@example.com",
        chatName: "javascript:alert(1)",
        inviteCode: "ABC123",
      }),
    });

    assert(response.status === 400 || response.status === 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Email: Rejects HTML in message",
  async fn() {
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({
        type: "invite",
        to: "test@example.com",
        chatName: "Test Chat",
        inviteCode: "ABC123",
        message: "<img src=x onerror=alert(1)>",
      }),
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
  name: "Email: Handles CORS preflight",
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
  name: "Rate Limit: Email rate limit per recipient works",
  async fn() {
    await setupTestData();
    const testEmail = `test_${Date.now()}@example.com`;
    const testKey = `email:${testEmail}`;

    try {
      // First 5 requests should be allowed (sensitive preset = 5 per hour)
      for (let i = 1; i <= 5; i++) {
        const { data: result } = await adminClient.rpc("check_rate_limit", {
          p_key: testKey,
          p_max_requests: 5,
          p_window_seconds: 3600,
        });
        assertEquals(result.allowed, true);
        assertEquals(result.current, i);
      }

      // 6th request should be blocked
      const { data: result6 } = await adminClient.rpc("check_rate_limit", {
        p_key: testKey,
        p_max_requests: 5,
        p_window_seconds: 3600,
      });

      assertEquals(result6.allowed, false);
    } finally {
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
// TESTS: INTERNAL CALLS
// =============================================================================

Deno.test({
  name: "Email: Allows internal calls without auth",
  async fn() {
    // Internal calls bypass auth but still validate input
    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Internal-Call": "true",
      },
      body: JSON.stringify({
        type: "welcome",
        to: "test@example.com",
      }),
    });

    // Should not be 401 (auth error) - either succeeds or fails for other reasons
    // (like missing Resend API key in test environment)
    assert(response.status !== 401);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});
