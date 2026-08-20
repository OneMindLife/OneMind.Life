import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/services/matches/match_pair_selector.dart';

import '../../fixtures/proposition_fixtures.dart';

/// Build N rateable propositions with ids 1..N.
List<Proposition> props(int n) =>
    [for (var i = 1; i <= n; i++) PropositionFixtures.model(id: i, content: 'P$i')];

String key(int a, int b) => a < b ? '$a:$b' : '$b:$a';

/// Drive the selector to completion. [winnerOf] decides the winner of a pair
/// (default: the lower id). Returns the ordered list of pairs shown.
List<MatchPair> runToCompletion(
  MatchPairSelector selector,
  List<Proposition> rateable,
  MatchObjective objective, {
  int Function(int a, int b)? winnerOf,
  bool tieEvery = false,
}) {
  final votes = <PriorVote>[];
  final shown = <MatchPair>[];
  while (true) {
    final pair = selector.nextPair(
      rateable: rateable,
      priorVotes: votes,
      objective: objective,
    );
    if (pair == null) break;
    shown.add(pair);
    final a = pair.top.id;
    final b = pair.bottom.id;
    final w = tieEvery ? a : (winnerOf?.call(a, b) ?? min(a, b));
    final l = w == a ? b : a;
    votes.add(PriorVote(winnerId: w, loserId: l, isTie: tieEvery));
    if (shown.length > 200) {
      fail('selector did not converge (${objective.name})');
    }
  }
  return shown;
}

