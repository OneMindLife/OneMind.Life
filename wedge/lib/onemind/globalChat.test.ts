import { describe, it, expect } from "vitest";
import {
  formatClock,
  flutterClock,
  clockPct,
  deriveClock,
  proposingBar,
  phaseLabel,
  pickStarters,
  voteProgress,
  takeAgoParts,
  winnerTimeParts,
  hueFor,
  mapGlobalWinners,
  type ClockState,
  type GlobalWinnerRow,
} from "./globalChat";

describe("flutterClock", () => {
  it("unit-suffixed, zero-padded below an hour", () => {
    expect(flutterClock(0)).toBe("0s");
    expect(flutterClock(9)).toBe("9s");
    expect(flutterClock(90)).toBe("1m 30s");
    expect(flutterClock(3599)).toBe("59m 59s");
  });
  it("adds the hours segment at/over an hour", () => {
    expect(flutterClock(3661)).toBe("1h 01m 01s");
    expect(flutterClock(43200)).toBe("12h 00m 00s");
  });
  it("floors negatives to 0s", () => {
    expect(flutterClock(-5)).toBe("0s");
  });
});

describe("formatClock", () => {
  it("mm:ss under an hour", () => {
    expect(formatClock(0)).toBe("0:00");
    expect(formatClock(9)).toBe("0:09");
    expect(formatClock(90)).toBe("1:30");
    expect(formatClock(3599)).toBe("59:59");
  });
  it("h:mm:ss at/over an hour (the real 12h clock)", () => {
    expect(formatClock(3661)).toBe("1:01:01");
    expect(formatClock(43200)).toBe("12:00:00");
  });
  it("floors negatives to 0:00", () => {
    expect(formatClock(-5)).toBe("0:00");
  });
});

describe("clockPct", () => {
  it("is remaining/duration, clamped 0..100", () => {
    expect(clockPct(43200, 43200)).toBe(100);
    expect(clockPct(21600, 43200)).toBe(50);
    expect(clockPct(0, 43200)).toBe(0);
    expect(clockPct(999999, 43200)).toBe(100); // clamp high
    expect(clockPct(-100, 43200)).toBe(0); // clamp low
    expect(clockPct(10, 0)).toBe(0); // guard div-by-zero
  });
});

describe("proposingBar", () => {
  const clock: ClockState = { remaining: 45, duration: 120, pct: 38 };
  it("shows the takes-threshold goal while the round can't end (timer would extend)", () => {
    // Copy now lives in the component (i18n); the formatter returns only mode + %.
    expect(proposingBar(0, clock)).toEqual({ mode: "goal", pct: 0 });
    expect(proposingBar(1, clock)).toEqual({ mode: "goal", pct: 50 });
  });
  it("shows the real countdown once the minimum is met", () => {
    expect(proposingBar(2, clock)).toEqual({ mode: "countdown", pct: 38 });
    expect(proposingBar(7, clock)).toEqual({ mode: "countdown", pct: 38 });
  });
});

describe("pickStarters", () => {
  it("dedupes, drops blanks and board collisions (case/space-insensitive), caps at n", () => {
    expect(
      pickStarters(
        ["Networking events", "  ", "networking   EVENTS", "Kale", "Small talk", "Monday standups"],
        ["kale"],
        3,
      ),
    ).toEqual(["Networking events", "Small talk", "Monday standups"]);
  });
  it("returns [] when everything collides or input is empty", () => {
    expect(pickStarters([], [], 3)).toEqual([]);
    expect(pickStarters(["Kale"], ["  kale "], 3)).toEqual([]);
  });
});

describe("deriveClock", () => {
  it("derives duration from the phase window and remaining from ends_at", () => {
    const started = "2026-07-09T00:00:00.000Z";
    const ends = "2026-07-09T12:00:00.000Z"; // 12h later
    const now = new Date("2026-07-09T03:00:00.000Z"); // 3h in, 9h left
    const c = deriveClock({ phase_started_at: started, phase_ends_at: ends }, now);
    expect(c.duration).toBe(43200);
    expect(c.remaining).toBe(9 * 3600);
    expect(c.pct).toBe(75);
  });
  it("never goes negative past the deadline", () => {
    const c = deriveClock(
      {
        phase_started_at: "2026-07-09T00:00:00.000Z",
        phase_ends_at: "2026-07-09T12:00:00.000Z",
      },
      new Date("2026-07-10T00:00:00.000Z"),
    );
    expect(c.remaining).toBe(0);
    expect(c.pct).toBe(0);
  });
  it("is safe with a missing round", () => {
    expect(deriveClock(null, new Date()).pct).toBe(0);
  });
});

describe("voteProgress", () => {
  it("uses (n-1) as the honest bracket denominator", () => {
    expect(voteProgress(5, 0)).toEqual({ total: 4, done: 0 });
    expect(voteProgress(5, 2)).toEqual({ total: 4, done: 2 });
    expect(voteProgress(5, 10)).toEqual({ total: 4, done: 4 }); // capped at total
    expect(voteProgress(1, 0)).toEqual({ total: 1, done: 0 }); // floor of 1 dot
    expect(voteProgress(0, 3)).toEqual({ total: 1, done: 1 });
  });
});

