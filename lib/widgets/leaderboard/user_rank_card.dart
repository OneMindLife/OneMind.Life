import 'package:flutter/material.dart';
import '../../models/user_round_rank.dart';

/// Card widget displaying a user's rank on the leaderboard grid.
///
/// Shows user name, rank score, "(You)" indicator for current user,
/// and a trophy icon for the winner.
class UserRankCard extends StatelessWidget {
  final UserRoundRank userRank;
  final bool isCurrentUser;
  final bool isWinner;

  const UserRankCard({
    super.key,
    required this.userRank,
    this.isCurrentUser = false,
    this.isWinner = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: isWinner ? 4 : 2,
      color: isWinner
          ? colorScheme.primaryContainer
          : isCurrentUser
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isWinner
            ? BorderSide(color: Colors.amber.shade600, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Trophy icon for winner
            if (isWinner) ...[
              Icon(
                Icons.emoji_events,
                color: Colors.amber.shade700,
                size: 20,
              ),
              const SizedBox(width: 6),
            ],
            // User name and (You) indicator
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          userRank.displayName ?? 'Unknown',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isWinner || isCurrentUser ? FontWeight.bold : null,
                            color: isWinner
                                ? colorScheme.onPrimaryContainer
                                : isCurrentUser
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(You)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSecondaryContainer
                                .withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Rank score
                  Text(
                    'Score: ${userRank.rank.toStringAsFixed(1)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isWinner
                          ? colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                          : isCurrentUser
                              ? colorScheme.onSecondaryContainer.withValues(alpha: 0.8)
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
