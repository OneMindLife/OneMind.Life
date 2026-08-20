import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/proposition.dart';
import '../../widgets/tts_button.dart';

/// Matches-mode round results: the propositions for a finished round, ranked
/// best-first, each on its own card. This is the matches counterpart to the
/// 0–100 grid shown for `ratingMode == 'grid'` chats.
///
/// [propositions] arrive pre-sorted descending by score (the proposition
/// service does this), so list order IS the ranking — index 0 is the winner.
/// Styling mirrors [RankedLeaderboard]/the voting card: a `surface` fill with
/// a rating-colored 1.5 border, the winner promoted to [AppColors.consensus]
/// with a trophy, so a finished survey's ranked cards read as the very cards
/// the user was tapping, now ordered and scored.
class MatchesResultsView extends StatelessWidget {
  const MatchesResultsView({
    super.key,
    required this.propositions,
    this.chatId,
    this.cycleId,
  });

  /// Propositions for the round, pre-sorted best-first.
  final List<Proposition> propositions;

  /// Analytics context for the per-card read-aloud button. When both [chatId]
  /// and the card's `source` are set, tapping logs `chat_audio_played`.
  final String? chatId;

  /// Cycle id, threaded into the read-aloud analytics event.
  final int? cycleId;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: propositions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _MatchesResultCard(
        rank: index + 1,
        proposition: propositions[index],
        isWinner: index == 0,
        chatId: chatId,
        cycleId: cycleId,
      ),
    );
  }
}

class _MatchesResultCard extends StatelessWidget {
  const _MatchesResultCard({
    required this.rank,
    required this.proposition,
    required this.isWinner,
    this.chatId,
    this.cycleId,
  });

  final int rank;
  final Proposition proposition;
  final bool isWinner;
  final String? chatId;
  final int? cycleId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isWinner ? AppColors.consensus : AppColors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$rank',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  proposition.displayContent,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight:
                        isWinner ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (isWinner) ...[
            const SizedBox(width: 8),
            Icon(Icons.emoji_events, size: 18, color: AppColors.consensus),
          ],
          const SizedBox(width: 4),
          TtsButton(
            text: proposition.displayContent,
            source: 'cycle_winner',
            chatId: chatId,
            cycleId: cycleId,
          ),
        ],
      ),
    );
  }
}
