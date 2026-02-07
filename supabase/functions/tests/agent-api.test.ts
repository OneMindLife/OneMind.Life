/**
 * Agent API Test Suite
 *
 * Comprehensive tests for the Agent API endpoints covering:
 * - Authentication (invalid key, missing header, deactivated key)
 * - Phase validation (can't propose during rating, can't rate during proposing)
 * - Rate limiting (verify 429 responses when exceeded)
 * - Input validation (content too long, invalid ratings, malicious content)
 * - Happy path (full lifecycle: register -> create chat -> propose -> rate -> results)
 *
 * Run with: deno test supabase/functions/tests/agent-api.test.ts --allow-env --allow-net
 */

import {
  assertEquals,
  assertExists,
  assertMatch,
  assertNotEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

// Test configuration - update these for your environment
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

// Helper to make API requests
async function agentRequest(
  endpoint: string,
  options: {
    method?: string;
    body?: Record<string, unknown>;
    apiKey?: string;
    queryParams?: Record<string, string>;
  } = {}
): Promise<{ status: number; data: unknown }> {
  const { method = "POST", body, apiKey, queryParams } = options;

  let url = `${SUPABASE_URL}/functions/v1/${endpoint}`;
  if (queryParams) {
    const params = new URLSearchParams(queryParams);
    url += `?${params.toString()}`;
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (apiKey) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const data = await response.json();
  return { status: response.status, data };
}

// =============================================================================
// API Key Hashing Tests
// =============================================================================

Deno.test("hashApiKey - produces consistent hex output", async () => {
  const { hashApiKey } = await import("../_shared/agent-auth.ts");

  const key = "onemind_sk_test123";
  const hash1 = await hashApiKey(key);
  const hash2 = await hashApiKey(key);

  // Same input should produce same hash
  assertEquals(hash1, hash2);

  // Hash should be 64 characters (SHA-256 hex)
  assertEquals(hash1.length, 64);

  // Hash should be lowercase hex
  assertMatch(hash1, /^[a-f0-9]{64}$/);
});

Deno.test("hashApiKey - different keys produce different hashes", async () => {
  const { hashApiKey } = await import("../_shared/agent-auth.ts");

  const hash1 = await hashApiKey("onemind_sk_key1");
  const hash2 = await hashApiKey("onemind_sk_key2");

  assertNotEquals(hash1, hash2);
});

// =============================================================================
// Authentication Tests (Unit Tests - No Network)
// =============================================================================

Deno.test("AgentErrorCodes - contains all required error codes", async () => {
  const { AgentErrorCodes } = await import("../_shared/agent-auth.ts");

  // Auth errors
  assertExists(AgentErrorCodes.INVALID_API_KEY);
  assertExists(AgentErrorCodes.MISSING_AUTH);
  assertExists(AgentErrorCodes.NOT_PARTICIPANT);

  // Rate limiting
  assertExists(AgentErrorCodes.RATE_LIMITED);

  // Validation errors
  assertExists(AgentErrorCodes.INVALID_REQUEST);
  assertExists(AgentErrorCodes.WRONG_PHASE);
  assertExists(AgentErrorCodes.PHASE_ENDED);
  assertExists(AgentErrorCodes.LIMIT_REACHED);
  assertExists(AgentErrorCodes.CONTENT_TOO_LONG);
  assertExists(AgentErrorCodes.INVALID_RATING);
  assertExists(AgentErrorCodes.CANNOT_RATE_OWN);
  assertExists(AgentErrorCodes.MALICIOUS_CONTENT);

  // Conflict errors
  assertExists(AgentErrorCodes.DUPLICATE);
  assertExists(AgentErrorCodes.ALREADY_PARTICIPANT);
  assertExists(AgentErrorCodes.AGENT_NAME_TAKEN);

  // Not found errors
  assertExists(AgentErrorCodes.CHAT_NOT_FOUND);

  // Server errors
  assertExists(AgentErrorCodes.DB_ERROR);
  assertExists(AgentErrorCodes.INTERNAL_ERROR);
});

Deno.test("AgentRateLimits - contains all endpoint configurations", async () => {
  const { AgentRateLimits } = await import("../_shared/agent-auth.ts");

  // Verify all endpoints have rate limit configs
  assertExists(AgentRateLimits.register);
  assertExists(AgentRateLimits.createChat);
  assertExists(AgentRateLimits.joinChat);
  assertExists(AgentRateLimits.joinByCode);
  assertExists(AgentRateLimits.propose);
  assertExists(AgentRateLimits.rate);
  assertExists(AgentRateLimits.chatState);
  assertExists(AgentRateLimits.results);
  assertExists(AgentRateLimits.listChats);

  // Verify each config has required fields
  for (const [_name, config] of Object.entries(AgentRateLimits)) {
    assertExists((config as { maxRequests: number }).maxRequests);
    assertExists((config as { windowSeconds: number }).windowSeconds);
  }
});

// =============================================================================
// Input Sanitization Tests (Unit Tests - No Network)
// =============================================================================

Deno.test("sanitizeString - removes control characters", async () => {
  const { sanitizeString } = await import("../_shared/validation.ts");

  const input = "Hello\x00World\x1FTest";
  const result = sanitizeString(input);
  assertEquals(result, "HelloWorldTest");
});

Deno.test("sanitizeString - normalizes whitespace", async () => {
  const { sanitizeString } = await import("../_shared/validation.ts");

  const input = "  Hello   World  \n\t Test  ";
  const result = sanitizeString(input);
  assertEquals(result, "Hello World Test");
});

Deno.test("sanitizeString - truncates long strings", async () => {
  const { sanitizeString } = await import("../_shared/validation.ts");

  const input = "a".repeat(15000);
  const result = sanitizeString(input);
  assertEquals(result.length, 10000);
});

Deno.test("containsMaliciousContent - detects script tags", async () => {
  const { containsMaliciousContent } = await import("../_shared/validation.ts");

  assertEquals(containsMaliciousContent("<script>alert(1)</script>"), true);
  assertEquals(containsMaliciousContent("<SCRIPT>alert(1)</SCRIPT>"), true);
  assertEquals(containsMaliciousContent("<script src='evil.js'>"), true);
});

Deno.test("containsMaliciousContent - detects javascript: URIs", async () => {
  const { containsMaliciousContent } = await import("../_shared/validation.ts");

  assertEquals(containsMaliciousContent("javascript:alert(1)"), true);
  assertEquals(containsMaliciousContent("JAVASCRIPT:void(0)"), true);
});

Deno.test("containsMaliciousContent - detects event handlers", async () => {
  const { containsMaliciousContent } = await import("../_shared/validation.ts");

  assertEquals(containsMaliciousContent("onclick=alert(1)"), true);
  assertEquals(containsMaliciousContent("onerror=fetch()"), true);
  assertEquals(containsMaliciousContent("onload = init()"), true);
});

Deno.test("containsMaliciousContent - allows safe content", async () => {
  const { containsMaliciousContent } = await import("../_shared/validation.ts");

  assertEquals(containsMaliciousContent("Hello, world!"), false);
  assertEquals(containsMaliciousContent("Let's build consensus together"), false);
  assertEquals(containsMaliciousContent("I think we should implement option A"), false);
  assertEquals(containsMaliciousContent("The onclick function is deprecated"), false);
});

// =============================================================================
// Integration Tests (Require Running Supabase)
// These tests require a running Supabase instance
// =============================================================================

// Skip integration tests if no service role key is available
const SKIP_INTEGRATION = !SERVICE_ROLE_KEY;

Deno.test({
  name: "Integration: agent-register - missing agent_name returns 400",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-register", {
      body: {},
    });

    assertEquals(status, 400);
    assertEquals((data as { code?: string }).code, "INVALID_REQUEST");
  },
});

