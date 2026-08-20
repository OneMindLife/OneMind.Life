import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_colors.dart';
import '../../models/proposition.dart';
import '../../providers/providers.dart';
import '../../services/matches/match_pair_selector.dart';
import '../../widgets/ranked_leaderboard.dart';

/// Zero-friction, hardcoded "value-first" demo — the new landing-CTA entry point.
///
/// Why hardcoded content (no live agents / LLM / backend chat): the live agented
/// preview produced jargony, near-duplicate ideas + creation latency +
/// confirmation-dialog friction (dogfooded 2026-06-01). Curated options are
/// instant, deterministic, free, and show the convergence at its best.
///
/// Why the REAL match logic: pairing is driven by the production
/// [MatchPairSelector] in `fullRank` mode (leveled-Swiss passes) — the same
/// adaptive, equal-exposure algorithm the real app uses, so every option gets a
/// fair number of equal-exposure comparisons and we can show a true ranked
/// leaderboard (not just a winner). Pure client-side, so this stays backend-free.
///
/// Flow: land straight in the vote (tap-first) → ~6 adaptive pairwise taps →
/// the group's full ranking (1st–4th) → offer "run this with your own group".
class DemoVoteScreen extends ConsumerStatefulWidget {
  const DemoVoteScreen({super.key});

  @override
  ConsumerState<DemoVoteScreen> createState() => _DemoVoteScreenState();
}

