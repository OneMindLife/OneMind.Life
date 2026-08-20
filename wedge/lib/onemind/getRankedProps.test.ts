import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock the Supabase client so getRankedProps can be exercised in isolation.
// vi.hoisted lets the mock factory reference these fns (vi.mock is hoisted).
const { rpc, from } = vi.hoisted(() => ({ rpc: vi.fn(), from: vi.fn() }));
vi.mock("@/lib/supabase/client", () => ({
  supabase: { rpc, from },
  ensureSignedIn: vi.fn(),
}));

import { getRankedProps } from "./chat";

describe("getRankedProps — score is the ranking evidence", () => {
  beforeEach(() => {
    rpc.mockReset();
    from.mockReset();
  });

  it("maps global_score → WalkProp.score, preserving the RPC's (score-ranked) order", async () => {
    rpc.mockResolvedValue({
      data: [
        { proposition_id: 21, content: "B", content_translated: null, participant_id: null, global_score: 90.4 },
        { proposition_id: 20, content: "A", content_translated: null, participant_id: 3, global_score: 40.1 },
      ],
      error: null,
    });
    const board = await getRankedProps(99);
    expect(board.map((p) => p.id)).toEqual([21, 20]); // RPC order kept
    expect(board[0].score).toBeCloseTo(90.4);
    expect(board[1].score).toBeCloseTo(40.1);
  });

  it("prefers content_translated for the displayed text", async () => {
    rpc.mockResolvedValue({
      data: [
        { proposition_id: 1, content: "أمر مهم", content_translated: "An important matter", participant_id: 2, global_score: 55 },
      ],
      error: null,
    });
    const board = await getRankedProps(99, "en");
    expect(board[0].content).toBe("An important matter");
    expect(board[0].score).toBe(55);
  });

  it("falls back to submission order with NO score when the RPC returns nothing", async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    const order = vi.fn().mockResolvedValue({
      data: [{ id: 1, content: "x", participant_id: 2 }],
      error: null,
    });
    const eq = vi.fn(() => ({ order }));
    const select = vi.fn(() => ({ eq }));
    from.mockReturnValue({ select });

    const board = await getRankedProps(99);
    expect(board).toEqual([{ id: 1, content: "x", participant_id: 2 }]);
    expect(board[0].score).toBeUndefined(); // unranked → no score
  });

  it("throws if the RPC errors (never renders a wrong ranking silently)", async () => {
    rpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    await expect(getRankedProps(99)).rejects.toBeTruthy();
  });
});
