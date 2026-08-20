// Multi-context end-to-end suite for the OneMind wedge.
//
// Each browser CONTEXT is an isolated anonymous Supabase user, so this drives
// the real multi-user flows (host + participants) with no localStorage hacks —
// and, because the wedge auto-refreshes (polling), it also exercises live
// cross-client updates. Reuses the Playwright + chromium already installed under
// tools/load-sim.
//
// Usage:
//   (dev server running on :3000, hitting prod Supabase)
//   node wedge/e2e/run.mjs
//   BASE=https://onemind.life node wedge/e2e/run.mjs   # against a deploy
//
// Exit code is non-zero if any path fails.

import { createRequire } from "module";
const require = createRequire(
  "/home/joelc0193/StudioProjects/OneMind_SaaS/tools/load-sim/",
);
const { chromium, devices } = require("playwright");

const BASE = process.env.BASE || "http://localhost:3000";
const SHORT = 12000;
// Auto-advance transitions need a server trigger + the host's 3s poll to land,
// which is slower over a remote preview — give those waits extra headroom.
const LONG = 35000;
// MOBILE=1 → chromium with the iPhone descriptor (touch + mobile viewport +
// iOS UA). A partial Safari proxy; true WebKit/iOS still needs a real device.
const MOBILE = process.env.MOBILE === "1";
const DEVICE = MOBILE ? devices["iPhone 13"] : null;
// Demo / watch mode. HEADED=1 opens a visible window and slows actions so a
// human can watch; ONLY=<substr> runs just the matching scenario(s);
// GATE_PAUSE=<ms> holds on the round-2 "keep or replace?" gate so it's visible.
const HEADED = process.env.HEADED === "1";
const SLOWMO = Number(process.env.SLOWMO || (HEADED ? 650 : 0));
const ONLY = process.env.ONLY || "";
const GATE_PAUSE = Number(process.env.GATE_PAUSE || (HEADED ? 4500 : 0));

// STEP=1 → live step-gate: pause before each game-converge action until a human
// releases the next step (write N to STEP_FILE to allow steps 1..N). Each gate()
// call is the next step in sequence. Used for a watch-along demo across the 3
// windows; a no-op otherwise.
const STEP = process.env.STEP === "1";
const STEP_FILE = process.env.STEP_FILE || "/tmp/om_step.txt";
const fs = require("fs");
let _stepN = 0;
async function gate(label) {
  if (!STEP) return;
  const need = ++_stepN;
  console.log(`\n⏸  [${need}] ${label}  — say "ok"`);
  for (;;) {
    let v = 0;
    try {
      v = parseInt(fs.readFileSync(STEP_FILE, "utf8").trim()) || 0;
    } catch {
      /* file not created yet */
    }
    if (v >= need) break;
    await new Promise((r) => setTimeout(r, 400));
  }
  console.log(`▶  [${need}] ${label}`);
}

let browser;
const results = [];

function assert(cond, msg) {
  if (!cond) throw new Error("ASSERT FAILED: " + msg);
}

async function newUser() {
  const ctx = await browser.newContext(
    DEVICE ?? { viewport: { width: 390, height: 844 } },
  );
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("   [pageerror]", e.message));
  return { ctx, page };
}

// ── primitives ──────────────────────────────────────────────────────────────

async function createChat(page, question) {
  await page.goto(BASE + "/create");
  await page.fill("textarea", question);
  await page.click('button:has-text("Create a room")');
  await page.waitForURL(/\/c\/[^_]/, { timeout: SHORT });
  return page.url().match(/\/c\/([^/]+)/)[1];
}

const open = (page, code) =>
  page.goto(`${BASE}/c/${code}`, { waitUntil: "networkidle" });

const seedGroup = (page) =>
  page.click('button:has-text("Get ideas from the group")');

async function seedOptions(page, opts) {
  await page.click('button:has-text("I already have the options")');
  // The dialog shows 2 fields by default — add more for extra options.
  for (let i = 2; i < opts.length; i++)
    await page.click('button:has-text("Add option")');
  const inputs = page.locator("input.opt-input");
  for (let i = 0; i < opts.length; i++) await inputs.nth(i).fill(opts[i]);
  await page.click('button:has-text("Start voting")');
}

async function addIdea(page, text) {
  await page.fill('textarea[placeholder^="Type your idea"]', text);
  await page.click('button:has-text("Add idea")');
  await page.waitForSelector(String.raw`textarea[placeholder^="Type your idea"]`, { state: "detached", timeout: SHORT });
}