describe("takeAgoParts", () => {
  const now = new Date("2026-07-09T12:00:00.000Z");
  it("labels recent inserts as structured parts", () => {
    expect(takeAgoParts("2026-07-09T11:59:59.000Z", now)).toEqual({ kind: "now" });
    expect(takeAgoParts("2026-07-09T11:59:45.000Z", now)).toEqual({ kind: "secs", n: 15 });
    expect(takeAgoParts("2026-07-09T11:57:00.000Z", now)).toEqual({ kind: "mins", n: 3 });
  });
  it("is safe with a missing/invalid timestamp", () => {
    expect(takeAgoParts(null, now)).toEqual({ kind: "now" });
    expect(takeAgoParts("not-a-date", now)).toEqual({ kind: "now" });
  });
});

describe("winnerTimeParts", () => {
  it("labels very recent winners relatively as structured parts (TZ-independent)", () => {
    const now = new Date("2026-07-09T12:00:00.000Z");
    expect(winnerTimeParts("2026-07-09T11:59:30.000Z", now)).toEqual({ kind: "now" });
    expect(winnerTimeParts("2026-07-09T11:55:00.000Z", now)).toEqual({ kind: "minsAgo", n: 5 });
  });
  it("tags same-day winners as 'today'", () => {
    const now = new Date(2026, 6, 9, 15, 0, 0); // local
    const d = new Date(2026, 6, 9, 12, 0, 0); // 3h earlier, same local day
    expect(winnerTimeParts(d.toISOString(), now)).toEqual({ kind: "today", iso: d.toISOString() });
  });
  it("returns null for a missing decision time", () => {
    expect(winnerTimeParts(null, new Date())).toBeNull();
  });
});

describe("hueFor", () => {
  it("cycles the 6-hue palette and is negative-safe", () => {
    expect(hueFor(0)).toBe("h0");
    expect(hueFor(1)).toBe("h2");
    expect(hueFor(6)).toBe("h0");
    expect(hueFor(-1)).toBe("h1");
  });
});

describe("mapGlobalWinners", () => {
  const rows: GlobalWinnerRow[] = [
    {
      id: 10,
      text: "touch grass",
      beat: 5,
      voters: 38,
      time_iso: "2026-07-09T11:59:30.000Z",
      winning_participant_id: 7,
    },
    {
      id: 11,
      text: "reply-all needs a permit",
      beat: 4,
      voters: 44,
      time_iso: "2026-07-08T20:00:00.000Z",
      winning_participant_id: 42,
    },
    {
      // null-safe: a partially-empty server row must not throw
      id: 12,
      text: null,
      beat: null,
      voters: null,
      time_iso: null,
      winning_participant_id: null,
    },
  ];

  it("passes resolved fields straight through, preserving order", () => {
    const out = mapGlobalWinners(rows, 42);
    expect(out.map((w) => w.id)).toEqual([10, 11, 12]);
    expect(out[0].text).toBe("touch grass");
    expect(out[0].beat).toBe(5);
    expect(out[0].voters).toBe(38);
    expect(out[0].timeIso).toBe("2026-07-09T11:59:30.000Z");
  });

  it("flags 'mine' only when the winning author is the viewer", () => {
    const asMe = mapGlobalWinners(rows, 42);
    expect(asMe[0].mine).toBe(false);
    expect(asMe[1].mine).toBe(true);
    expect(asMe[2].mine).toBe(false);
    const asStranger = mapGlobalWinners(rows, 999);
    expect(asStranger.every((w) => !w.mine)).toBe(true);
  });

  it("is null-safe: empty text/beat/voters/time never throw or go negative", () => {
    const out = mapGlobalWinners([rows[2]], 7);
    expect(out[0].text).toBe("");
    expect(out[0].beat).toBe(0);
    expect(out[0].voters).toBe(0);
    expect(out[0].timeIso).toBeNull();
    expect(out[0].mine).toBe(false);
  });

  it("clamps a negative beat to 0", () => {
    const out = mapGlobalWinners([{ ...rows[0], beat: -3 }], 7);
    expect(out[0].beat).toBe(0);
  });
});

describe("phaseLabel — the bar must not claim a cadence the chat no longer runs", () => {
  it("renders sub-minute phases in seconds", () => {
    expect(phaseLabel(30)).toBe("30s");
    expect(phaseLabel(45)).toBe("45s");
  });

  it("renders the live-event cadence in minutes", () => {
    expect(phaseLabel(60)).toBe("1m");
    expect(phaseLabel(300)).toBe("5m");
  });

  it("renders the old 12h window in hours", () => {
    expect(phaseLabel(43200)).toBe("12h");
  });

  it("falls back to the 12h window for a missing or nonsense value", () => {
    expect(phaseLabel(null)).toBe("12h");
    expect(phaseLabel(undefined)).toBe("12h");
    expect(phaseLabel(0)).toBe("12h");
    expect(phaseLabel(Number.NaN)).toBe("12h");
  });
});
