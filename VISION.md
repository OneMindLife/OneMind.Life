# OneMind Vision

## What OneMind Is

OneMind is infrastructure for groups of humans to think together — to converge on ideas through structured, anonymous deliberation rather than debate, voting, or authority.

Individual voices don't disappear. They become part of a collective output that no single person could produce alone.

## How It Works

1. **Proposing** — participants submit ideas anonymously
2. **Rating** — everyone ranks propositions on a grid
3. **Consensus** — the [MOVDA algorithm](USER_RANKING.md) computes global scores from pairwise comparisons
4. **Rounds** — repeat, refining the collective output each time
5. **Survival** — a proposition that wins consecutive rounds is consensus

What survives isn't necessarily "truth" — it's what the collective couldn't kill. Each person votes using their own criteria: truth, beauty, peace, utility, resonance. What passes through all these filters simultaneously is stronger than any single criterion could produce.

## The Novelty Bias Discovery

OneMind originally used a match-based slider system where propositions were compared in chain-linked pairs (A vs B, then B vs C). A bug was found — users consistently preferred the proposition they hadn't seen yet. In match 2, they'd already seen B from match 1, so they'd slide toward C. The team prepared to fix it. Then they realized it wasn't a bug.

The system has since moved to grid rating, so the within-round novelty bias no longer applies. But it still operates across rounds: a winning proposition carried forward to the next round has already been seen by participants. It has to overcome that familiarity disadvantage to win again. Only genuinely strong ideas survive consecutive rounds — that's what makes consensus meaningful.

## Design Principles

**Truth over identity.** Ideas are evaluated on merit, not status. Anonymous, equal-weighted rating prevents identity from corrupting selection.

**Calm, not chaos.** No outrage incentives, no attention economy. Thoughtful participation is the point.

**Universal participation.** Anyone, anywhere. Works across cultures, languages, and contexts.

**Never finished.** OneMind evolves through participation. No equilibrium state — continuous evolution.

## What OneMind Aims to Be

The vision is for OneMind to function as a collective thinking layer for humanity — a way for any group, from a classroom to the entire planet, to converge on ideas together.

Current decision-making systems have known limitations:
- Democracy takes snapshots rather than tracking evolving consensus
- Majority rule silences minorities
- Positions are fixed rather than iteratively refined
- Human bias is treated as a problem to eliminate rather than a force to channel

OneMind attempts to address these through continuous participation, iterative refinement, and consensus through competition. The goal is decisions like climate agreements, safety standards, or conflict resolution emerging from collective intelligence rather than top-down negotiation.

## The Natural Laws It Channels

OneMind is built around five observed dynamics:

1. **Attention Conservation** — human attention flows toward maximum uncertainty, allocating cognitive resources without central direction
2. **Selection Pressure** — ideas compete for survival; quality emerges through natural selection, with novelty bias as the mutation rate
3. **Information Compression** — diverse inputs converge to singular output through iterative consensus
4. **Talent Flow** — talent flows toward the problems that matter most rather than the ones that pay most
5. **Collective Mirror** — the system surfaces collective intelligence that exists within a group but can't be accessed by individuals alone

## Token Economics

The [token model](TOKEN_ECONOMICS.md) is designed so wealth cannot compound:

- Every consensus round mints **1 OMT per participant** — the only way tokens enter existence
- No pre-mine, no investor allocation, no staking rewards
- A person holding 10,000 OMT earns the same ~1 OMT per round as someone holding zero
- Early participants have no structural advantage over late ones
- The only way to have more is to have **participated more**

Two ways to get OMT: participate in consensus rounds (minting new tokens) or trade goods and services in the marketplace (circulating existing ones). The currency's value emerges from what people are willing to do for it.

## Self-Sustaining Model

OneMind is designed to sustain itself without external funding or advertising:

1. **Self-funding through tokenomics** — the token economy funds growth through participation itself
2. **Self-directing evolution** — development priorities determined by the platform's own collective intelligence
3. **Singular global conversation** — one worldwide dialogue rather than fragmented communities

The marketplace enables participants to exchange goods and services for OMT, creating a real economy backed by participation rather than speculation.

## The Longer-Term Vision

OneMind's ambition is to become how humanity coordinates on hard problems — from local community decisions to species-level challenges. Not a government imposed from above, but a thinking process that emerges from below.

If it works as intended:
- Governance becomes an expression of collective intelligence rather than something imposed on it
- Economic incentives align with contribution rather than accumulation
- Talent flows toward the problems that matter most rather than the ones that pay most
- Any group, anywhere, can converge on shared direction

That's the bet. Whether it delivers is up to the people who participate.

---

## Further Reading

| Document | Description |
|----------|-------------|
| [Token Economics](TOKEN_ECONOMICS.md) | How OMT creates a non-compounding participation economy |
| [User Ranking](USER_RANKING.md) | How contribution quality is measured |
| [Consensus Output](CONSENSUS_OUTPUT.md) | Real consensus results from OneMind |
| [Agent API](supabase/functions/AGENT_API.md) | How AI agents participate alongside humans |