async function clickWhenEnabled(page, label) {
  await page.waitForFunction(
    (l) => {
      const b = [...document.querySelectorAll("button")].find((x) =>
        x.textContent.includes(l),
      );
      return b && !b.disabled;
    },
    label,
    { timeout: 20000 },
  );
  await page.click(`button:has-text("${label}")`);
}

async function isDone(page) {
  return (await page.locator("text=Your votes are in").count()) > 0;
}

// "This person has no more voting to do" — either they finished their pairs, OR
// they have nothing to vote on (they authored the only available idea(s), e.g.
// a round-2 leader/challenger author). Both are terminal for vote().
// Always-terminal states (independent of whether we voted yet): finished our
// pairs, nothing to vote on, or the chat converged.
async function noMoreVoting(page) {
  return (
    (await isDone(page)) ||
    (await page.locator("text=Nothing to vote on yet").count()) > 0 ||
    (await page.locator(".converged").count()) > 0
  );
}
// The "round-N result / keep-or-replace" gate. Ambiguous: it's the NEXT screen
// after rating (terminal) OR the PREVIOUS screen before rating (must wait for
// auto-advance). vote() resolves it by whether it has already cast a vote.
async function onResultGate(page) {
  return (
    (await page.locator('.yes').count()) > 0 ||
    (await page.locator("text=Round 1 result").count()) > 0
  );
}

// Vote through the duel. If `target` is given, pick the prop containing it when
// present; otherwise pick the first. Robust to backend auto-advance: a round can
// finalize the instant everyone's done, flipping this page to the next gate or
// the result mid-vote. The result gate is terminal ONLY once we've cast a vote
// (R1-done); if we haven't voted yet it's the pre-rating gate → wait for the
// auto-advance to open rating.
async function vote(page, target) {
  let casted = 0;
  const deadline = Date.now() + 40000;
  for (;;) {
    if (await noMoreVoting(page)) return; // votes-in / nothing-to-vote / converged
    if (await onResultGate(page)) {
      if (casted >= 1) return; // already voted; the round advanced past us
    } else {
      const props = page.locator(".prop:not([disabled])");
      if ((await props.count()) > 0) {
        try {
          let idx = 0;
          if (target) {
            const n = await props.count();
            for (let j = 0; j < n; j++) {
              if ((await props.nth(j).innerText()).includes(target)) {
                idx = j;
                break;
              }
            }
          }
          await props.nth(idx).click({ timeout: 5000 });
          casted++;
          await page.waitForTimeout(400);
          continue;
        } catch {
          await page.waitForTimeout(300);
          continue;
        }
      }
    }
    if (Date.now() > deadline) {
      if (casted >= 1) return;
      throw new Error("vote: never reached a votable pair");
    }
    await page.waitForTimeout(500);
  }
}

// Click a button by text, tolerating the transient disabled/detached state
// from in-flight actions + polling re-renders.
async function clickResilient(page, selector, timeout = 8000) {
  const end = Date.now() + timeout;
  for (;;) {
    try {
      await page.locator(selector).first().click({ timeout: 3000 });
      return;
    } catch (e) {
      if (Date.now() > end) throw e;
      await page.waitForTimeout(300);
    }
  }
}

// Backend now auto-finalizes rating once everyone has voted (matches_preview_
// maybe_finalize). The manual "End voting" control is a fallback for when the
// host gets ahead of the backend — so this is best-effort: click it only if it's
// still there, otherwise the round already advanced.
async function endVoting(page) {
  try {
    await page.waitForFunction(
      (l) => {
        const b = [...document.querySelectorAll("button")].find((x) =>
          x.textContent.includes(l),
        );
        return b && !b.disabled;
      },
      "End voting now",
      { timeout: 4000 },
    );
    await clickResilient(page, 'button:has-text("End voting now")');
  } catch {
    /* backend already finalized the round — expected with backend auto-advance */
  }
}
const startVoting = (page) => clickWhenEnabled(page, "Start voting");

// R2+ responses: challenge the leader, or keep it (affirm).
async function challenge(page, text) {
  await clickResilient(page, '.no');
  await page.fill("textarea", text);
  await clickResilient(page, 'button:has-text("Submit alternative")');
}
const affirm = (page) =>
  clickResilient(page, '.yes');

async function text(page, sel) {
  const l = page.locator(sel);
  return (await l.count()) ? (await l.first().innerText()) : "";
}

// ── paths ───────────────────────────────────────────────────────────────────

