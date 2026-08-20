import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// A ranked list of options, best-first — the shared "how the group ranked
/// them" leaderboard used by the value-first demo (`/try`) and by real
/// matches-mode chat results, so both deliver the same payoff.
///
/// [entries] is ordered best-first; index 0 is the winner (highlighted in
/// [AppColors.consensus] with a trophy). Renders a non-scrolling Column
/// (`mainAxisSize.min`) — wrap it in your own scroll view.
class RankedLeaderboard extends StatelessWidget {
  const RankedLeaderboard({super.key, required this.entries});

  /// Option labels, best-first. Index 0 is treated as the winner.
  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++)
          _RankRow(rank: i + 1, text: entries[i], isWinner: i == 0),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.text,
    required this.isWinner,
  });

  final int rank;
  final String text;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          // Match the voting card (PropositionContentCard / matches _OptionCard):
          // same surface fill + rating-colored 1.5 border, so a finished survey's
          // ranked cards read as the very cards the user was tapping, now ordered.
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isWinner
                ? AppColors.consensus
                : AppColors.rating.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(
              '$rank',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isWinner ? AppColors.consensus : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isWinner)
              Icon(Icons.emoji_events, size: 18, color: AppColors.consensus),
          ],
        ),
      ),
    );
  }
}
