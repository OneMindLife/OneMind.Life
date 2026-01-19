// Tests for process-timers Edge Function
// Run with: deno test --allow-all supabase/functions/tests/process-timers-test.ts
//
// Prerequisites:
// 1. supabase start (local Supabase running)
// 2. supabase functions serve process-timers (function running)

import {
  assertEquals,
  assertExists,
  assert,
} from "jsr:@std/assert@1";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Load environment variables
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// Use service role key for setup, anon key for function invocation
let adminClient: SupabaseClient;
let anonClient: SupabaseClient;

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

  anonClient = createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function cleanupTestData(chatName: string) {
  // Clean up in reverse order of dependencies
  const { data: chat } = await adminClient
    .from("chats")
    .select("id")
    .eq("name", chatName)
    .single();

  if (chat) {
    // Get cycles for this chat
    const { data: cycles } = await adminClient
      .from("cycles")
      .select("id")
      .eq("chat_id", chat.id);

    if (cycles) {
      for (const cycle of cycles) {
        // Get rounds for this cycle
        const { data: rounds } = await adminClient
          .from("rounds")
          .select("id")
          .eq("cycle_id", cycle.id);

        if (rounds) {
          for (const round of rounds) {
            // Get propositions for this round
            const { data: props } = await adminClient
              .from("propositions")
              .select("id")
              .eq("round_id", round.id);

            if (props) {
              // Delete ratings
              await adminClient
                .from("ratings")
                .delete()
                .in("proposition_id", props.map((p) => p.id));

              // Delete proposition_ratings
              await adminClient
                .from("proposition_ratings")
                .delete()
                .in("proposition_id", props.map((p) => p.id));
            }

            // Delete propositions
            await adminClient
              .from("propositions")
              .delete()
              .eq("round_id", round.id);
          }

          // Delete rounds
          await adminClient
            .from("rounds")
            .delete()
            .eq("cycle_id", cycle.id);
        }
      }

      // Delete cycles
      await adminClient.from("cycles").delete().eq("chat_id", chat.id);
    }

    // Delete participants
    await adminClient.from("participants").delete().eq("chat_id", chat.id);

    // Delete chat
    await adminClient.from("chats").delete().eq("id", chat.id);
  }
}