// 1) Group, leader wins both rounds → converged.
async function groupConverge() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E group converge?");
  await seedGroup(host.page);
  await addIdea(host.page, "Alpha plan");

  const p2 = await newUser();
  await open(p2.page, code);
  await addIdea(p2.page, "Beta plan");
  const p3 = await newUser();
  await open(p3.page, code);
  await addIdea(p3.page, "Gamma plan");

  await startVoting(host.page); // host sees ≥2 (polling) → enabled
  await vote(host.page);
  await vote(p2.page);
  await vote(p3.page);
  await endVoting(host.page); // R1 → R2 leader/challenge

  // R2 needs >=2 responses: one challenges, one keeps. Then everyone votes the
  // leader → it wins again → converge.
  await host.page.waitForSelector("text=Round 1 result", { timeout: SHORT });
  // Demo: hold on the round-2 "keep or replace?" gate so it can be watched
  // (the round-1-result card anchored at the top).
  if (GATE_PAUSE) {
    await host.page.bringToFront();
    await host.page.waitForTimeout(GATE_PAUSE);
  }
  const leader = (await text(host.page, ".leader .la")).trim();
  await open(p2.page, code);
  await challenge(p2.page, "A late challenger");
  await open(p3.page, code);
  await affirm(p3.page); // 2nd response (1 challenge + 1 keep)
  await startVoting(host.page); // R2 → rating
  await vote(host.page, leader);
  await vote(p2.page, leader);
  await vote(p3.page, leader);
  await endVoting(host.page);

  await host.page.waitForSelector("text=The group locked it in", { timeout: SHORT });
  const winner = (await text(host.page, ".converged .ca")).trim();
  assert(winner === leader, `converged winner "${winner}" should equal leader "${leader}"`);
  // History reachable (timeline loads async — wait for items).
  await host.page.click('button:has-text("How it converged")');
  await host.page.waitForSelector(".tl-item", { timeout: SHORT });
  assert(
    (await host.page.locator(".tl-item").count()) >= 2,
    "history should list ≥2 rounds",
  );

  // Regression for the "0 voters" race: a BRAND-NEW viewer (just auto-joined)
  // opens the ended chat and immediately drills into History — counts must be
  // correct (authoritative DEFINER read), never a flashed "0 voters".
  const viewer = await newUser();
  await open(viewer.page, code);
  await viewer.page.waitForSelector("text=The group locked it in", { timeout: SHORT });
  await viewer.page.click('button:has-text("How it converged")');
  await viewer.page.waitForSelector(".tl-item", { timeout: SHORT });
  const firstRow = (await viewer.page.locator(".tl-item").first().innerText()).toLowerCase();
  assert(
    !/\b0 (voted|kept)/.test(firstRow) && /[1-9]\d* (voted|kept)/.test(firstRow),
    `fresh viewer must see real counts, got: ${firstRow.replace(/\n/g, " ")}`,
  );
  return `converged on "${winner}"; fresh viewer saw real counts`;
}

// 2) Challenger BEATS the leader in R2 → a fresh round opens with the challenger
//    as the new leader (re-convergence, NOT sealed).
async function challengerBeatsLeader() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E challenger beats leader?");
  await seedGroup(host.page);
  await addIdea(host.page, "Original A");
  const p2 = await newUser();
  await open(p2.page, code);
  await addIdea(p2.page, "Original B");
  const p3 = await newUser();
  await open(p3.page, code);
  await addIdea(p3.page, "Original C");

  await startVoting(host.page);
  await vote(host.page);
  await vote(p2.page);
  await vote(p3.page);
  await endVoting(host.page);

  await host.page.waitForSelector("text=Round 1 result", { timeout: SHORT });
  const leader = (await text(host.page, ".leader .la")).trim();
  const challenger = "Beats the leader";
  await open(p2.page, code);
  await challenge(p2.page, challenger);
  await open(p3.page, code);
  await affirm(p3.page); // 2nd response so the host can advance
  await startVoting(host.page);
  // Everyone votes the CHALLENGER over the leader (p3, owning neither, decides).
  await vote(host.page, challenger);
  await vote(p2.page, challenger);
  await vote(p3.page, challenger);
  await endVoting(host.page);

  // Not converged: a new round opens with the challenger as the leader.
  await host.page.waitForSelector("text=Round 2 result", { timeout: SHORT });
  const newLeader = (await text(host.page, ".leader .la")).trim();
  assert(
    (await host.page.locator("text=The group locked it in").count()) === 0,
    "should NOT have sealed after a challenger win",
  );
  assert(
    newLeader === challenger,
    `R3 leader "${newLeader}" should be the challenger "${challenger}" (was "${leader}")`,
  );
  return `challenger won R2 → R3 opened with new leader "${newLeader}"`;
}

