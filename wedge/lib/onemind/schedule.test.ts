import { describe, it, expect, vi, beforeEach } from "vitest";

// schedule.ts imports the Supabase client for its one read; mock it so the
// formatters (and the read's mapping) can be exercised in isolation.
const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock("@/lib/supabase/client", () => ({
  supabase: { rpc },
  ensureSignedIn: vi.fn(),
}));

import {
  countdown,
  getScheduleState,
  roomTimeLabel,
  viewerTimeLabel,
  windowLength,
} from "./schedule";

// 2026-07-25 12:00Z == 8:00 AM America/New_York (EDT, UTC-4).
const OPEN = "2026-07-25T12:00:00.000Z";
const CLOSE = "2026-07-25T12:30:00.000Z";
const NOW = Date.parse("2026-07-25T07:48:00.000Z");

describe("countdown", () => {
  it("shows hours and minutes when more than an hour out", () => {
    expect(countdown(NOW, OPEN)).toBe("4h 12m");
  });

  it("shows minutes and seconds inside the last hour", () => {
    expect(countdown(Date.parse("2026-07-25T11:47:30.000Z"), OPEN)).toBe(
      "12m 30s",
    );
  });

  it("shows seconds inside the last minute", () => {
    expect(countdown(Date.parse("2026-07-25T11:59:41.000Z"), OPEN)).toBe("19s");
  });

  it("reports 'now' once the boundary has passed, never a negative clock", () => {
    expect(countdown(Date.parse("2026-07-25T12:00:00.000Z"), OPEN)).toBe("now");
    expect(countdown(Date.parse("2026-07-25T12:05:00.000Z"), OPEN)).toBe("now");
  });

  it("is empty for a chat with no window", () => {
    expect(countdown(NOW, null)).toBe("");
  });
});

describe("roomTimeLabel", () => {
  it("renders the opening time in the room's zone, with the zone named", () => {
    // Zone abbreviation comes from the platform ICU data; assert the parts we
    // control rather than the exact abbreviation string.
    const label = roomTimeLabel(OPEN, "America/New_York");
    expect(label).toContain("8:00");
    expect(label).toContain("AM");
    expect(label).toMatch(/E[DS]T|GMT-[45]/);
  });

  it("survives DST: the same local hour maps to a different UTC instant", () => {
    // 2026-12-25 13:00Z == 8:00 AM EST (UTC-5).
    const winter = roomTimeLabel("2026-12-25T13:00:00.000Z", "America/New_York");
    expect(winter).toContain("8:00");
    expect(winter).toContain("AM");
  });

  it("is empty when there is no window", () => {
    expect(roomTimeLabel(null, "America/New_York")).toBe("");
  });
});

describe("viewerTimeLabel", () => {
  it("formats the same instant without a zone suffix", () => {
    expect(viewerTimeLabel(OPEN)).toMatch(/\d{1,2}:\d{2}/);
  });

  it("is empty when there is no window", () => {
    expect(viewerTimeLabel(null)).toBe("");
  });
});

describe("getScheduleState", () => {
  beforeEach(() => rpc.mockReset());

  it("maps the RPC row into the client shape", async () => {
    rpc.mockResolvedValue({
      data: [
        {
          is_open: false,
          opens_at: OPEN,
          closes_at: CLOSE,
          timezone: "America/New_York",
        },
      ],
      error: null,
    });
    await expect(getScheduleState(1269)).resolves.toEqual({
      isOpen: false,
      opensAt: OPEN,
      closesAt: CLOSE,
      timezone: "America/New_York",
    });
  });

  it("treats an empty result as open — an unschedulable chat must never be walled off", async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await expect(getScheduleState(1)).resolves.toEqual({
      isOpen: true,
      opensAt: null,
      closesAt: null,
      timezone: "UTC",
    });
  });
});

describe("windowLength", () => {
  it("describes a sub-hour window in minutes (structured)", () => {
    expect(windowLength(OPEN, CLOSE)).toEqual({ kind: "mins", n: 30 });
  });

  it("describes longer windows in hours (structured)", () => {
    expect(windowLength(OPEN, "2026-07-25T14:00:00.000Z")).toEqual({ kind: "hours", h: 2 });
    expect(windowLength(OPEN, "2026-07-25T14:15:00.000Z")).toEqual({
      kind: "hoursMins",
      h: 2,
      m: 15,
    });
  });

  it("is null when an edge is missing or inverted", () => {
    expect(windowLength(null, CLOSE)).toBeNull();
    expect(windowLength(CLOSE, OPEN)).toBeNull();
  });
});
