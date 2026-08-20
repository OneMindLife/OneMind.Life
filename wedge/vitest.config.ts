import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

// Unit tests for the wedge's pure logic + data-mapping helpers. Node
// environment — these functions touch no DOM. Run: `npm test`.
export default defineConfig({
  test: {
    environment: "node",
    include: ["lib/**/*.test.ts"],
  },
  // Resolve the `@/` path alias (matches tsconfig) so tests can import runtime
  // modules; Supabase-coupled deps are mocked per-test via vi.mock.
  resolve: {
    alias: {
      "@": fileURLToPath(new URL(".", import.meta.url)),
    },
  },
});