// 3) Poll (host provides options) → converges through the R2 challenge.
async function pollConverge() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E poll converge?");
  await seedOptions(host.page, ["Red", "Green", "Blue"]);
  await vote(host.page);
  const p2 = await newUser();
  await open(p2.page, code);
  await vote(p2.page);
  await endVoting(host.page); // R1 → R2 challenge

  await host.page.waitForSelector("text=Round 1 result", { timeout: SHORT });
  const leader = (await text(host.page, ".leader .la")).trim();
  // Nobody challenges — two keep the leader (2 responses), host advances →
  // skips voting → result.
  await affirm(host.page);
  await open(p2.page, code);
  await affirm(p2.page);
  await startVoting(host.page);
  await host.page.waitForSelector("text=The group locked it in", { timeout: SHORT });
  const winner = (await text(host.page, ".converged .ca")).trim();
  assert(winner === leader, `poll winner "${winner}" should equal R1 leader "${leader}"`);
  const cs = (await text(host.page, ".converged .cs")).toLowerCase();
  assert(cs.includes("no alternatives"), `should read unchallenged, got: "${cs}"`);
  return `poll converged (unchallenged) on "${winner}"`;
}

// 4) All participants affirm ("Keep it") → counts as responses,
//    room does NOT auto-resolve (host stays in control).
async function allAffirmNoAutoResolve() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E all affirm?");
  await seedGroup(host.page);
  await addIdea(host.page, "Keepme A");
  const p2 = await newUser();
  await open(p2.page, code);
  await addIdea(p2.page, "Other B");
  // 3rd proposer so R1 has a real (non-author) voter — 2 people each proposing
  // once is the dead case (nobody can form a pair), now correctly un-endable.
  const p3 = await newUser();
  await open(p3.page, code);
  await addIdea(p3.page, "Third C");
  await startVoting(host.page);
  await vote(host.page);
  await vote(p2.page);
  await vote(p3.page);
  await endVoting(host.page);

  await host.page.waitForSelector("text=Round 1 result", { timeout: SHORT });
  // All affirm.
  await host.page.click('button:has-text("Keep it")');
  await open(p2.page, code);
  await p2.page.click('button:has-text("Keep it")');
  await open(p3.page, code);
  await p3.page.click('button:has-text("Keep it")');
  // Give polling a few cycles; the room must NOT have ended.
  await host.page.waitForTimeout(5000);
  await open(host.page, code);
  assert(
    (await host.page.locator("text=The group locked it in").count()) === 0,
    "all-affirm must NOT auto-resolve a quick room",
  );
  // Responses counted — the host footer reflects affirmations ("N responses").
  const note = (await text(host.page, ".host-note")).toLowerCase();
  assert(
    /[1-9]\d* responses?/.test(note),
    `host should see the affirm count, got: "${note}"`,
  );
  // Now the host advances with no alternatives → skips voting → unchallenged result.
  await startVoting(host.page);
  await host.page.waitForSelector("text=The group locked it in", { timeout: SHORT });
  const cs = (await text(host.page, ".converged .cs")).toLowerCase();
  assert(cs.includes("no alternatives"), `should read unchallenged, got: "${cs}"`);
  return `all affirmed → no auto-resolve → host locked in (unchallenged)`;
}

// 5) Live update via polling: a participant's new idea appears on the host's
//    screen WITHOUT a manual reload.
async function liveUpdate() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E live update?");
  await seedGroup(host.page);
  await addIdea(host.page, "Host idea");
  const p2 = await newUser();
  await open(p2.page, code);
  await addIdea(p2.page, "Surprise idea");
  // Host did NOT reload — polling should surface it within a few seconds.
  await host.page.waitForSelector("text=Surprise idea", { timeout: 10000 });

  // Realtime presence: both contexts are open on this chat → host's rail shows
  // a live count of ≥2.
  await host.page.waitForSelector(".presence.live", { timeout: 10000 });
  const pres = (await text(host.page, ".presence")).toLowerCase();
  const pm = pres.match(/(\d+)\s*here/);
  assert(pm && Number(pm[1]) >= 2, `host should see >=2 present, got "${pres}"`);
  return `idea appeared without reload; presence "${pres.replace(/\s+/g, " ")}"`;
}