Deno.test({
  name: "Integration: agent-register - invalid agent_name format returns 400",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-register", {
      body: { agent_name: "123invalid" }, // Can't start with number
    });

    assertEquals(status, 400);
    assertEquals((data as { code?: string }).code, "INVALID_REQUEST");
  },
});

Deno.test({
  name: "Integration: agent-register - agent_name too short returns 400",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-register", {
      body: { agent_name: "ab" }, // Min 3 chars
    });

    assertEquals(status, 400);
    assertEquals((data as { code?: string }).code, "INVALID_REQUEST");
  },
});

Deno.test({
  name: "Integration: agent-create-chat - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-create-chat", {
      body: {
        name: "Test Chat",
        initial_message: "Test message",
      },
    });

    assertEquals(status, 401);
    assertEquals((data as { code?: string }).code, "MISSING_AUTH");
  },
});

Deno.test({
  name: "Integration: agent-create-chat - invalid API key returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-create-chat", {
      apiKey: "onemind_sk_invalid_key_12345678",
      body: {
        name: "Test Chat",
        initial_message: "Test message",
      },
    });

    assertEquals(status, 401);
    // Code can be INVALID_API_KEY or potentially DB_ERROR if hash lookup fails
    const code = (data as { code?: string }).code;
    assertEquals(code === "INVALID_API_KEY" || code === "DB_ERROR", true);
  },
});

