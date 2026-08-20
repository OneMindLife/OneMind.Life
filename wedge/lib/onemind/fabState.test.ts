import { describe, expect, it } from "vitest";
import { composeTargetFor, voteFabEnabled } from "./fabState";

describe("composeTargetFor", () => {
  it("targets the live round when there is one (takes precedence over a leaf)", () => {
    expect(composeTargetFor(42, 7)).toEqual({ kind: "round", roundId: 42 });
  });

  it("falls back to the leaf when there's no live round", () => {
    expect(composeTargetFor(null, 7)).toEqual({ kind: "leaf", propId: 7 });
  });

  it("is null when neither is available (transient loading)", () => {
    expect(composeTargetFor(null, null)).toBeNull();
  });
});

describe("voteFabEnabled", () => {
  it("is false without a pair, whatever the count", () => {
    expect(voteFabEnabled(false, 10)).toBe(false);
  });

  it("is false with a pair but no full match (0 or 1 unplaced → floor/2 = 0)", () => {
    expect(voteFabEnabled(true, 0)).toBe(false);
    expect(voteFabEnabled(true, 1)).toBe(false);
  });

  it("is true with a pair and at least one match's worth of unplaced", () => {
    expect(voteFabEnabled(true, 2)).toBe(true);
    expect(voteFabEnabled(true, 5)).toBe(true);
  });
});