// 6) Non-host cannot advance: participant sees a wait state, not "Start voting".
async function hostGating() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E host gating?");
  await seedGroup(host.page);
  await addIdea(host.page, "H idea");
  const p2 = await newUser();
  await open(p2.page, code);
  await addIdea(p2.page, "P idea");
  assert(
    (await p2.page.locator('button:has-text("Start voting")').count()) === 0,
    "participant must not see Start voting",
  );
  assert(
    (await p2.page.locator("text=when the host").count()) > 0,
    "participant should see a host-controlled wait note",
  );
  assert(
    (await host.page.locator('button:has-text("Start voting")').count()) > 0,
    "host should see Start voting",
  );
  return "participant gated; host has the control";
}

// 7) Duplicate proposition is rejected.
async function duplicateProp() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E duplicate?");
  await seedGroup(host.page);
  await addIdea(host.page, "Exactly the same");
  const p2 = await newUser();
  await open(p2.page, code);
  await p2.page.fill('textarea[placeholder^="Type your idea"]', "Exactly the same");
  await p2.page.click('button:has-text("Add idea")');
  // Dedup runs in the edge function (translation + normalize), so allow time.
  await p2.page.waitForSelector("text=already added", { timeout: 25000 });
  return "duplicate idea rejected";
}

// 8) Unknown code → not-found screen.
async function notFound() {
  const u = await newUser();
  await u.page.goto(`${BASE}/c/ZZ9 QZZ`.replace(" ", ""));
  await u.page.waitForSelector("text=Chat not found", { timeout: SHORT });
  return "unknown code shows not-found";
}

// 9b) Tie ("Equal") + "Skip this pair" controls still drive the round to done
//     and let the host finalize.
async function tieAndSkip() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E tie and skip?");
  await seedGroup(host.page);
  await addIdea(host.page, "Idea one");
  const p2 = await newUser();
  await open(p2.page, code);
  await addIdea(p2.page, "Idea two");
  const p3 = await newUser();
  await open(p3.page, code);
  await addIdea(p3.page, "Idea three");
  await startVoting(host.page);

  // A 4th user (owns nothing) gets multiple pairs → exercise Equal then Skip.
  const v = await newUser();
  await open(v.page, code);
  await v.page.locator(".prop").first().waitFor({ timeout: SHORT });
  await clickResilient(v.page, 'button:has-text("Equal")');
  await v.page.waitForTimeout(400);
  if (!(await isDone(v.page))) {
    await clickResilient(v.page, 'button:has-text("Skip this pair")');
  }
  await vote(v.page); // finish remaining pairs
  assert(await isDone(v.page), "tie+skip voter should reach done");

  await vote(host.page);
  await vote(p2.page);
  await vote(p3.page);
  await endVoting(host.page);
  await host.page.waitForSelector("text=Round 1 result", { timeout: SHORT });
  return "Equal + Skip handled; round finalized to R2";
}

// 10) Reload mid-proposing resumes (submitted idea persists).
async function reloadResume() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E reload resume?");
  await seedGroup(host.page);
  await addIdea(host.page, "Persisted idea");
  await open(host.page, code); // reload
  await host.page.waitForSelector("text=Your idea is in", { timeout: SHORT });
  assert(
    (await host.page.locator("text=Persisted idea").count()) > 0,
    "submitted idea should persist across reload",
  );
  return "state resumed after reload";
}