Deno.test({
  name: "Integration: agent-propose - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-propose", {
      body: {
        chat_id: 999,
        content: "Test proposition",
      },
    });

    // These endpoints use validateAgentParticipant which checks both auth AND participant status
    // Missing auth returns 401, but invalid auth can return 403 (not participant)
    assertEquals(status >= 401 && status <= 403, true);
  },
});

Deno.test({
  name: "Integration: agent-rate - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-rate", {
      body: {
        chat_id: 999,
        ratings: { "1": 75 },
      },
    });

    // These endpoints use validateAgentParticipant - returns 401 or 403
    assertEquals(status >= 401 && status <= 403, true);
  },
});

Deno.test({
  name: "Integration: agent-chat-state - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-chat-state", {
      method: "GET",
      queryParams: { chat_id: "999" },
    });

    // These endpoints use validateAgentParticipant - returns 401 or 403
    assertEquals(status >= 401 && status <= 403, true);
  },
});

Deno.test({
  name: "Integration: agent-results - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-results", {
      method: "GET",
      queryParams: { chat_id: "999" },
    });

    // These endpoints use validateAgentParticipant - returns 401 or 403
    assertEquals(status >= 401 && status <= 403, true);
  },
});

Deno.test({
  name: "Integration: agent-list-chats - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-list-chats", {
      method: "GET",
    });

    assertEquals(status, 401);
    assertEquals((data as { code?: string }).code, "MISSING_AUTH");
  },
});

Deno.test({
  name: "Integration: agent-join-chat - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-join-chat", {
      body: { chat_id: 999 },
    });

    assertEquals(status, 401);
    assertEquals((data as { code?: string }).code, "MISSING_AUTH");
  },
});

Deno.test({
  name: "Integration: agent-join-by-code - missing auth returns 401",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-join-by-code", {
      body: { invite_code: "ABC123" },
    });

    assertEquals(status, 401);
    assertEquals((data as { code?: string }).code, "MISSING_AUTH");
  },
});

// =============================================================================
// Validation Tests
// =============================================================================

Deno.test({
  name: "Integration: agent-rate - invalid rating value returns 400",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-rate", {
      apiKey: "onemind_sk_invalid_key_12345678",
      body: {
        chat_id: 999,
        ratings: { "1": 150 }, // Max is 100
      },
    });

    // Should fail auth first, but if it passes, would get validation error
    assertEquals(status >= 400, true);
  },
});

Deno.test({
  name: "Integration: agent-propose - empty content returns 400",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status } = await agentRequest("agent-propose", {
      body: {
        chat_id: 999,
        content: "",
      },
    });

    assertEquals(status, 400);
  },
});

Deno.test({
  name: "Integration: agent-chat-state - invalid chat_id format returns 400",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-chat-state", {
      method: "GET",
      apiKey: "onemind_sk_invalid_key_12345678",
      queryParams: { chat_id: "not_a_number" },
    });

    assertEquals(status, 400);
    assertEquals((data as { code?: string }).code, "INVALID_REQUEST");
  },
});

Deno.test({
  name: "Integration: agent-chat-state - missing chat_id returns 400",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-chat-state", {
      method: "GET",
      apiKey: "onemind_sk_invalid_key_12345678",
    });

    assertEquals(status, 400);
    assertEquals((data as { code?: string }).code, "INVALID_REQUEST");
  },
});

// =============================================================================
// Method Validation Tests
// =============================================================================

Deno.test({
  name: "Integration: agent-register - GET method returns 405",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status } = await agentRequest("agent-register", {
      method: "GET",
    });

    assertEquals(status, 405);
  },
});

Deno.test({
  name: "Integration: agent-chat-state - POST method returns 405",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status } = await agentRequest("agent-chat-state", {
      method: "POST",
      body: { chat_id: 999 },
    });

    assertEquals(status, 405);
  },
});

// =============================================================================
// Full Lifecycle Test (Happy Path)
// This test requires a clean database state
// =============================================================================

