/**
 * Tests for send-email Edge Function
 *
 * Run with: deno test --allow-net --allow-env supabase/functions/tests/send-email.test.ts
 *
 * Note: These are unit tests for the email template logic.
 * Integration tests require a running Edge Function server.
 */

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { inviteEmail, welcomeEmail, paymentReceiptEmail } from "../_shared/email.ts";

Deno.test("inviteEmail - generates correct URL with inviteToken", () => {
  const result = inviteEmail({
    chatName: "Test Chat",
    inviteToken: "abc-123-token",
    inviterName: "Alice",
  });

  assertEquals(result.subject, 'You\'re invited to "Test Chat" on OneMind');
  assertStringIncludes(result.html, "/join/invite?token=abc-123-token");
  assertStringIncludes(result.text, "/join/invite?token=abc-123-token");
  assertStringIncludes(result.html, "Alice");
  assertStringIncludes(result.html, "Test Chat");
});

Deno.test("inviteEmail - generates correct URL with inviteCode (fallback)", () => {
  const result = inviteEmail({
    chatName: "Code Chat",
    inviteCode: "ABCDEF",
    inviterName: "Bob",
  });

  assertEquals(result.subject, 'You\'re invited to "Code Chat" on OneMind');
  assertStringIncludes(result.html, "/join/ABCDEF");
  assertStringIncludes(result.text, "/join/ABCDEF");
  assertStringIncludes(result.html, "Or use invite code:");
  assertStringIncludes(result.html, "ABCDEF");
});

Deno.test("inviteEmail - prefers inviteToken over inviteCode", () => {
  const result = inviteEmail({
    chatName: "Both Chat",
    inviteToken: "token-preferred",
    inviteCode: "XYZZYX",
    inviterName: "Charlie",
  });

  // Should use token URL
  assertStringIncludes(result.html, "/join/invite?token=token-preferred");
  // Should also show invite code as alternative
  assertStringIncludes(result.html, "Or use invite code:");
  assertStringIncludes(result.html, "XYZZYX");
});

Deno.test("inviteEmail - handles missing inviterName", () => {
  const result = inviteEmail({
    chatName: "Anonymous Chat",
    inviteToken: "anon-token",
  });

  assertStringIncludes(result.html, "Someone");
  assertStringIncludes(result.text, "Someone");
});

Deno.test("inviteEmail - includes optional message", () => {
  const result = inviteEmail({
    chatName: "Message Chat",
    inviteToken: "msg-token",
    message: "Please join our discussion!",
  });

  assertStringIncludes(result.html, "Please join our discussion!");
  assertStringIncludes(result.text, "Please join our discussion!");
});

Deno.test("inviteEmail - no invite code section when only token provided", () => {
  const result = inviteEmail({
    chatName: "Token Only",
    inviteToken: "only-token",
  });

  // Should NOT include "Or use invite code" section
  assertEquals(result.html.includes("Or use invite code:"), false);
});

Deno.test("welcomeEmail - generates correct content", () => {
  const result = welcomeEmail("TestUser");

  assertEquals(result.subject, "Welcome to OneMind!");
  assertStringIncludes(result.html, "TestUser");
  assertStringIncludes(result.text, "TestUser");
  assertStringIncludes(result.html, "Get Started");
});

Deno.test("welcomeEmail - handles missing userName", () => {
  const result = welcomeEmail();

  assertStringIncludes(result.html, "there");
  assertStringIncludes(result.text, "there");
});

Deno.test("paymentReceiptEmail - generates correct content", () => {
  const result = paymentReceiptEmail({
    userName: "PayUser",
    credits: 1000,
    amount: 10.00,
    transactionId: "txn_123",
    date: new Date("2026-01-14"),
  });

  assertStringIncludes(result.subject, "1000 OneMind Credits");
  assertStringIncludes(result.html, "PayUser");
  assertStringIncludes(result.html, "1000 credits");
  assertStringIncludes(result.html, "$10.00");
  assertStringIncludes(result.html, "txn_123");
});
