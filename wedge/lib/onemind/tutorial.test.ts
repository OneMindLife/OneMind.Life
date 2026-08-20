import { describe, expect, it } from "vitest";
import { nextTutStep, readTutStep, TUT_ORDER, type TutStep } from "./tutorial";

describe("tutorial step machine", () => {
  it("orders the guided steps monotonically (vote-first flow)", () => {
    const order: TutStep[] = ["vote", "reply", "share", "done"];
    for (let i = 1; i < order.length; i++) {
      expect(TUT_ORDER[order[i]]).toBeGreaterThan(TUT_ORDER[order[i - 1]]);
    }
  });

  it("nextTutStep advances forward", () => {
    expect(nextTutStep("tap", "reply")).toBe("reply");
    expect(nextTutStep("reply", "done")).toBe("done");
  });

  it("nextTutStep never regresses (backward target is ignored)", () => {
    expect(nextTutStep("vote", "tap")).toBe("vote");
    expect(nextTutStep("done", "reply")).toBe("done");
  });

  it("nextTutStep is a no-op when target equals current", () => {
    expect(nextTutStep("share", "share")).toBe("share");
  });

  it("readTutStep falls back to 'vote' with no storage (node/SSR/private mode)", () => {
    // vitest runs in the node environment — localStorage is undefined, so the
    // read throws and the safe default applies. Vote-first: the guided flow now
    // starts in the duel.
    expect(readTutStep()).toBe("vote");
  });
});
