# OneMind Token Economics (OMT)

> **Status: Not yet implemented.** This document describes the vision. The [User Ranking System](USER_RANKING.md) that feeds into this is already built.

## The Idea

Every consensus round mints **1 OMT per participant**. A round with 10 people creates 10 OMT. That pool is distributed unevenly based on each participant's [round rank](USER_RANKING.md) — better participation earns a larger share.

**Total OMT supply = total human participations across all rounds, ever.**

That's the only way tokens enter existence. No pre-mine, no investor allocation, no staking rewards. You earn OMT by participating in collective consensus. That's it.

## Why This Matters

In every existing economic model, capital generates more capital. If you have more, you earn more. OMT breaks that:

- A person holding 10,000 OMT earns the same ~1 OMT per round as someone holding zero
- There is no mechanism for wealth to compound
- The only way to have more is to have **participated more**
- Early participants have no structural advantage over late ones — the earning rate never changes

## Two Ways to Get OMT

1. **Participate in consensus rounds** — the only way new OMT is minted
2. **Trade goods or services for it in the marketplace** — earning OMT from others who already hold it

The first is how tokens enter existence. The second is how they circulate. Together they form an economy where the currency's value is not pegged to anything — it emerges from what people are willing to do for it. Pure market dynamics.

## How Earning Works

Round ranks (0–100) come from the [User Ranking System](USER_RANKING.md), which scores participants on:

- **Voting accuracy** — how well your rankings matched the final consensus
- **Proposing quality** — how well your propositions performed

Higher rank = larger share of the round's token pool. Everyone who participates earns something. The distribution rewards quality, but it's bounded — no one can earn orders of magnitude more than anyone else in a single round.