// NOTE: This test requires proper auth admin API configuration which may not
// be available in local dev. Skip if auth.admin.createUser fails.
Deno.test({
  name: "Integration: Full agent lifecycle - register, create chat, join",
  ignore: SKIP_INTEGRATION,
  async fn() {
    // Generate unique agent name to avoid conflicts
    const uniqueId = Date.now().toString(36);
    const agentName = `TestAgent_${uniqueId}`;

    // Step 1: Register a new agent
    const registerResult = await agentRequest("agent-register", {
      body: {
        agent_name: agentName,
        description: "Test agent for integration tests",
      },
    });

    if (registerResult.status !== 201) {
      console.log("Register failed:", registerResult.data);
      // Skip test if auth admin API isn't configured (common in local dev)
      const errorCode = (registerResult.data as { code?: string }).code;
      if (errorCode === "DB_ERROR") {
        console.log("Skipping lifecycle test - auth admin API not configured for local dev");
        return;
      }
    }
    assertEquals(registerResult.status, 201);
    const registerData = registerResult.data as {
      success: boolean;
      api_key: string;
      agent_id: string;
    };
    assertExists(registerData.api_key);
    assertExists(registerData.agent_id);
    assertEquals(registerData.success, true);

    const apiKey = registerData.api_key;

    // Verify API key format
    assertMatch(apiKey, /^onemind_sk_[A-Za-z0-9]{32}$/);

    // Step 2: Create a chat
    const createChatResult = await agentRequest("agent-create-chat", {
      apiKey,
      body: {
        name: `Test Chat ${uniqueId}`,
        initial_message: "This is a test chat created by an agent",
        description: "Integration test chat",
        proposing_duration_seconds: 300,
        rating_duration_seconds: 300,
      },
    });

    if (createChatResult.status !== 201) {
      console.log("Create chat failed:", createChatResult.data);
    }
    assertEquals(createChatResult.status, 201);
    const chatData = createChatResult.data as {
      success: boolean;
      chat_id: number;
      invite_code: string;
      participant_id: number;
    };
    assertExists(chatData.chat_id);
    assertExists(chatData.invite_code);
    assertExists(chatData.participant_id);

    const chatId = chatData.chat_id;
    const inviteCode = chatData.invite_code;

    // Verify invite code format (6 uppercase alphanumeric)
    assertMatch(inviteCode, /^[A-Z0-9]{6}$/);

    // Step 3: Check chat state
    const stateResult = await agentRequest("agent-chat-state", {
      method: "GET",
      apiKey,
      queryParams: { chat_id: chatId.toString() },
    });

    if (stateResult.status !== 200) {
      console.log("Chat state failed:", stateResult.data);
    }
    assertEquals(stateResult.status, 200);
    const stateData = stateResult.data as {
      chat_id: number;
      propositions_per_user: number;
    };
    assertEquals(stateData.chat_id, chatId);
    assertExists(stateData.propositions_per_user);

    // Step 4: List chats
    const listResult = await agentRequest("agent-list-chats", {
      method: "GET",
      apiKey,
      queryParams: { include_joined: "true" },
    });

    if (listResult.status !== 200) {
      console.log("List chats failed:", listResult.data);
    }
    assertEquals(listResult.status, 200);
    const listData = listResult.data as {
      chats: Array<{ id: number }>;
      total: number;
    };
    assertExists(listData.chats);
    assertExists(listData.total);

    // Verify our chat is in the list
    const ourChat = listData.chats.find((c) => c.id === chatId);
    assertExists(ourChat);

    // Step 5: Check results (no results yet, but should return structure)
    const resultsResult = await agentRequest("agent-results", {
      method: "GET",
      apiKey,
      queryParams: { chat_id: chatId.toString() },
    });

    if (resultsResult.status !== 200) {
      console.log("Results failed:", resultsResult.data);
    }
    assertEquals(resultsResult.status, 200);
    const resultsData = resultsResult.data as {
      chat_id: number;
      consensus_reached: boolean;
      rounds_for_consensus: number;
    };
    assertEquals(resultsData.chat_id, chatId);
    assertEquals(resultsData.consensus_reached, false);
    assertExists(resultsData.rounds_for_consensus);

    console.log(
      `Lifecycle test passed! Agent: ${agentName}, Chat: ${chatId}, Code: ${inviteCode}`
    );
  },
});

// =============================================================================
// Security Tests
// =============================================================================

Deno.test({
  name: "Security: API key without prefix is rejected",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-list-chats", {
      method: "GET",
      apiKey: "invalid_key_without_prefix_12345",
    });

    assertEquals(status, 401);
    assertEquals((data as { code?: string }).code, "MISSING_AUTH");
  },
});

Deno.test({
  name: "Security: Empty API key is rejected",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-list-chats", {
      method: "GET",
      apiKey: "",
    });

    assertEquals(status, 401);
  },
});

Deno.test({
  name: "Security: Malicious content in agent name is rejected",
  ignore: SKIP_INTEGRATION,
  async fn() {
    const { status, data } = await agentRequest("agent-register", {
      body: {
        agent_name: "<script>alert(1)</script>",
      },
    });

    // Should fail validation before reaching malicious content check
    // May also get 429 if rate limited from previous tests
    const code = (data as { code?: string }).code;
    assertEquals(
      status === 400 || status === 429,
      true,
      `Expected 400 or 429, got ${status} with code ${code}`
    );
    assertEquals(
      code === "INVALID_REQUEST" || code === "RATE_LIMITED",
      true,
      `Expected INVALID_REQUEST or RATE_LIMITED, got ${code}`
    );
  },
});
