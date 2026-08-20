import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  hasSeenReveal,
  markRevealSeen,
  REVEAL_COPY,
  type RevealKey,
} from "./conceptReveals";

describe("concept reveals", () => {
  it("has copy for every reveal key", () => {
    const keys: RevealKey[] = ["duel", "branch"];
    for (const k of keys) {
      expect(REVEAL_COPY[k]).toBeTruthy();
      expect(REVEAL_COPY[k].length).toBeGreaterThan(0);
    }
  });

  it("treats a reveal as unseen with no storage (SSR/private mode)", () => {
    // vitest's node env has no localStorage — the read throws and we fall back
    // to "unseen", so worst case a reveal shows again rather than never.
    expect(hasSeenReveal("duel")).toBe(false);
  });

  describe("with a localStorage stub", () => {
    beforeEach(() => {
      const store = new Map<string, string>();
      vi.stubGlobal("localStorage", {
        getItem: (k: string) => store.get(k) ?? null,
        setItem: (k: string, v: string) => void store.set(k, v),
        removeItem: (k: string) => void store.delete(k),
        clear: () => store.clear(),
      });
    });
    afterEach(() => vi.unstubAllGlobals());

    it("fires once: unseen until marked, seen after", () => {
      expect(hasSeenReveal("duel")).toBe(false);
      markRevealSeen("duel");
      expect(hasSeenReveal("duel")).toBe(true);
    });

    it("keys are independent", () => {
      markRevealSeen("duel");
      expect(hasSeenReveal("duel")).toBe(true);
      expect(hasSeenReveal("branch")).toBe(false);
    });
  });
});