// 11) Two people, each proposing ONCE → nobody can form a pair (you don't vote
// on your own idea) → both see the honest "invite others" empty-state, NOT a
// false "done". A 3rd person (non-author) joining during rating CAN vote.
async function twoPersonNoVote() {
  const host = await newUser();
  const code = await createChat(host.page, "E2E two-person no-vote?");
  await seedGroup(host.page);
  await addIdea(host.page, "Host idea");

  const p2 = await newUser();
  await open(p2.page, code);
  await addIdea(p2.page, "Second idea");

  await startVoting(host.page); // 2 props → rating

  // Each authored one of the two ideas → no pair is possible for either.
  await host.page.waitForSelector("text=Nothing to vote on yet", { timeout: SHORT });
  await p2.page.waitForSelector("text=Nothing to vote on yet", { timeout: SHORT });
  // Honest empty-state, NOT a false "your votes are in".
  assert(!(await isDone(host.page)), "host must NOT show a false 'votes are in'");
  assert(!(await isDone(p2.page)), "p2 must NOT show a false 'votes are in'");

  // Host-side guard: with 0 real votes the host CANNOT end the round, so it
  // can't finalize into a meaningless winner.
  await host.page.waitForSelector("text=No votes cast yet", { timeout: SHORT });
  assert(
    await host.page.locator('button:has-text("End voting now")').first().isDisabled(),
    "host's End voting must be disabled with 0 real votes",
  );

  // A 3rd person joining during rating authored neither idea → CAN form a pair
  // and vote. Validates the 'invite someone to vote' remedy.
  const p3 = await newUser();
  await open(p3.page, code);
  await p3.page.waitForSelector(".prop", { timeout: SHORT });
  assert(
    (await p3.page.locator("text=Nothing to vote on yet").count()) === 0,
    "3rd person (non-author) should vote, not see the empty-state",
  );
  await vote(p3.page);

  // Now there is >=1 real vote → the host's End button unblocks.
  await host.page.waitForFunction(
    (l) => {
      const b = [...document.querySelectorAll("button")].find((x) =>
        x.textContent.includes(l),
      );
      return b && !b.disabled;
    },
    "End voting now",
    { timeout: SHORT },
  );
  return "0-vote round blocked host's end; a non-author voter unblocked it";
}

// G2) Global Chat smoke — the continuous "the room speaks" surface (code GLOBAL,
// chat 1216). READ-ONLY by default: asserts the page loads and the header
// (brand + live presence + Invite), the dock phase-bar countdown, the feed
// spine, and the live staging (winners feed if the room has sealed any, else the
// blind composer) all render. Set GLOBAL_WRITE=1 to ALSO drive a real take —
// OFF by default because GLOBAL is the LIVE public room (a posted take enters the
// real round). Run against a deploy: BASE=<preview-url> ONLY=global node e2e/run.mjs
async function globalChat() {
  const code = process.env.GLOBAL_CODE || "GLOBAL";
  const u = await newUser();
  await u.page.goto(`${BASE}/c/${code}`, { waitUntil: "networkidle" });

  // Header: brand lockup, live presence ("N here"), Invite pill.
  await u.page.waitForSelector("text=Global", { timeout: SHORT });
  await u.page.waitForSelector(".presence", { timeout: SHORT });
  const pres = (await text(u.page, ".presence")).toLowerCase();
  assert(/\bhere\b/.test(pres), `presence should read "N here", got "${pres}"`);
  assert(
    (await u.page.locator('button:has-text("Invite")').count()) > 0,
    "Invite pill should render in the header",
  );

  // Feed spine + dock phase-bar (Proposing countdown, Proposing threshold-goal
  // when the round is below proposing_minimum, or Voting countdown).
  await u.page.waitForSelector('[data-screen-label="Global chat"]', { timeout: SHORT });
  await u.page.waitForSelector("text=the room decides one take at a time", { timeout: SHORT });
  const barCount = await u.page
    .locator("text=/Voting opens in|Voting opens at|Round ends in/")
    .count();
  assert(barCount > 0, "dock phase-bar (countdown or threshold goal) should render");

  // The live staging block always renders; the winners feed shows entries once
  // the room has sealed at least one round.
  await u.page.waitForSelector('[data-testid="global-stage"]', { timeout: SHORT });
  const winners = await u.page.locator('[data-testid="global-winner"]').count();
  const composers = await u.page.locator('[data-testid="global-composer"]').count();
  assert(
    winners > 0 || composers > 0,
    "either past winners or the live composer must render",
  );
  let note = `loaded; ${winners} winner(s); presence "${pres.replace(/\s+/g, " ").trim()}"`;

  // Optional write-path (LIVE room — opt-in). Proposing + composer present →
  // post a take → staging reveals the room's takes and the composer is replaced
  // by the "your take's in" status.
  if (process.env.GLOBAL_WRITE === "1" && composers > 0) {
    await u.page.fill('[data-testid="global-composer"]', "E2E smoke take " + Date.now());
    await u.page.click('button[aria-label="Post your take"]');
    // One take per round: after posting, the composer is removed — replaced by
    // the "your take's in" status (round still proposing) or the voting stage
    // (the post filled the round and it advanced). Either proves the post landed
    // and the composer no longer accepts input.
    await u.page.waitForFunction(
      () => document.querySelectorAll('[data-testid="global-composer"]').length === 0,
      null,
      { timeout: SHORT },
    );
    const status = (await u.page.locator("text=Your take’s in").count()) > 0;
    assert(
      status || (await u.page.locator('[data-testid="global-stage"]').count()) > 0,
      "after posting, the composer is gone and the staging/status renders",
    );
    note += status
      ? "; posted a take → staging revealed + composer disabled"
      : "; posted a take → composer disabled (round advanced)";
  }
  return note;
}

