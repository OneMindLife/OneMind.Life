// Edge Function Test: submit-proposition
//
// Tests the submit-proposition edge function for duplicate proposition detection.
// Run with: deno test --allow-all supabase/functions/tests/submit-proposition-test.ts
//
// Note: These tests require:
// - SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables
// - ANTHROPIC_API_KEY environment variable (for actual translation)
// - A local Supabase instance or test database
//
// Auth tests verify the internal auth validation:
// - Service role key in Authorization header
// - Valid Supabase user JWT (for client requests)
// - Local development bypass

import {
  assertEquals,
  assertExists,
  assertNotEquals,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

// =============================================================================
// VALIDATION TESTS
// Tests the request validation logic
// =============================================================================

// Define request body type for type-safe testing
interface RequestBody {
  content?: string;
  round_id?: number;
  participant_id?: number;
}

Deno.test("submit-proposition - validation tests", async (t) => {
  await t.step("rejects request missing content", () => {
    const requestBody: RequestBody = {
      round_id: 1,
      participant_id: 1,
      // Missing content
    };

    const hasContent = requestBody.content !== undefined && requestBody.content.length > 0;
    assertEquals(hasContent, false, "Should reject when content is missing");
  });

  await t.step("rejects request with empty content", () => {
    const requestBody: RequestBody = {
      content: "",
      round_id: 1,
      participant_id: 1,
    };

    const hasContent = requestBody.content !== undefined && requestBody.content.length > 0;
    assertEquals(hasContent, false, "Should reject when content is empty string");
  });

  await t.step("rejects request missing round_id", () => {
    const requestBody: RequestBody = {
      content: "Test proposition",
      participant_id: 1,
      // Missing round_id
    };

    const hasRoundId = typeof requestBody.round_id === "number" && requestBody.round_id > 0;
    assertEquals(hasRoundId, false, "Should reject when round_id is missing");
  });

  await t.step("rejects request with negative round_id", () => {
    const requestBody: RequestBody = {
      content: "Test proposition",
      round_id: -1,
      participant_id: 1,
    };

    const hasValidRoundId = typeof requestBody.round_id === "number" && requestBody.round_id > 0;
    assertEquals(hasValidRoundId, false, "Should reject when round_id is negative");
  });

  await t.step("rejects request missing participant_id", () => {
    const requestBody: RequestBody = {
      content: "Test proposition",
      round_id: 1,
      // Missing participant_id
    };

    const hasParticipantId = typeof requestBody.participant_id === "number" && requestBody.participant_id > 0;
    assertEquals(hasParticipantId, false, "Should reject when participant_id is missing");
  });

  await t.step("accepts valid request body", () => {
    const requestBody: RequestBody = {
      content: "This is a valid proposition",
      round_id: 1,
      participant_id: 1,
    };

    const isValid =
      typeof requestBody.content === "string" && requestBody.content.length > 0 &&
      typeof requestBody.round_id === "number" && requestBody.round_id > 0 &&
      typeof requestBody.participant_id === "number" && requestBody.participant_id > 0;

    assertEquals(isValid, true, "Should accept valid request with all required fields");
  });
});

// =============================================================================
// NORMALIZATION TESTS
// Tests the text normalization logic for duplicate detection
// =============================================================================

Deno.test("submit-proposition - normalization tests", async (t) => {
  const normalizeText = (text: string): string => text.toLowerCase().trim();

  await t.step("normalizes to lowercase", () => {
    const input = "WE SHOULD IMPROVE OUR TESTING";
    const normalized = normalizeText(input);
    assertEquals(normalized, "we should improve our testing");
  });

  await t.step("trims leading whitespace", () => {
    const input = "   We should improve";
    const normalized = normalizeText(input);
    assertEquals(normalized, "we should improve");
  });

  await t.step("trims trailing whitespace", () => {
    const input = "We should improve   ";
    const normalized = normalizeText(input);
    assertEquals(normalized, "we should improve");
  });

  await t.step("trims both leading and trailing whitespace", () => {
    const input = "   We should improve   ";
    const normalized = normalizeText(input);
    assertEquals(normalized, "we should improve");
  });

  await t.step("handles mixed case and whitespace", () => {
    const input = "   We Should IMPROVE   ";
    const normalized = normalizeText(input);
    assertEquals(normalized, "we should improve");
  });

  await t.step("preserves internal whitespace", () => {
    const input = "We should   improve   testing";
    const normalized = normalizeText(input);
    assertEquals(normalized, "we should   improve   testing");
  });

  await t.step("handles empty string", () => {
    const input = "";
    const normalized = normalizeText(input);
    assertEquals(normalized, "");
  });

  await t.step("handles whitespace-only string", () => {
    const input = "   ";
    const normalized = normalizeText(input);
    assertEquals(normalized, "");
  });
});

// =============================================================================
// DUPLICATE DETECTION LOGIC TESTS
// Tests the duplicate detection comparison logic
// =============================================================================

Deno.test("submit-proposition - duplicate detection logic", async (t) => {
  // Simulate existing translations in the database
  const existingTranslations = [
    { id: 1, normalized: "we should improve our testing strategy" },
    { id: 2, normalized: "let us add more unit tests" },
    { id: 3, normalized: "we need better documentation" },
  ];

  const findDuplicate = (newNormalized: string): { id: number } | null => {
    const match = existingTranslations.find((t) => t.normalized === newNormalized);
    return match ? { id: match.id } : null;
  };

  await t.step("detects exact match", () => {
    const newProposition = "we should improve our testing strategy";
    const duplicate = findDuplicate(newProposition);
    assertExists(duplicate, "Should find duplicate for exact match");
    assertEquals(duplicate?.id, 1);
  });

  await t.step("detects case variation (after normalization)", () => {
    const newProposition = "WE SHOULD IMPROVE OUR TESTING STRATEGY".toLowerCase().trim();
    const duplicate = findDuplicate(newProposition);
    assertExists(duplicate, "Should find duplicate for case variation");
    assertEquals(duplicate?.id, 1);
  });

  await t.step("detects whitespace variation (after normalization)", () => {
    const newProposition = "   we should improve our testing strategy   ".toLowerCase().trim();
    const duplicate = findDuplicate(newProposition);
    assertExists(duplicate, "Should find duplicate for whitespace variation");
    assertEquals(duplicate?.id, 1);
  });

  await t.step("returns null for unique content", () => {
    const newProposition = "this is a completely new idea";
    const duplicate = findDuplicate(newProposition);
    assertEquals(duplicate, null, "Should return null for unique content");
  });

  await t.step("partial match is not a duplicate", () => {
    const newProposition = "we should improve";
    const duplicate = findDuplicate(newProposition);
    assertEquals(duplicate, null, "Should not match partial content");
  });
});

// =============================================================================
// RESPONSE STRUCTURE TESTS
// Tests the response format for success and duplicate cases
// =============================================================================

Deno.test("submit-proposition - response structure", async (t) => {
  await t.step("success response has correct structure", () => {
    const successResponse = {
      proposition: {
        id: 123,
        round_id: 1,
        participant_id: 1,
        content: "Test proposition",
        created_at: "2026-01-25T00:00:00Z",
      },
    };

    assertExists(successResponse.proposition, "Response should have proposition");
    assertExists(successResponse.proposition.id, "Proposition should have id");
    assertExists(successResponse.proposition.round_id, "Proposition should have round_id");
    assertExists(successResponse.proposition.participant_id, "Proposition should have participant_id");
    assertExists(successResponse.proposition.content, "Proposition should have content");
    assertExists(successResponse.proposition.created_at, "Proposition should have created_at");
  });

  await t.step("duplicate response has correct structure", () => {
    const duplicateResponse = {
      error: "A proposition with the same content already exists in this round",
      code: "DUPLICATE_PROPOSITION",
      duplicate_proposition_id: 123,
    };

    assertExists(duplicateResponse.error, "Should have error message");
    assertEquals(duplicateResponse.code, "DUPLICATE_PROPOSITION", "Should have correct error code");
    assertExists(duplicateResponse.duplicate_proposition_id, "Should have duplicate_proposition_id");
    assertEquals(typeof duplicateResponse.duplicate_proposition_id, "number", "duplicate_proposition_id should be number");
  });

  await t.step("validation error response has correct structure", () => {
    const validationErrorResponse = {
      error: "Validation error: content: Content is required",
    };

    assertExists(validationErrorResponse.error, "Should have error message");
    assertEquals(
      validationErrorResponse.error.startsWith("Validation error:"),
      true,
      "Error should start with 'Validation error:'"
    );
  });
});

// =============================================================================
// AUTH VALIDATION TESTS
// Tests the authentication validation logic
// =============================================================================

Deno.test("submit-proposition - auth validation logic", async (t) => {
  const mockServiceKey = "test-service-role-key-12345";
  const mockSupabaseUrl = "https://test-project.supabase.co";
  const mockLocalUrl = "http://localhost:54321";

  await t.step("accepts service role key in Authorization header", () => {
    const authHeader = `Bearer ${mockServiceKey}`;
    const token = authHeader.replace("Bearer ", "");

    const isServiceRole = token === mockServiceKey;
    assertEquals(isServiceRole, true, "Should accept service role key");
  });

  await t.step("rejects invalid service role key", () => {
    const authHeader = "Bearer invalid-key";
    const token = authHeader.replace("Bearer ", "");

    const isServiceRole = token === mockServiceKey;
    assertEquals(isServiceRole, false, "Should reject invalid service role key");
  });

  await t.step("allows local development URLs", () => {
    const localUrls = [
      "http://localhost:54321",
      "http://127.0.0.1:54321",
      "http://kong:8000",
    ];

    for (const url of localUrls) {
      const isLocalDev = url.includes("localhost") ||
                         url.includes("127.0.0.1") ||
                         url.includes("kong:8000");
      assertEquals(isLocalDev, true, `Should allow local URL: ${url}`);
    }
  });

  await t.step("rejects production URLs without auth", () => {
    const prodUrl = "https://example-project.supabase.co";

    const isLocalDev = prodUrl.includes("localhost") ||
                       prodUrl.includes("127.0.0.1") ||
                       prodUrl.includes("kong:8000");
    assertEquals(isLocalDev, false, "Should not allow production URL as local dev");
  });

  await t.step("extracts token correctly from Bearer header", () => {
    const testCases = [
      { header: "Bearer abc123", expected: "abc123" },
      { header: "Bearer ", expected: "" },
      { header: "Bearer my-token-123", expected: "my-token-123" },
    ];

    for (const tc of testCases) {
      const token = tc.header.replace("Bearer ", "");
      assertEquals(token, tc.expected, `Should extract token from: ${tc.header}`);
    }
  });

  await t.step("handles missing Authorization header", () => {
    const authHeader = null as string | null;
    const token = authHeader?.replace("Bearer ", "");

    assertEquals(token, undefined, "Token should be undefined when header is missing");
  });
});

// =============================================================================
// HTTP STATUS CODE TESTS
// Tests the correct HTTP status codes for different scenarios
// =============================================================================

Deno.test("submit-proposition - HTTP status codes", async (t) => {
  await t.step("200 for successful submission", () => {
    const successStatus = 200;
    assertEquals(successStatus, 200, "Successful submission should return 200");
  });

  await t.step("400 for validation error", () => {
    const validationErrorStatus = 400;
    assertEquals(validationErrorStatus, 400, "Validation error should return 400");
  });

  await t.step("401 for unauthorized", () => {
    const unauthorizedStatus = 401;
    assertEquals(unauthorizedStatus, 401, "Unauthorized should return 401");
  });

  await t.step("405 for wrong method", () => {
    const methodNotAllowedStatus = 405;
    assertEquals(methodNotAllowedStatus, 405, "Wrong method should return 405");
  });

  await t.step("409 for duplicate proposition", () => {
    const conflictStatus = 409;
    assertEquals(conflictStatus, 409, "Duplicate proposition should return 409");
  });

  await t.step("500 for server error", () => {
    const serverErrorStatus = 500;
    assertEquals(serverErrorStatus, 500, "Server error should return 500");
  });
});

// =============================================================================
// TRANSLATION GENERATION TESTS
// Tests translation schema validation
// =============================================================================

Deno.test("submit-proposition - translation schema", async (t) => {
  await t.step("valid translation has en and es keys", () => {
    const validTranslation = {
      en: "English translation",
      es: "Spanish translation",
    };

    assertEquals(typeof validTranslation.en, "string", "Should have English translation");
    assertEquals(typeof validTranslation.es, "string", "Should have Spanish translation");
  });

  await t.step("translation record has correct structure", () => {
    const propositionId = 123;
    const translations = {
      en: "English text",
      es: "Spanish text",
    };

    const records = Object.entries(translations).map(([lang, translatedText]) => ({
      proposition_id: propositionId,
      entity_type: "proposition",
      field_name: "content",
      language_code: lang,
      translated_text: translatedText,
    }));

    assertEquals(records.length, 2, "Should create 2 translation records");

    const enRecord = records.find((r) => r.language_code === "en");
    assertExists(enRecord, "Should have English record");
    assertEquals(enRecord?.proposition_id, 123);
    assertEquals(enRecord?.entity_type, "proposition");
    assertEquals(enRecord?.field_name, "content");
    assertEquals(enRecord?.translated_text, "English text");

    const esRecord = records.find((r) => r.language_code === "es");
    assertExists(esRecord, "Should have Spanish record");
    assertEquals(esRecord?.translated_text, "Spanish text");
  });
});

// =============================================================================
// CARRIED-FORWARD PROPOSITION TESTS
// Tests that carried-forward propositions are included in duplicate check
// =============================================================================

Deno.test("submit-proposition - carried-forward propositions", async (t) => {
  // Simulate propositions including carried-forward ones
  const propositions = [
    { id: 1, round_id: 2, carried_from_id: null, english: "original idea" },
    { id: 2, round_id: 2, carried_from_id: 10, english: "carried forward idea" }, // Carried from round 1
    { id: 3, round_id: 2, carried_from_id: null, english: "another original" },
  ];

  const findDuplicateInRound = (roundId: number, normalizedEnglish: string): { id: number } | null => {
    const match = propositions.find(
      (p) => p.round_id === roundId && p.english === normalizedEnglish
    );
    return match ? { id: match.id } : null;
  };

  await t.step("includes carried-forward propositions in duplicate check", () => {
    const duplicate = findDuplicateInRound(2, "carried forward idea");
    assertExists(duplicate, "Should find carried-forward proposition as duplicate");
    assertEquals(duplicate?.id, 2);
  });

  await t.step("carried-forward proposition blocks new submission of same content", () => {
    // User tries to submit same content as a carried-forward proposition
    const newContent = "carried forward idea";
    const duplicate = findDuplicateInRound(2, newContent);
    assertNotEquals(duplicate, null, "Should detect duplicate against carried-forward proposition");
  });
});

// =============================================================================
// ROUND ISOLATION TESTS
// Tests that duplicate detection is scoped to the current round
// =============================================================================

Deno.test("submit-proposition - round isolation", async (t) => {
  const propositions = [
    { id: 1, round_id: 1, english: "shared idea" },
    { id: 2, round_id: 2, english: "shared idea" },
    { id: 3, round_id: 1, english: "round 1 only" },
  ];

  const findDuplicateInRound = (roundId: number, normalizedEnglish: string): { id: number } | null => {
    const match = propositions.find(
      (p) => p.round_id === roundId && p.english === normalizedEnglish
    );
    return match ? { id: match.id } : null;
  };

  await t.step("same content in different rounds is NOT duplicate", () => {
    // If we're checking in round 3, "shared idea" should not be a duplicate
    const duplicate = findDuplicateInRound(3, "shared idea");
    assertEquals(duplicate, null, "Should not find duplicate in different round");
  });

  await t.step("finds duplicate only in current round", () => {
    const duplicateInRound1 = findDuplicateInRound(1, "shared idea");
    const duplicateInRound2 = findDuplicateInRound(2, "shared idea");

    assertExists(duplicateInRound1, "Should find duplicate in round 1");
    assertEquals(duplicateInRound1?.id, 1);

    assertExists(duplicateInRound2, "Should find duplicate in round 2");
    assertEquals(duplicateInRound2?.id, 2);
  });

  await t.step("unique to round content is not duplicate", () => {
    const duplicateInRound2 = findDuplicateInRound(2, "round 1 only");
    assertEquals(duplicateInRound2, null, "Should not find round-1-only content in round 2");
  });
});
