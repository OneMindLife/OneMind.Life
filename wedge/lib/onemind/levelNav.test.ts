import { describe, expect, it } from "vitest";
import {
  descendChoices,
  jumpChoices,
  pathChoices,
  type Choices,
} from "./levelNav";

describe("descendChoices", () => {
  it("commits a child choice at the given key", () => {
    expect(descendChoices({}, -5, 12)).toEqual({ "-5": 12 });
  });

  it("adds to existing choices without mutating the input", () => {
    const base: Choices = { "-5": 12 };
    const next = descendChoices(base, 12, 34);
    expect(next).toEqual({ "-5": 12, "12": 34 });
    expect(base).toEqual({ "-5": 12 }); // input untouched
  });

  it("overwrites the choice at a key that's already committed", () => {
    expect(descendChoices({ "12": 34 }, 12, 99)).toEqual({ "12": 99 });
  });
});

describe("jumpChoices", () => {
  // Committed path: root(-5) → 12 → 34 → 56. committedKeys align with the crumbs.
  const committedKeys = [-5, 12, 34];
  const full: Choices = { "-5": 12, "12": 34, "34": 56 };

  it("jumping home (-1) drops every committed choice", () => {
    expect(jumpChoices(full, committedKeys, -1)).toEqual({});
  });

  it("jumping to crumb 0 keeps only the root choice", () => {
    expect(jumpChoices(full, committedKeys, 0)).toEqual({ "-5": 12 });
  });

  it("jumping to a middle crumb keeps that level and drops everything deeper", () => {
    expect(jumpChoices(full, committedKeys, 1)).toEqual({
      "-5": 12,
      "12": 34,
    });
  });

  it("jumping to the last crumb is a no-op on the committed path", () => {
    expect(jumpChoices(full, committedKeys, 2)).toEqual(full);
  });

  it("drops stale off-path keys so re-descending doesn't auto-jump past", () => {
    // A deeper choice (56) lingered from a previous descent past crumb 1.
    const withStale: Choices = { "-5": 12, "12": 34, "34": 56, "56": 78 };
    expect(jumpChoices(withStale, committedKeys, 1)).toEqual({
      "-5": 12,
      "12": 34,
    });
  });

  it("does not mutate the input", () => {
    const copy = { ...full };
    jumpChoices(full, committedKeys, 0);
    expect(full).toEqual(copy);
  });
});

describe("pathChoices", () => {
  it("returns the input unchanged for an empty path", () => {
    const base: Choices = { "-5": 12 };
    expect(pathChoices(base, [])).toBe(base);
  });

  it("commits a single-entry path at its round root", () => {
    expect(pathChoices({}, [{ round_id: 5, proposition_id: 12 }])).toEqual({
      "-5": 12,
    });
  });

  it("chains a multi-entry path root→target", () => {
    const path = [
      { round_id: 5, proposition_id: 12 },
      { round_id: 8, proposition_id: 34 },
      { round_id: 9, proposition_id: 56 },
    ];
    // root -5→12, then node 12→34, node 34→56.
    expect(pathChoices({}, path)).toEqual({
      "-5": 12,
      "12": 34,
      "34": 56,
    });
  });

  it("merges onto existing choices without mutating the input", () => {
    const base: Choices = { "-99": 1 };
    const next = pathChoices(base, [{ round_id: 5, proposition_id: 12 }]);
    expect(next).toEqual({ "-99": 1, "-5": 12 });
    expect(base).toEqual({ "-99": 1 });
  });
});