class _DemoVoteScreenState extends ConsumerState<DemoVoteScreen>
    with SingleTickerProviderStateMixin {
  // ── Curated demo content (work/team context — matches ad intent). ──
  // Four options → full_rank covers all 6 pairs (~6 taps) for a fair leaderboard.
  static const String _question = "What's the best perk to add at work?";
  static const List<String> _optionTexts = [
    'A four-day work week',
    'Work from anywhere',
    'Better health insurance',
    'Unlimited PTO',
  ];

  late final List<Proposition> _items;
  final MatchPairSelector _selector = MatchPairSelector();
  final List<PriorVote> _votes = [];
  MatchPair? _pair;
  List<Proposition>? _results;

  /// Gentle "breathing" pulse on BOTH option cards until the first vote — an
  /// affordance cue that the cards are tappable, without privileging either
  /// choice (we can't animate a directed tap on a two-equal-options screen
  /// without biasing it). Stopped on first interaction (see [_record]).
  late final AnimationController _pulseController;
  bool get _showPulse => _votes.isEmpty;

  @override
  void initState() {
    super.initState();
    final created = DateTime(2026, 6, 1);
    _items = [
      for (var i = 0; i < _optionTexts.length; i++)
        Proposition(
          id: i,
          roundId: 0,
          content: _optionTexts[i],
          createdAt: created,
        ),
    ];
    _pair = _nextPair();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    ref.read(analyticsServiceProvider).logDemoOpened();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  MatchPair? _nextPair() => _selector.nextPair(
        rateable: _items,
        priorVotes: _votes,
        objective: MatchObjective.fullRank,
      );

  void _record(PriorVote vote) {
    // First interaction → the affordance cue has done its job; stop pulsing.
    if (_pulseController.isAnimating) _pulseController.stop();
    _votes.add(vote);
    final next = _nextPair();
    if (next == null) {
      final ranked = _computeRanking();
      ref
          .read(analyticsServiceProvider)
          .logDemoCompleted(winner: ranked.first.content);
      setState(() {
        _results = ranked;
        _pair = null;
      });
    } else {
      setState(() => _pair = next);
    }
  }

  void _pick(Proposition chosen) {
    final pair = _pair!;
    final other = chosen.id == pair.top.id ? pair.bottom : pair.top;
    ref.read(analyticsServiceProvider).logDemoVoted(step: _votes.length + 1);
    _record(PriorVote(winnerId: chosen.id, loserId: other.id));
  }

  void _equal() {
    final pair = _pair!;
    _record(PriorVote(
      winnerId: pair.top.id,
      loserId: pair.bottom.id,
      isTie: true,
    ));
  }

  /// Rank every option by the user's votes: decisive wins desc, then losses asc,
  /// then stable order. full_rank's exposure-synced passes give every option
  /// enough comparisons for this to be a fair ordering.
  List<Proposition> _computeRanking() {
    final wins = {for (final p in _items) p.id: 0};
    final losses = {for (final p in _items) p.id: 0};
    for (final v in _votes) {
      if (!v.isTie && !v.isSkip) {
        wins[v.winnerId] = wins[v.winnerId]! + 1;
        losses[v.loserId] = losses[v.loserId]! + 1;
      }
    }
    final ranked = List<Proposition>.of(_items);
    ranked.sort((a, b) {
      final byWins = wins[b.id]!.compareTo(wins[a.id]!);
      if (byWins != 0) return byWins;
      final byLosses = losses[a.id]!.compareTo(losses[b.id]!);
      if (byLosses != 0) return byLosses;
      return a.id.compareTo(b.id);
    });
    return ranked;
  }

  void _createReal() {
    ref.read(analyticsServiceProvider).logDemoCreateClicked();
    context.go('/create');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // Wordmark + a group-size count so the demo reads like a real
        // quick chat (the destination it hands off to). The count is fixed
        // (this is a hardcoded preview — no real participants) and matches
        // the number shown in the landing hero's vote shot. No Invite / no
        // host controls: the viewer isn't a host here.
        title: Text(
          'OneMind',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(Icons.groups,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('6', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _results != null
                        ? _buildResults(theme)
                        : _buildVote(theme),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Voting step (tap-first, adaptive pairs) ──
  Widget _buildVote(ThemeData theme) {
    final pair = _pair!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "A 20-second example of how OneMind ranks ideas — "
          "you'll run your own next.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),
        _questionCard(theme),
        const SizedBox(height: 28),
        Text(
          'Which is better? Tap one.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        _maybePulse(_optionCard(theme, pair.top.content, () => _pick(pair.top),
            key: const Key('demo-top'))),
        _vsBadge(theme),
        _maybePulse(_optionCard(
            theme, pair.bottom.content, () => _pick(pair.bottom),
            key: const Key('demo-bottom'))),
        const SizedBox(height: 16),
        _equalButton(theme),
        const SizedBox(height: 28),
        Text(
          'A few quick taps and the group ranks every idea.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _questionCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.seed.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Text(
            'The group is deciding',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            _question,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _optionCard(ThemeData theme, String text, VoidCallback onTap,
      {Key? key}) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            // A light fill (not just an outline) so the card reads as a
            // pressable button, not a label.
            color: AppColors.rating.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.rating.withValues(alpha: 0.8)),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ),
    );
  }

  /// Wraps an option card in the pre-first-vote affordance pulse (gentle scale
  /// + glow on both cards in sync). After the first vote it's a no-op.
  Widget _maybePulse(Widget child) {
    if (!_showPulse) return child;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, c) {
        final t = Curves.easeInOut.transform(_pulseController.value);
        return Transform.scale(
          scale: 1.0 + 0.03 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.rating.withValues(alpha: 0.30 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 1.0 * t,
                ),
              ],
            ),
            child: c,
          ),
        );
      },
      child: child,
    );
  }

  /// Small "VS" badge between the two cards — signals "pick one of these two"
  /// at a glance, before any reading.
  Widget _vsBadge(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(color: AppColors.rating.withValues(alpha: 0.4)),
          ),
          child: Text(
            'VS',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _equalButton(ThemeData theme) {
    return TextButton.icon(
      onPressed: _equal,
      icon: const Icon(Icons.balance, size: 18),
      label: const Text('Equal'),
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    );
  }

  // ── Ranked leaderboard reveal ──
  Widget _buildResults(ThemeData theme) {
    final ranked = _results!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events, size: 36, color: AppColors.consensus),
        const SizedBox(height: 12),
        Text(
          "Here's how the group ranked them",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        RankedLeaderboard(
          entries: [for (final p in ranked) p.content],
        ),
        const SizedBox(height: 18),
        Text(
          'That\'s OneMind: everyone submits ideas, rates them fairly, and the '
          'best ones rise — no loudest-voice-wins.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _createReal,
            icon: const Icon(Icons.add),
            label: const Text('Create your own decision'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'You pick the question and the options (or let your group add them), '
          'share a link, and everyone ranks — you get an answer like this one.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
