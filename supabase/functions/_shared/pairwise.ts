/**
 * Score → pairwise-vote conversion for matches-mode chats.
 *
 * Agents rate with a 0-100 score per proposition (one LLM call / one SDK
 * request), but a matches-mode round is decided by pairwise_comparisons rows —
 * the same match-by-match votes humans cast. This converts a score map into
 * one row per unordered pair: winner = higher score, equal scores = tie.
 *
 * Derived votes are transitively consistent by construction (no A>B>C>A
 * cycles), which is the same property game-ai-voter gets from expanding a
 * ranking. MOVDA consumes the rows identically to human votes.
 */

export interface ScoredProposition {
  propositionId: number;
  score: number;
}

export interface PairwiseRow {
  round_id: number;
  participant_id: number;
  winner_proposition_id: number;
  loser_proposition_id: number;
  is_tie: boolean;
  is_skip: boolean;
}

export function scoresToPairwiseRows(
  scored: ScoredProposition[],
  roundId: number,
  participantId: number
): PairwiseRow[] {
  const rows: PairwiseRow[] = [];
  for (let i = 0; i < scored.length; i++) {
    for (let j = i + 1; j < scored.length; j++) {
      const a = scored[i];
      const b = scored[j];
      // Ties keep a deterministic winner/loser order (the schema requires
      // distinct winner != loser even for ties); is_tie carries the meaning.
      const [winner, loser] =
        b.score > a.score ? [b, a] : [a, b];
      rows.push({
        round_id: roundId,
        participant_id: participantId,
        winner_proposition_id: winner.propositionId,
        loser_proposition_id: loser.propositionId,
        is_tie: a.score === b.score,
        is_skip: false,
      });
    }
  }
  return rows;
}
