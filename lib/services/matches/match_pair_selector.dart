import 'dart:math';

import '../../models/proposition.dart';

/// What a matches round is trying to produce.
enum MatchObjective {
  /// Surface the single top proposition in the fewest comparisons
  /// (single-elimination bracket: losers drop out).
  winnerOnly,

  /// Enough signal to rank ALL propositions (leveled "Swiss" passes:
  /// nobody is eliminated, everyone keeps playing in exposure-synced passes).
  fullRank,
}

/// One vote the current user has already cast this round.
/// [isTie] = the user judged them equal (no ordering signal; not an elimination).
/// [isSkip] = the user passed on the pair (no ordering signal, no elimination);
/// the pair still counts as faced + contributes to both props' exposure, so it
/// is never re-offered and the equal-exposure invariant still holds.
class PriorVote {
  const PriorVote({
    required this.winnerId,
    required this.loserId,
    this.isTie = false,
    this.isSkip = false,
  });
  final int winnerId;
  final int loserId;
  final bool isTie;
  final bool isSkip;
}

/// A pair to show the user. [top] is rendered above [bottom]; which proposition
/// lands on top is randomized to neutralize position bias.
/// [exposureBalanced] is false only in the rare last-resort case where no
/// equal-exposure pair was available and a difference of 1 was accepted — the
/// caller should log that so residual bias is observable.
class MatchPair {
  const MatchPair({
    required this.top,
    required this.bottom,
    required this.exposureBalanced,
  });
  final Proposition top;
  final Proposition bottom;
  final bool exposureBalanced;
}

/// Chooses the next pair to show a user, enforcing the **equal-exposure
/// invariant**: a match only ever pairs two propositions the user has seen the
/// same number of times before (no mere-exposure / novelty advantage). See
/// docs/MATCHES_RATING_MODE_SPEC.md §3.1.
///
/// Pure / stateless: every call derives everything from [rateable] +
/// [priorVotes], so it is trivially unit-testable and has no hidden state.
class MatchPairSelector {
  MatchPairSelector({Random? random, this.maxComparisons = 12})
      : _random = random ?? Random();

  final Random _random;

  /// Hard cap on comparisons per user per round (bounds full_rank on large
  /// rounds; winner_only converges well before this). When truncated, the
  /// caller should note the cap (silent truncation reads as "fully covered").
  final int maxComparisons;

  /// Returns the next pair to show, or null when the user is done
  /// (objective satisfied, no useful pair left, or budget hit).
  ///
  /// [rateable] must already EXCLUDE the user's own proposition(s).
  MatchPair? nextPair({
    required List<Proposition> rateable,
    required List<PriorVote> priorVotes,
    required MatchObjective objective,
  }) {
    if (rateable.length < 2) return null;
    if (priorVotes.length >= maxComparisons) return null;

    final byId = {for (final p in rateable) p.id: p};
    final ids = byId.keys.toList();

    // Per-user exposure (matches seen) + faced pairs + eliminated (lost a
    // non-tie match) — all derived from the user's prior votes.
    final exposure = {for (final id in ids) id: 0};
    final faced = <String>{};
    final eliminated = <int>{};
    for (final v in priorVotes) {
      if (exposure.containsKey(v.winnerId)) {
        exposure[v.winnerId] = exposure[v.winnerId]! + 1;
      }
      if (exposure.containsKey(v.loserId)) {
        exposure[v.loserId] = exposure[v.loserId]! + 1;
      }
      faced.add(_pairKey(v.winnerId, v.loserId));
      // Only a real, decisive vote eliminates the loser. Ties and skips carry
      // no ordering signal (but still count as faced + exposure above).
      if (!v.isTie && !v.isSkip) eliminated.add(v.loserId);
    }

    // winner_only: a loser drops out of contention. full_rank: everyone stays.
    final active = objective == MatchObjective.winnerOnly
        ? ids.where((id) => !eliminated.contains(id)).toList()
        : ids;

    if (objective == MatchObjective.winnerOnly && active.length <= 1) {
      return null; // a champion has emerged
    }

    // Collect unfaced pairs among active props, split by exposure relationship.
    // equalPairs: same exposure level (preferred — fully bias-free).
    // diffOnePairs: exposure differs by exactly 1 (last-resort fallback only).
    final equalPairs = <List<int>>[]; // [a, b, level]
    final diffOnePairs = <List<int>>[]; // [a, b, combinedExposure]
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        final a = active[i];
        final b = active[j];
        if (faced.contains(_pairKey(a, b))) continue;
        final ea = exposure[a]!;
        final eb = exposure[b]!;
        if (ea == eb) {
          equalPairs.add([a, b, ea]);
        } else if ((ea - eb).abs() == 1) {
          diffOnePairs.add([a, b, ea + eb]);
        }
      }
    }

    // Prefer the lowest exposure level (advance the bracket/pass bottom-up),
    // random tiebreak among equally-good candidates for coverage spread.
    final equal = _pickLowest(equalPairs);
    if (equal != null) return _buildPair(byId, equal[0], equal[1], true);

    final diffOne = _pickLowest(diffOnePairs);
    if (diffOne != null) return _buildPair(byId, diffOne[0], diffOne[1], false);

    return null; // nothing useful left → done
  }

  List<int>? _pickLowest(List<List<int>> pairs) {
    if (pairs.isEmpty) return null;
    pairs.sort((x, y) => x[2].compareTo(y[2]));
    final minKey = pairs.first[2];
    final tied = pairs.where((p) => p[2] == minKey).toList();
    return tied[_random.nextInt(tied.length)];
  }

  MatchPair _buildPair(
      Map<int, Proposition> byId, int a, int b, bool balanced) {
    final pa = byId[a]!;
    final pb = byId[b]!;
    final flip = _random.nextBool(); // randomize top/bottom (position bias)
    return MatchPair(
      top: flip ? pb : pa,
      bottom: flip ? pa : pb,
      exposureBalanced: balanced,
    );
  }

  String _pairKey(int a, int b) => a < b ? '$a:$b' : '$b:$a';
}
