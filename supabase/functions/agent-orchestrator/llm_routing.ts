// Pure helpers for per-chat LLM backend selection. Isolated from the SDK-heavy
// index.ts so Deno tests can exercise the routing logic without resolving
// npm:@anthropic-ai/sdk and its peer deps.
//
// The production `callLLM` in index.ts composes these helpers with the two
// client SDKs; tests exercise the helpers directly.

import { AsyncLocalStorage } from "node:async_hooks";

export const DEFAULT_MODEL = "deepseek-chat";

// Per-request store so callLLM can pick a backend without every call site
// threading a model string through every function.
export const requestContext = new AsyncLocalStorage<{ model: string }>();

export function activeModel(override?: string): string {
  return override ?? requestContext.getStore()?.model ?? DEFAULT_MODEL;
}

export function isClaudeModel(model: string): boolean {
  return model.startsWith("claude");
}

export interface LLMMessage {
  role: "system" | "user" | "assistant";
  content: string;
}
export interface LLMCallParams {
  model?: string;
  messages: LLMMessage[];
  max_tokens?: number;
  temperature?: number;
  response_format?: { type: "json_object" | "text" };
}
export interface LLMCallResponse {
  choices: Array<{ message: { content: string } }>;
}

// Shape an LLMCallParams into an Anthropic Messages API request body, honouring
// Opus 4.7's constraints:
// - role: "system" messages fold into top-level `system`.
// - Adaptive thinking enabled only when max_tokens >= 1024 (tiny calls skip it).
// - `shouldStream` is true when max_tokens >= 2048 — caller should use
//   `.stream()` + `.finalMessage()` to dodge edge-function HTTP timeouts.
export function buildAnthropicBody(params: LLMCallParams): {
  body: Record<string, unknown>;
  shouldStream: boolean;
} {
  const systemParts: string[] = [];
  const convo: Array<{ role: "user" | "assistant"; content: string }> = [];
  for (const m of params.messages) {
    if (m.role === "system") systemParts.push(m.content);
    else convo.push({ role: m.role, content: m.content });
  }
  const maxTokens = params.max_tokens ?? 16000;
  const body: Record<string, unknown> = {
    model: activeModel(params.model),
    max_tokens: maxTokens,
    messages: convo,
  };
  const systemText = systemParts.join("\n\n");
  if (systemText) body.system = systemText;
  if (maxTokens >= 1024) body.thinking = { type: "adaptive" };
  return { body, shouldStream: maxTokens >= 2048 };
}