void main() {
  group('MatchPairSelector', () {
    test('returns null when fewer than 2 rateable propositions', () {
      final s = MatchPairSelector(random: Random(1));
      expect(
        s.nextPair(rateable: props(1), priorVotes: const [], objective: MatchObjective.winnerOnly),
        isNull,
      );
      expect(
        s.nextPair(rateable: const [], priorVotes: const [], objective: MatchObjective.winnerOnly),
        isNull,
      );
    });

    test('never shows a proposition against itself / never repeats a faced pair', () {
      final s = MatchPairSelector(random: Random(7));
      final p = props(5);
      final shown = runToCompletion(s, p, MatchObjective.fullRank);
      final seen = <String>{};
      for (final m in shown) {
        expect(m.top.id, isNot(m.bottom.id), reason: 'a pair must be two distinct props');
        final k = key(m.top.id, m.bottom.id);
        expect(seen.contains(k), isFalse, reason: 'pair $k was shown twice');
        seen.add(k);
      }
    });

    test('winner_only: converges in exactly n-1 comparisons (single elimination)', () {
      for (final n in [2, 4, 8]) {
        final s = MatchPairSelector(random: Random(42));
        final shown = runToCompletion(s, props(n), MatchObjective.winnerOnly);
        expect(shown.length, n - 1, reason: 'winner_only with $n props should take n-1 matches');
      }
    });

    test('winner_only with power-of-2 count: every match is exposure-balanced', () {
      for (final n in [2, 4, 8]) {
        final s = MatchPairSelector(random: Random(99));
        final shown = runToCompletion(s, props(n), MatchObjective.winnerOnly);
        for (final m in shown) {
          expect(m.exposureBalanced, isTrue,
              reason: 'n=$n bracket should never need an unequal-exposure pair');
        }
      }
    });

    test('winner_only: a proposition that loses is never shown again (eliminated)', () {
      // Champion = id 1 always wins; everyone else loses once and is out.
      final s = MatchPairSelector(random: Random(3));
      final p = props(4);
      final votes = <PriorVote>[];
      final appearancesAfterLoss = <int, int>{};
      final lost = <int>{};
      while (true) {
        final pair = s.nextPair(rateable: p, priorVotes: votes, objective: MatchObjective.winnerOnly);
        if (pair == null) break;
        final a = pair.top.id, b = pair.bottom.id;
        for (final id in [a, b]) {
          if (lost.contains(id)) {
            appearancesAfterLoss[id] = (appearancesAfterLoss[id] ?? 0) + 1;
          }
        }
        final w = (a == 1 || b == 1) ? 1 : min(a, b);
        final l = w == a ? b : a;
        votes.add(PriorVote(winnerId: w, loserId: l));
        lost.add(l);
      }
      expect(appearancesAfterLoss, isEmpty, reason: 'eliminated props must not reappear');
    });

    test('full_rank: no elimination — covers all distinct pairs, all balanced (n=4)', () {
      final s = MatchPairSelector(random: Random(11));
      final shown = runToCompletion(s, props(4), MatchObjective.fullRank);
      // 4 props → C(4,2)=6 distinct pairs, all reachable at equal exposure.
      expect(shown.length, 6);
      for (final m in shown) {
        expect(m.exposureBalanced, isTrue);
      }
    });

    test('full_rank explores more comparisons than winner_only', () {
      final wo = runToCompletion(
          MatchPairSelector(random: Random(5)), props(6), MatchObjective.winnerOnly);
      final fr = runToCompletion(
          MatchPairSelector(random: Random(5)), props(6), MatchObjective.fullRank);
      expect(fr.length, greaterThan(wo.length));
    });

    test('respects the maxComparisons budget cap', () {
      final s = MatchPairSelector(random: Random(2), maxComparisons: 3);
      final shown = runToCompletion(s, props(8), MatchObjective.fullRank);
      expect(shown.length, lessThanOrEqualTo(3));
    });

    test('odd count: falls back to an exposure-diff-of-1 pair, flagged unbalanced', () {
      // n=3 winner_only: round 1 pairs two (both →1), the third sits at 0.
      // The next match must pair across a 1-level exposure gap → last resort.
      final s = MatchPairSelector(random: Random(1));
      final shown = runToCompletion(s, props(3), MatchObjective.winnerOnly);
      expect(shown.length, 2, reason: 'n=3 single-elim still resolves in n-1=2');
      expect(shown.any((m) => !m.exposureBalanced), isTrue,
          reason: 'the bye forces one unequal-exposure (diff-1) match, flagged');
    });

    test('skip: a skipped pair is never returned again', () {
      final s = MatchPairSelector(random: Random(13));
      final p = props(4);
      // User skips the pair {1,2} up front.
      final votes = <PriorVote>[
        const PriorVote(winnerId: 1, loserId: 2, isSkip: true),
      ];
      final shown = <MatchPair>[];
      while (true) {
        final pair =
            s.nextPair(rateable: p, priorVotes: votes, objective: MatchObjective.fullRank);
        if (pair == null) break;
        shown.add(pair);
        final a = pair.top.id, b = pair.bottom.id;
        votes.add(PriorVote(winnerId: min(a, b), loserId: max(a, b)));
        if (shown.length > 200) fail('did not converge');
      }
      expect(shown.any((m) => key(m.top.id, m.bottom.id) == key(1, 2)), isFalse,
          reason: 'the skipped pair {1,2} must never be re-offered');
    });

    test('skip: increments exposure for both props so the invariant still holds', () {
      // n=4 full_rank, all 6 pairs reachable. If we skip {1,2}, then props 1 and
      // 2 each sit at exposure 1 while 3 and 4 sit at 0 — the very next pair must
      // be the equal-exposure {3,4} (level 0), never an unbalanced one.
      final s = MatchPairSelector(random: Random(21));
      final votes = <PriorVote>[
        const PriorVote(winnerId: 1, loserId: 2, isSkip: true),
      ];
      final next = s.nextPair(
          rateable: props(4), priorVotes: votes, objective: MatchObjective.fullRank);
      expect(next, isNotNull);
      expect(key(next!.top.id, next.bottom.id), key(3, 4),
          reason: 'skip lifted {1,2} to exposure 1; the level-0 pair {3,4} comes next');
      expect(next.exposureBalanced, isTrue);

      // And driving to completion from a skip still covers every remaining pair
      // at equal exposure (the skip contributed exposure exactly like a vote).
      final all = <MatchPair>[];
      final v2 = <PriorVote>[const PriorVote(winnerId: 1, loserId: 2, isSkip: true)];
      while (true) {
        final pair =
            s.nextPair(rateable: props(4), priorVotes: v2, objective: MatchObjective.fullRank);
        if (pair == null) break;
        all.add(pair);
        for (final m in all) {
          expect(m.exposureBalanced, isTrue,
              reason: 'every offered pair must respect equal exposure');
        }
        final a = pair.top.id, b = pair.bottom.id;
        v2.add(PriorVote(winnerId: min(a, b), loserId: max(a, b)));
        if (all.length > 200) fail('did not converge');
      }
      // 6 total pairs minus the 1 pre-skipped = 5 remaining offered pairs.
      expect(all.length, 5);
    });

    test('skip: does not crown a winner (no elimination in winner_only)', () {
      // winner_only with n=2: if the only pair is SKIPPED, neither prop is
      // eliminated, the (sole) pair is now faced, so there is nothing left to
      // offer → null, but crucially active.length stays 2 (no champion crowned).
      final s = MatchPairSelector(random: Random(4));
      final votes = <PriorVote>[
        const PriorVote(winnerId: 1, loserId: 2, isSkip: true),
      ];
      final next = s.nextPair(
          rateable: props(2), priorVotes: votes, objective: MatchObjective.winnerOnly);
      expect(next, isNull, reason: 'the only pair was skipped → nothing left to offer');

      // Contrast: a real vote on {1,2} eliminates 2 — also null, but for a
      // different reason. The point of this test is the skip path produced no
      // elimination, which we verify indirectly: with n=3 and one prop skipped
      // against another, the loser of the skip is still eligible to be paired.
      final s3 = MatchPairSelector(random: Random(8));
      final v3 = <PriorVote>[const PriorVote(winnerId: 1, loserId: 2, isSkip: true)];
      final after = s3.nextPair(
          rateable: props(3), priorVotes: v3, objective: MatchObjective.winnerOnly);
      expect(after, isNotNull,
          reason: 'prop 2 was skipped (not eliminated) so it can still be paired');
      // The next pair must involve prop 3 (the only one at exposure 0) and one
      // of 1/2 (both at exposure 1) — i.e. prop 2 is still active.
      final ids = {after!.top.id, after.bottom.id};
      expect(ids.contains(3), isTrue);
    });

    test('skip: when all useful pairs are skipped/seen, nextPair returns null', () {
      // n=3 full_rank: pre-record all 3 pairs as skips → fully faced, nothing left.
      final s = MatchPairSelector(random: Random(2));
      final votes = <PriorVote>[
        const PriorVote(winnerId: 1, loserId: 2, isSkip: true),
        const PriorVote(winnerId: 1, loserId: 3, isSkip: true),
        const PriorVote(winnerId: 2, loserId: 3, isSkip: true),
      ];
      final next = s.nextPair(
          rateable: props(3), priorVotes: votes, objective: MatchObjective.fullRank);
      expect(next, isNull);
    });

    test('position is randomized across many pairings (no fixed top/bottom)', () {
      // Same first pair drawn repeatedly with different RNG → both orderings appear.
      final p = props(2);
      final tops = <int>{};
      for (var seed = 0; seed < 30; seed++) {
        final m = MatchPairSelector(random: Random(seed))
            .nextPair(rateable: p, priorVotes: const [], objective: MatchObjective.winnerOnly)!;
        tops.add(m.top.id);
      }
      expect(tops, containsAll([1, 2]), reason: 'top card should not be fixed to one side');
    });
  });
}
