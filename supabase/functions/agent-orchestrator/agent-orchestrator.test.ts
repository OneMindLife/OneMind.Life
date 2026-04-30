// Deno tests for agent-orchestrator's per-chat model selection.
// Run from repo root:
//   deno test --allow-env --allow-net supabase/functions/agent-orchestrator/
//
// These tests cover the pieces that would have caught the
// "agents silently 402 on DeepSeek when OneMind chat should be on Claude" bug:
// - AsyncLocalStorage-based per-request model resolution
// - Explicit `params.model` override
// - Default fallback when no store is active
// - Anthropic body shaping (system folding, thinking threshold, stream threshold)

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  activeModel,
  buildAnthropicBody,
  DEFAULT_MODEL,
  isClaudeModel,
  requestContext,
} from "./llm_routing.ts";

Deno.test("activeModel: falls back to DEFAULT_MODEL with no context and no override", () => {
  assertEquals(activeModel(), DEFAULT_MODEL);
  assertEquals(DEFAULT_MODEL, "deepseek-chat");
});

Deno.test("activeModel: reads from AsyncLocalStorage when set", () => {
  requestContext.run({ model: "claude-opus-4-7" }, () => {
    assertEquals(activeModel(), "claude-opus-4-7");
  });
});

Deno.test("activeModel: nested runs scope independently", () => {
  requestContext.run({ model: "claude-opus-4-7" }, () => {
    assertEquals(activeModel(), "claude-opus-4-7");
    requestContext.run({ model: "deepseek-chat" }, () => {
      assertEquals(activeModel(), "deepseek-chat");
    });
    assertEquals(activeModel(), "claude-opus-4-7");
  });
});

Deno.test("activeModel: explicit param override wins over store", () => {
  requestContext.run({ model: "claude-opus-4-7" }, () => {
    assertEquals(activeModel("deepseek-chat"), "deepseek-chat");
  });
});

Deno.test("activeModel: explicit override wins even with no store", () => {
  assertEquals(activeModel("claude-opus-4-7"), "claude-opus-4-7");
});

Deno.test("concurrent requestContext.run isolates models between async tasks", async () => {
  // Reproduces a concurrent edge-function invocation: one chat on Claude,
  // another on DeepSeek, running at the same time. AsyncLocalStorage must
  // keep the two independent or we'd route the wrong chat to the wrong model.
  const results: string[] = [];
  await Promise.all([
    requestContext.run({ model: "claude-opus-4-7" }, async () => {
      await new Promise((r) => setTimeout(r, 5));
      results.push(activeModel());
    }),
    requestContext.run({ model: "deepseek-chat" }, async () => {
      await new Promise((r) => setTimeout(r, 1));
      results.push(activeModel());
    }),
  ]);
  results.sort();
  assertEquals(results, ["claude-opus-4-7", "deepseek-chat"]);
});

Deno.test("buildAnthropicBody: folds system messages into top-level system param", () => {
  const { body } = buildAnthropicBody({
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Hello" },
    ],
    max_tokens: 100,
  });
  assertEquals(body.system, "You are a helpful assistant.");
  assertEquals(body.messages, [{ role: "user", content: "Hello" }]);
});

Deno.test("buildAnthropicBody: concatenates multiple system messages with double-newline", () => {
  const { body } = buildAnthropicBody({
    messages: [
      { role: "system", content: "System A" },
      { role: "system", content: "System B" },
      { role: "user", content: "Hello" },
    ],
    max_tokens: 100,
  });
  assertEquals(body.system, "System A\n\nSystem B");
});

Deno.test("buildAnthropicBody: omits system param when no system messages", () => {
  const { body } = buildAnthropicBody({
    messages: [{ role: "user", content: "Hello" }],
    max_tokens: 100,
  });
  assert(!("system" in body), "body should not have a system key");
});

Deno.test("buildAnthropicBody: enables adaptive thinking when max_tokens >= 1024", () => {
  const { body } = buildAnthropicBody({
    messages: [{ role: "user", content: "Hello" }],
    max_tokens: 1024,
  });
  assertEquals(body.thinking, { type: "adaptive" });
});

Deno.test("buildAnthropicBody: skips thinking on tiny calls to stay fast", () => {
  const { body } = buildAnthropicBody({
    messages: [{ role: "user", content: "Hello" }],
    max_tokens: 50,
  });
  assert(!("thinking" in body), "body should not have a thinking key");
});

Deno.test("buildAnthropicBody: streams only when max_tokens >= 2048", () => {
  const small = buildAnthropicBody({
    messages: [{ role: "user", content: "Hi" }],
    max_tokens: 2047,
  });
  const large = buildAnthropicBody({
    messages: [{ role: "user", content: "Hi" }],
    max_tokens: 2048,
  });
  assertEquals(small.shouldStream, false);
  assertEquals(large.shouldStream, true);
});

Deno.test("buildAnthropicBody: uses activeModel for the body's model field", () => {
  requestContext.run({ model: "claude-opus-4-7" }, () => {
    const { body } = buildAnthropicBody({
      messages: [{ role: "user", content: "Hello" }],
      max_tokens: 100,
    });
    assertEquals(body.model, "claude-opus-4-7");
  });
});

Deno.test("buildAnthropicBody: explicit model param overrides active context model", () => {
  requestContext.run({ model: "deepseek-chat" }, () => {
    const { body } = buildAnthropicBody({
      model: "claude-opus-4-7",
      messages: [{ role: "user", content: "Hello" }],
      max_tokens: 100,
    });
    assertEquals(body.model, "claude-opus-4-7");
  });
});

Deno.test("isClaudeModel: true for claude-* ids, false for deepseek/gpt/etc", () => {
  assertEquals(isClaudeModel("claude-opus-4-7"), true);
  assertEquals(isClaudeModel("claude-sonnet-4-6"), true);
  assertEquals(isClaudeModel("claude-haiku-4-5"), true);
  assertEquals(isClaudeModel("deepseek-chat"), false);
  assertEquals(isClaudeModel("gpt-4o"), false);
  assertEquals(isClaudeModel(""), false);
});