async function invokeProcessTimers() {
  const response = await fetch(
    `${supabaseUrl}/functions/v1/process-timers`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${supabaseAnonKey}`,
        "Content-Type": "application/json",
      },
    }
  );
  return response.json();
}

async function createTestChat(
  name: string,
  options: {
    proposingDuration?: number;
    ratingDuration?: number;
    proposingMinimum?: number;
    ratingMinimum?: number;
    proposingThresholdPercent?: number | null;
    proposingThresholdCount?: number | null;
    ratingThresholdPercent?: number | null;
    ratingThresholdCount?: number | null;
    startMode?: string;
    autoStartCount?: number;
  } = {}
) {
  const { data: chat, error } = await adminClient
    .from("chats")
    .insert({
      name,
      initial_message: "Test topic",
      creator_session_token: crypto.randomUUID(),
      proposing_duration_seconds: options.proposingDuration ?? 300,
      rating_duration_seconds: options.ratingDuration ?? 300,
      proposing_minimum: options.proposingMinimum ?? 2,
      rating_minimum: options.ratingMinimum ?? 2,
      proposing_threshold_percent: options.proposingThresholdPercent ?? null,
      proposing_threshold_count: options.proposingThresholdCount ?? null,
      rating_threshold_percent: options.ratingThresholdPercent ?? null,
      rating_threshold_count: options.ratingThresholdCount ?? null,
      start_mode: options.startMode ?? "manual",
      auto_start_participant_count: options.autoStartCount ?? 5,
    })
    .select()
    .single();

  if (error) throw error;
  return chat;
}

async function createTestCycleAndRound(
  chatId: number,
  phase: string,
  phaseEndsAt: Date | null
) {
  // Create cycle
  const { data: cycle, error: cycleError } = await adminClient
    .from("cycles")
    .insert({ chat_id: chatId })
    .select()
    .single();

  if (cycleError) throw cycleError;

  // Create round
  const { data: round, error: roundError } = await adminClient
    .from("rounds")
    .insert({
      cycle_id: cycle.id,
      custom_id: 1,
      phase,
      phase_started_at: new Date().toISOString(),
      phase_ends_at: phaseEndsAt?.toISOString() ?? null,
    })
    .select()
    .single();

  if (roundError) throw roundError;

  return { cycle, round };
}

async function createTestParticipant(chatId: number, name: string) {
  const { data, error } = await adminClient
    .from("participants")
    .insert({
      chat_id: chatId,
      session_token: crypto.randomUUID(),
      display_name: name,
      is_host: false,
      status: "active",
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

async function createTestProposition(
  roundId: number,
  participantId: number,
  content: string
) {
  const { data, error } = await adminClient
    .from("propositions")
    .insert({
      round_id: roundId,
      participant_id: participantId,
      content,
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

async function createTestRating(
  propositionId: number,
  participantId: number,
  rating: number
) {
  const { data, error } = await adminClient
    .from("ratings")
    .insert({
      proposition_id: propositionId,
      participant_id: participantId,
      rating,
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// =============================================================================
// TESTS: TIMER EXPIRATION
// =============================================================================

Deno.test({
  name: "Timer: Expired proposing phase with minimum met advances to rating",
  async fn() {
    await setupTestData();
    const chatName = "Test Timer Advance " + Date.now();

    try {
      // Create chat with low minimum
      const chat = await createTestChat(chatName, {
        proposingDuration: 60,
        proposingMinimum: 2,
      });

      // Create cycle and round with EXPIRED timer
      const expiredTime = new Date(Date.now() - 60000); // 1 minute ago
      const { round } = await createTestCycleAndRound(
        chat.id,
        "proposing",
        expiredTime
      );

      // Create participants and propositions to meet minimum
      const p1 = await createTestParticipant(chat.id, "User 1");
      const p2 = await createTestParticipant(chat.id, "User 2");
      await createTestProposition(round.id, p1.id, "Prop 1");
      await createTestProposition(round.id, p2.id, "Prop 2");

      // Invoke the timer processor
      const result = await invokeProcessTimers();

      // Verify phase advanced
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("phase")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.phase, "rating");
      assert(result.phases_advanced >= 1);
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Timer: Expired proposing phase with minimum NOT met extends timer",
  async fn() {
    await setupTestData();
    const chatName = "Test Timer Extend " + Date.now();

    try {
      // Create chat requiring 3 propositions
      const chat = await createTestChat(chatName, {
        proposingDuration: 300, // 5 minutes
        proposingMinimum: 3,
      });

      // Create cycle and round with EXPIRED timer
      const expiredTime = new Date(Date.now() - 60000);
      const { round } = await createTestCycleAndRound(
        chat.id,
        "proposing",
        expiredTime
      );

      // Only create 1 proposition (below minimum)
      const p1 = await createTestParticipant(chat.id, "User 1");
      await createTestProposition(round.id, p1.id, "Only Prop");

      // Invoke the timer processor
      const result = await invokeProcessTimers();

      // Verify timer extended (still in proposing, new phase_ends_at)
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("phase, phase_ends_at")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.phase, "proposing");
      assert(new Date(updatedRound?.phase_ends_at) > new Date());
      assert(result.timers_extended >= 1);
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Timer: Expired rating phase calculates winner and completes",
  async fn() {
    await setupTestData();
    const chatName = "Test Rating Complete " + Date.now();

    try {
      const chat = await createTestChat(chatName, {
        ratingDuration: 60,
        ratingMinimum: 1,
      });

      const expiredTime = new Date(Date.now() - 60000);
      const { round } = await createTestCycleAndRound(
        chat.id,
        "rating",
        expiredTime
      );

      // Create participants, propositions, and ratings
      const p1 = await createTestParticipant(chat.id, "User 1");
      const p2 = await createTestParticipant(chat.id, "User 2");

      const prop1 = await createTestProposition(round.id, p1.id, "High Prop");
      const prop2 = await createTestProposition(round.id, p2.id, "Low Prop");

      // Rate: prop1 = 90, prop2 = 40
      await createTestRating(prop1.id, p1.id, 90);
      await createTestRating(prop1.id, p2.id, 90);
      await createTestRating(prop2.id, p1.id, 40);
      await createTestRating(prop2.id, p2.id, 40);

      // Invoke timer processor
      const result = await invokeProcessTimers();

      // Verify winner set
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("winning_proposition_id, completed_at")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.winning_proposition_id, prop1.id);
      assertExists(updatedRound?.completed_at);
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: AUTO-ADVANCE THRESHOLDS
// =============================================================================

Deno.test({
  name: "Auto-advance: Proposing advances early when threshold met",
  async fn() {
    await setupTestData();
    const chatName = "Test Auto Advance " + Date.now();

    try {
      // Create chat with 50% threshold, count of 2
      const chat = await createTestChat(chatName, {
        proposingDuration: 3600, // 1 hour (not expired)
        proposingMinimum: 2,
        proposingThresholdPercent: 50,
        proposingThresholdCount: 2,
      });

      // Timer NOT expired yet
      const futureTime = new Date(Date.now() + 3600000);
      const { round } = await createTestCycleAndRound(
        chat.id,
        "proposing",
        futureTime
      );

      // Create 4 participants
      const p1 = await createTestParticipant(chat.id, "User 1");
      const p2 = await createTestParticipant(chat.id, "User 2");
      const p3 = await createTestParticipant(chat.id, "User 3");
      const p4 = await createTestParticipant(chat.id, "User 4");

      // 2 out of 4 propose (50% + meets count of 2)
      await createTestProposition(round.id, p1.id, "Prop 1");
      await createTestProposition(round.id, p2.id, "Prop 2");

      // Invoke timer processor
      const result = await invokeProcessTimers();

      // Verify early advance
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("phase")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.phase, "rating");
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Auto-advance: Does NOT advance if only percent met, not count",
  async fn() {
    await setupTestData();
    const chatName = "Test No Early Advance " + Date.now();

    try {
      // Create chat with 50% threshold BUT count of 5
      const chat = await createTestChat(chatName, {
        proposingDuration: 3600,
        proposingMinimum: 2,
        proposingThresholdPercent: 50,
        proposingThresholdCount: 5, // Requires 5 proposers minimum
      });

      const futureTime = new Date(Date.now() + 3600000);
      const { round } = await createTestCycleAndRound(
        chat.id,
        "proposing",
        futureTime
      );

      // Create 4 participants
      const p1 = await createTestParticipant(chat.id, "User 1");
      const p2 = await createTestParticipant(chat.id, "User 2");
      const p3 = await createTestParticipant(chat.id, "User 3");
      const p4 = await createTestParticipant(chat.id, "User 4");

      // 2 out of 4 propose (50% met, but count of 5 NOT met)
      await createTestProposition(round.id, p1.id, "Prop 1");
      await createTestProposition(round.id, p2.id, "Prop 2");

      // Invoke timer processor
      await invokeProcessTimers();

      // Verify still in proposing
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("phase")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.phase, "proposing");
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: AUTO-START
// =============================================================================

Deno.test({
  name: "Auto-start: Waiting phase starts when participant count reached",
  async fn() {
    await setupTestData();
    const chatName = "Test Auto Start " + Date.now();

    try {
      // Create chat with auto-start at 3 participants
      const chat = await createTestChat(chatName, {
        startMode: "auto",
        autoStartCount: 3,
        proposingDuration: 300,
      });

      // Create cycle and round in WAITING phase
      const { round } = await createTestCycleAndRound(
        chat.id,
        "waiting",
        null
      );

      // Create 3 participants (meets threshold)
      await createTestParticipant(chat.id, "User 1");
      await createTestParticipant(chat.id, "User 2");
      await createTestParticipant(chat.id, "User 3");

      // Invoke timer processor
      const result = await invokeProcessTimers();

      // Verify phase changed to proposing
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("phase, phase_started_at, phase_ends_at")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.phase, "proposing");
      assertExists(updatedRound?.phase_started_at);
      assertExists(updatedRound?.phase_ends_at);
      assert(result.auto_started >= 1);
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Auto-start: Waiting phase does NOT start if count not reached",
  async fn() {
    await setupTestData();
    const chatName = "Test No Auto Start " + Date.now();

    try {
      const chat = await createTestChat(chatName, {
        startMode: "auto",
        autoStartCount: 5, // Need 5
        proposingDuration: 300,
      });

      const { round } = await createTestCycleAndRound(
        chat.id,
        "waiting",
        null
      );

      // Only 2 participants (below threshold)
      await createTestParticipant(chat.id, "User 1");
      await createTestParticipant(chat.id, "User 2");

      // Invoke timer processor
      await invokeProcessTimers();

      // Verify still in waiting
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("phase")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.phase, "waiting");
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Auto-start: Manual start mode does not auto-start",
  async fn() {
    await setupTestData();
    const chatName = "Test Manual No Auto " + Date.now();

    try {
      const chat = await createTestChat(chatName, {
        startMode: "manual", // Manual mode
        autoStartCount: 2,
        proposingDuration: 300,
      });

      const { round } = await createTestCycleAndRound(
        chat.id,
        "waiting",
        null
      );

      // Create 5 participants (more than auto-start count)
      await createTestParticipant(chat.id, "User 1");
      await createTestParticipant(chat.id, "User 2");
      await createTestParticipant(chat.id, "User 3");
      await createTestParticipant(chat.id, "User 4");
      await createTestParticipant(chat.id, "User 5");

      // Invoke timer processor
      await invokeProcessTimers();

      // Verify still in waiting (manual mode ignores auto-start)
      const { data: updatedRound } = await adminClient
        .from("rounds")
        .select("phase")
        .eq("id", round.id)
        .single();

      assertEquals(updatedRound?.phase, "waiting");
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

// =============================================================================
// TESTS: EDGE CASES
// =============================================================================

Deno.test({
  name: "Edge case: No rounds to process returns empty result",
  async fn() {
    await setupTestData();

    // Just invoke with no test data
    const result = await invokeProcessTimers();

    assertEquals(result.rounds_checked, 0);
    assertEquals(result.phases_advanced, 0);
    assertEquals(result.timers_extended, 0);
    assertEquals(result.auto_started, 0);
    assertEquals(result.errors.length, 0);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Edge case: Completed round is not processed",
  async fn() {
    await setupTestData();
    const chatName = "Test Completed Skip " + Date.now();

    try {
      const chat = await createTestChat(chatName);

      // Create cycle
      const { data: cycle } = await adminClient
        .from("cycles")
        .insert({ chat_id: chat.id })
        .select()
        .single();

      // Create COMPLETED round with expired timer
      const expiredTime = new Date(Date.now() - 60000);
      await adminClient.from("rounds").insert({
        cycle_id: cycle!.id,
        custom_id: 1,
        phase: "proposing",
        phase_ends_at: expiredTime.toISOString(),
        completed_at: new Date().toISOString(), // Already completed
      });

      // Invoke timer processor
      const result = await invokeProcessTimers();

      // Should not process completed round
      assertEquals(result.rounds_checked, 0);
    } finally {
      await cleanupTestData(chatName);
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});