// ── game mode ───────────────────────────────────────────────────────────────

// Quick chats now AUTO-ADVANCE both phases when everyone's done (proposing →
// rating when all submit/affirm/skip; rating → result when all vote). So we no
// longer force "End voting", and "Start voting" becomes best-effort: click it if
// the round is still proposing, skip if auto-advance already moved us to rating.
async function maybeStartVoting(page) {
  try {
    await page.waitForFunction(
      () => {
        const b = [...document.querySelectorAll("button")].find((x) =>
          x.textContent.includes("Start voting"),
        );
        return b && !b.disabled;
      },
      null,
      { timeout: 6000 },
    );
    await page.click('button:has-text("Start voting")');
  } catch {
    /* already auto-advanced to rating */
  }
}
// Create a GAME chat (the social "best ideas win" mode) via /create?game=1.
async function createGameChat(page, question) {
  await page.goto(BASE + "/create?game=1");
  await page.fill("textarea", question);
  await page.click('button:has-text("Start the game")');
  await page.waitForURL(/\/c\/[^_]/, { timeout: SHORT });
  return page.url().match(/\/c\/([^/]+)/)[1];
}

// The in-chat name gate (game mode): host and participant alike pick a name on
// entry. Returns once the gate has closed (load() re-rendered without it).
async function nameSelf(page, name) {
  await page.waitForSelector("input.name-input", { timeout: SHORT });
  await page.fill("input.name-input", name);
  await clickResilient(page, 'button:has-text("Join the game")');
  await page.waitForSelector("input.name-input", { state: "detached", timeout: SHORT });
}

// Assert we are NOT sitting on the round-2 "challenge the leader" screen. In
// INSTANT game mode a cycle is one round → winner → done, so LeaderChallenge
// (rendered only when roundNo >= 2) must never appear. Its tells: the "Round N
// result" header + the keep/replace gate (.leader .la / "keep or replace").
async function assertNoLeaderChallenge(page, whereMsg) {
  const r2 = await page.locator("text=Round 1 result").count();
  const gate2 = await page.locator(".leader .la").count();
  assert(
    r2 === 0 && gate2 === 0,
    `INSTANT mode must not show a round-2 leader-challenge screen (${whereMsg})`,
  );
}

