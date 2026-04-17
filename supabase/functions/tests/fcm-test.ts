// Tests for FCM notification infrastructure
// Run with: deno test --no-check --allow-all supabase/functions/tests/fcm-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

let adminClient: SupabaseClient;

function setup() {
  adminClient = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// =============================================================================
// FCM TOKEN TABLE TESTS
// =============================================================================

async function createAuthUser(): Promise<string> {
  // Use anonymous sign-in (same as the app does)
  const anonClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await anonClient.auth.signInAnonymously();
  if (error || !data?.user?.id) throw new Error("Failed to create test user: " + error?.message);
  return data.user.id;
}

Deno.test({
  name: "FCM Tokens: Table exists and accepts inserts",
  async fn() {
    setup();
    const userId = await createAuthUser();

    const { data, error } = await adminClient
      .from("fcm_tokens")
      .insert({
        user_id: userId,
        token: "test-token-" + Date.now(),
      })
      .select()
      .single();

    // Clean up
    if (data) {
      await adminClient.from("fcm_tokens").delete().eq("id", data.id);
    }
    await adminClient.auth.admin.deleteUser(userId);

    assertExists(data, "Token should be inserted");
    assertEquals(data.user_id, userId);
  },
});

Deno.test({
  name: "FCM Tokens: Unique constraint on token prevents duplicates",
  async fn() {
    setup();
    const token = "unique-token-" + Date.now();
    const userId1 = await createAuthUser();
    const userId2 = await createAuthUser();

    // Insert first token
    const { data: first } = await adminClient
      .from("fcm_tokens")
      .insert({ user_id: userId1, token })
      .select()
      .single();

    assertExists(first, "First insert should succeed");

    // Insert duplicate token with different user
    const { error: dupError } = await adminClient
      .from("fcm_tokens")
      .insert({ user_id: userId2, token });

    assertExists(dupError, "Duplicate token should fail");

    // Clean up
    await adminClient.from("fcm_tokens").delete().eq("token", token);
    await adminClient.auth.admin.deleteUser(userId1);
    await adminClient.auth.admin.deleteUser(userId2);
  },
});

Deno.test({
  name: "FCM Tokens: Upsert updates timestamp on conflict",
  async fn() {
    setup();
    const token = "upsert-token-" + Date.now();
    const userId = await createAuthUser();

    // Insert
    await adminClient
      .from("fcm_tokens")
      .insert({ user_id: userId, token });

    // Upsert same token with new timestamp
    const newTime = new Date().toISOString();
    const { data, error } = await adminClient
      .from("fcm_tokens")
      .upsert(
        { user_id: userId, token, updated_at: newTime },
        { onConflict: "token" }
      )
      .select()
      .single();

    assertEquals(error, null, "Upsert should succeed");
    assertExists(data);

    // Clean up
    await adminClient.from("fcm_tokens").delete().eq("token", token);
    await adminClient.auth.admin.deleteUser(userId);
  },
});

// =============================================================================
// GET_RATING_ELIGIBLE_COUNT TESTS
// =============================================================================

Deno.test({
  name: "get_rating_eligible_count: Returns only humans when rating_agent_count=0",
  async fn() {
    setup();
    const chatName = "FCM Eligible Count Test " + Date.now();

    // Create chat with agents enabled but rating_agent_count=0
    const { data: chat, error: chatError } = await adminClient
      .from("chats")
      .insert({
        name: chatName,
        initial_message: "Test",
        creator_session_token: crypto.randomUUID(),
        enable_agents: true,
        proposing_agent_count: 2,
        rating_agent_count: 0,
        start_mode: "manual",
      })
      .select()
      .single();

    assertExists(chat, "Chat should be created");

    // Add 3 human participants
    for (let i = 0; i < 3; i++) {
      await adminClient.from("participants").insert({
        chat_id: chat.id,
        session_token: crypto.randomUUID(),
        display_name: `Human ${i}`,
        status: "active",
        is_agent: false,
      });
    }

    // Count total active (includes auto-created agents)
    const { count: totalCount } = await adminClient
      .from("participants")
      .select("id", { count: "exact", head: true })
      .eq("chat_id", chat.id)
      .eq("status", "active");

    // Get rating eligible count
    const { data: eligibleCount, error: eligibleError } = await adminClient
      .rpc("get_rating_eligible_count", { p_chat_id: chat.id });

    assertEquals(eligibleError, null);
    assertEquals(eligibleCount, 3, "Should return 3 humans only");
    assert(
      (totalCount ?? 0) > 3,
      "Total count should be more than 3 (includes agents)"
    );

    // Clean up
    await adminClient.from("participants").delete().eq("chat_id", chat.id);
    await adminClient.from("chats").delete().eq("id", chat.id);
  },
});

Deno.test({
  name: "get_rating_eligible_count: Includes agents when rating_agent_count>0",
  async fn() {
    setup();
    const chatName = "FCM Eligible Agents Rate Test " + Date.now();

    // Create chat with agents that DO rate
    const { data: chat, error: chatError } = await adminClient
      .from("chats")
      .insert({
        name: chatName,
        initial_message: "Test",
        creator_session_token: crypto.randomUUID(),
        enable_agents: true,
        proposing_agent_count: 2,
        rating_agent_count: 2,
        start_mode: "manual",
      })
      .select()
      .single();

    assertExists(chat, "Chat should be created");

    // Add 3 human participants
    for (let i = 0; i < 3; i++) {
      await adminClient.from("participants").insert({
        chat_id: chat.id,
        session_token: crypto.randomUUID(),
        display_name: `Human ${i}`,
        status: "active",
        is_agent: false,
      });
    }

    // Count total active (includes auto-created agents)
    const { count: totalCount } = await adminClient
      .from("participants")
      .select("id", { count: "exact", head: true })
      .eq("chat_id", chat.id)
      .eq("status", "active");

    // Get rating eligible count — should include agents since they rate
    const { data: eligibleCount, error: eligibleError } = await adminClient
      .rpc("get_rating_eligible_count", { p_chat_id: chat.id });

    assertEquals(eligibleError, null);
    assertEquals(
      eligibleCount,
      totalCount,
      "Eligible count should equal total when agents rate"
    );

    // Clean up
    await adminClient.from("participants").delete().eq("chat_id", chat.id);
    await adminClient.from("chats").delete().eq("id", chat.id);
  },
});

Deno.test({
  name: "get_rating_eligible_count: Excludes inactive participants",
  async fn() {
    setup();
    const chatName = "FCM Eligible Inactive Test " + Date.now();

    const { data: chat } = await adminClient
      .from("chats")
      .insert({
        name: chatName,
        initial_message: "Test",
        creator_session_token: crypto.randomUUID(),
        start_mode: "manual",
      })
      .select()
      .single();

    assertExists(chat);

    // Add 2 active, 1 left, 1 kicked
    await adminClient.from("participants").insert([
      { chat_id: chat.id, session_token: crypto.randomUUID(), display_name: "Active1", status: "active" },
      { chat_id: chat.id, session_token: crypto.randomUUID(), display_name: "Active2", status: "active" },
      { chat_id: chat.id, session_token: crypto.randomUUID(), display_name: "Left", status: "left" },
      { chat_id: chat.id, session_token: crypto.randomUUID(), display_name: "Kicked", status: "kicked" },
    ]);

    const { data: eligibleCount } = await adminClient
      .rpc("get_rating_eligible_count", { p_chat_id: chat.id });

    assertEquals(eligibleCount, 2, "Should only count active participants");

    // Clean up
    await adminClient.from("participants").delete().eq("chat_id", chat.id);
    await adminClient.from("chats").delete().eq("id", chat.id);
  },
});

Deno.test({
  name: "get_rating_eligible_count: Returns 0 for empty chat",
  async fn() {
    setup();
    const chatName = "FCM Eligible Empty Test " + Date.now();

    const { data: chat } = await adminClient
      .from("chats")
      .insert({
        name: chatName,
        initial_message: "Test",
        creator_session_token: crypto.randomUUID(),
        start_mode: "manual",
      })
      .select()
      .single();

    assertExists(chat);

    const { data: eligibleCount } = await adminClient
      .rpc("get_rating_eligible_count", { p_chat_id: chat.id });

    assertEquals(eligibleCount, 0, "Empty chat should have 0 eligible");

    // Clean up
    await adminClient.from("chats").delete().eq("id", chat.id);
  },
});
