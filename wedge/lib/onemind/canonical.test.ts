import { describe, expect, it } from "vitest";
import { canonicalForCode, CANONICAL_ORIGIN } from "./canonical";

describe("canonicalForCode — resolves the /g/<code> SEO canonical", () => {
  it("points SEO-eligible codes at their /opinions/<code>/ content page", () => {
    expect(canonicalForCode("GLOBAL", ["GLOBAL", "TESTAB"])).toBe(
      `${CANONICAL_ORIGIN}/opinions/GLOBAL/`,
    );
  });

  it("uses a param-stripped self-canonical for non-eligible codes", () => {
    expect(canonicalForCode("ABC123", ["GLOBAL"])).toBe(
      `${CANONICAL_ORIGIN}/g/ABC123`,
    );
  });

  it("matches eligibility case-insensitively (path codes are upper-cased)", () => {
    // seoCodes lower-case, path code as-typed → still resolves to /opinions.
    expect(canonicalForCode("global", ["global"])).toBe(
      `${CANONICAL_ORIGIN}/opinions/GLOBAL/`,
    );
  });

  it("never carries query params (the ?take=<node> variants collapse to one)", () => {
    // The caller passes the bare code, but guard the contract: output is always
    // a clean URL with no '?'.
    expect(canonicalForCode("GLOBAL", []).includes("?")).toBe(false);
    expect(canonicalForCode("GLOBAL", ["GLOBAL"]).includes("?")).toBe(false);
  });

  it("empty eligibility list → everything self-canonicals (safe build fallback)", () => {
    // getSeoIndex() fails soft to [] — no code should then point at a
    // non-existent /opinions page.
    expect(canonicalForCode("GLOBAL", [])).toBe(`${CANONICAL_ORIGIN}/g/GLOBAL`);
  });
});