// G) Game (INSTANT): name gate → group plays ONE round → the winner locks in
//    immediately (no round 2 / LeaderChallenge) → results show the per-game
//    LEADERBOARD + AUTHORSHIP and NO "How it converged" (single round) → host
//    "Next game" opens a topic vote → the group picks a topic → a fresh answer
//    game opens (the loop continues cleanly in instant mode).
async function gameInstant() {
  const host = await newUser();
  await gate("Hank creates the game");
  const code = await createGameChat(host.page, "Our group's hottest take?");
  await nameSelf(host.page, "Hank");
  // Game mode auto-starts the proposing round at creation (no seed dialog).
  await gate("Hank proposes 'Pineapple belongs on pizza'");
  await addIdea(host.page, "Pineapple belongs on pizza");

  const p2 = await newUser();
  await gate("Pat joins + proposes 'Cereal is a soup'");
  await open(p2.page, code);
  await nameSelf(p2.page, "Pat");
  await addIdea(p2.page, "Cereal is a soup");
  const p3 = await newUser();
  await gate("Quinn joins + proposes 'Hot dogs are sandwiches'");
  await open(p3.page, code);
  await nameSelf(p3.page, "Quinn");
  await addIdea(p3.page, "Hot dogs are sandwiches");

  const dbg = (s) => process.env.GDBG && console.log("   · " + s);
  await gate("Hank starts the voting");
  await maybeStartVoting(host.page);
  await gate("Hank votes");
  await vote(host.page);
  await gate("Pat votes");
  await vote(p2.page);
  await gate("Quinn votes");
  await vote(p3.page);
  // Rating auto-finalizes once everyone has voted. With confirmation_rounds=1 the
  // sole/tie winner completes the cycle → max_cycles=1 seals the chat → straight
  // to the locked-in result. There is NO round-2 challenge gate.
  await gate("ONE round → winner locks in (no round 2)");
  // Game mode is instant: results use reveal copy ("The group's pick"), NOT the
  // decision-mode convergence copy ("The group locked it in").
  await host.page.waitForSelector("text=The group's pick", { timeout: LONG });
  dbg("locked in after one round");

  // The core instant-mode assertion: no leader-challenge / round-2 screen ever
  // rendered — the result came directly from round 1.
  await assertNoLeaderChallenge(host.page, "host results");
  // Single round → the "How it converged" multi-round link must be ABSENT
  // (Results gates it on meta.rounds > 1).
  assert(
    (await host.page.locator('button:has-text("How it converged")').count()) === 0,
    "instant single-round game must NOT show a 'How it converged' link",
  );

  // Game-mode results still work: the per-game leaderboard + authorship reveal.
  await host.page.waitForSelector(".lb-head", { timeout: SHORT });
  assert(
    (await host.page.locator(".lb-row").count()) >= 1,
    "game leaderboard should list players",
  );
  // Authorship lives on the winner card (.ca-by "by <name>").
  assert(
    (await host.page.locator(".ca-by").count()) >= 1,
    "results should reveal authorship (by <name>)",
  );
  const anAuthor = (await text(host.page, ".ca-by")).trim();
  assert(
    /^by\s+\S/i.test(anAuthor),
    `authorship should read "by <name>", got "${anAuthor}"`,
  );

  // "Next game" (host) opens a TOPIC vote — the group proposes the next topic.
  // It reopens into a proposing round (propose a topic), no question input.
  await gate("Host opens Next game (topic vote)");
  await clickResilient(host.page, 'button:has-text("Next game")');
  await host.page.waitForSelector('textarea[placeholder^="Type your idea"]', {
    timeout: LONG,
  });

  // Drive the topic vote to a winner and confirm the NEXT answer game opens —
  // proving the instant loop continues cleanly (topic round is also single-round).
  await addIdea(host.page, "Best pizza topping");
  await open(p2.page, code);
  await addIdea(p2.page, "Best road-trip snack");
  await open(p3.page, code);
  await addIdea(p3.page, "Best movie of all time");
  await open(host.page, code);
  await maybeStartVoting(host.page);
  await vote(host.page);
  await open(p2.page, code);
  await vote(p2.page);
  await open(p3.page, code);
  await vote(p3.page);
  dbg("topic voted");

  // The winning topic becomes the next answer game's question → a fresh proposing
  // round opens (group proposes answers again). Confirm we're back to proposing,
  // NOT ended and NOT on a leader-challenge screen.
  await gate("Topic wins → next answer game opens (proposing)");
  await host.page.waitForSelector('textarea[placeholder^="Type your idea"]', {
    timeout: LONG,
  });
  await assertNoLeaderChallenge(host.page, "next answer game");
  assert(
    (await host.page.locator("text=The group's pick").count()) === 0,
    "the next answer game should be live (proposing), not already ended",
  );

  return "instant game locked in after ONE round (no leader-challenge); leaderboard + authorship shown; topic vote → next answer game opened";
}

// ── runner ────────────────────────────────────────────────────────────────

const PATHS = [
  ["global-chat", globalChat],
  ["game-instant", gameInstant],
  ["group-converge", groupConverge],
  ["challenger-beats-leader→R3", challengerBeatsLeader],
  ["poll-converge", pollConverge],
  ["all-affirm-no-autoresolve", allAffirmNoAutoResolve],
  ["live-update(polling)", liveUpdate],
  ["host-gating", hostGating],
  ["duplicate-prop", duplicateProp],
  ["tie-and-skip", tieAndSkip],
  ["not-found", notFound],
  ["reload-resume", reloadResume],
  ["two-person-no-vote", twoPersonNoVote],
];

async function main() {
  browser = await chromium.launch({ headless: !HEADED, slowMo: SLOWMO });
  const paths = ONLY ? PATHS.filter(([n]) => n.includes(ONLY)) : PATHS;
  for (const [name, fn] of paths) {
    const t0 = Date.now();
    try {
      const note = await fn();
      const dt = ((Date.now() - t0) / 1000).toFixed(1);
      results.push({ name, ok: true, note, dt });
      console.log(`✅ ${name} (${dt}s) — ${note}`);
    } catch (e) {
      const dt = ((Date.now() - t0) / 1000).toFixed(1);
      results.push({ name, ok: false, note: e.message, dt });
      console.log(`❌ ${name} (${dt}s) — ${e.message}`);
    }
  }
  await browser.close();
  const passed = results.filter((r) => r.ok).length;
  console.log(`\n${passed}/${results.length} paths passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
