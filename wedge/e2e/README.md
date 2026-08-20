# Wedge end-to-end suite

A multi-context Playwright harness. Each browser **context is a separate
anonymous Supabase user**, so it drives the real host + participants flows (no
localStorage hacks) and — because the wedge auto-refreshes (3s polling) — also
exercises live cross-client updates.

## Run

```bash
# 1. dev server up (points at prod Supabase via .env.local)
npm run dev          # localhost:3000

# 2. in another shell
npm run e2e
# or against a deploy:
BASE=https://onemind.life npm run e2e
```

Exit code is non-zero if any path fails. Reuses the Playwright + chromium
already installed under `tools/load-sim/` (no extra install).

## What it covers

| Path | Asserts |
|------|---------|
| group-converge | full group flow → leader wins R1 + R2 → converged; history lists rounds |
| challenger-beats-leader→R3 | a challenger winning R2 opens a fresh round with it as the new leader (re-convergence, not sealed) |
| poll-converge | host-provided options → R1 → R2 challenge → locked in |
| all-affirm-no-autoresolve | "No, this is the one" counts as a response; an all-affirm quick room does NOT auto-resolve |
| live-update(polling) | a participant's new idea appears on the host screen without a reload |
| host-gating | participant can't advance (sees wait state); host has the control |
| duplicate-prop | a repeated idea is rejected with the "already added" message |
| tie-and-skip | "Equal" + "Skip this pair" still drive the round to done |
| not-found | unknown code → not-found screen |
| reload-resume | a submitted idea persists across a reload |

> Creates real chats on prod Supabase (test data — safe to delete).
