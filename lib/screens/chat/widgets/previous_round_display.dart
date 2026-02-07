import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../../../widgets/proposition_content_card.dart';
import '../../rating/read_only_results_screen.dart';

/// Displays the previous round winner(s) with support for tied winners.
class PreviousWinnerPanel extends StatelessWidget {
  final List<RoundWinner> previousRoundWinners;
  final int currentWinnerIndex;
  final bool isSoleWinner;
  final int consecutiveSoleWins;
  final int confirmationRoundsRequired;
  final int? currentRoundCustomId;
  final void Function(int) onWinnerIndexChanged;

  /// When true, shows a "See Results" button that opens the grid view
  final bool showResultsButton;

  /// All propositions from the previous round (needed for grid view)
  final List<Proposition>? previousRoundResults;

  /// Current user's participant ID (for leaderboard display)
  final int? myParticipantId;

  /// Previous round ID (for leaderboard data fetching)
  final int? previousRoundId;

  /// Previous round number (1-indexed) for display purposes
  final int? previousRoundNumber;

  /// Callback when user views the results grid and returns
  final VoidCallback? onResultsViewed;

  /// Whether to show tutorial hint on the results screen
  final bool showTutorialHintOnResults;

  const PreviousWinnerPanel({
    super.key,
    required this.previousRoundWinners,
    required this.currentWinnerIndex,
    required this.isSoleWinner,
    required this.consecutiveSoleWins,
    required this.confirmationRoundsRequired,
    required this.currentRoundCustomId,
    required this.onWinnerIndexChanged,
    this.showResultsButton = false,
    this.previousRoundResults,
    this.myParticipantId,
    this.previousRoundId,
    this.previousRoundNumber,
    this.onResultsViewed,
    this.showTutorialHintOnResults = false,
  });

  void _navigateToResultsGrid(BuildContext context) {
    if (previousRoundResults == null || previousRoundResults!.isEmpty) return;

    // Use explicit previousRoundNumber if provided, otherwise calculate from currentRoundCustomId
    final roundNum = previousRoundNumber ?? ((currentRoundCustomId ?? 2) - 1);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReadOnlyResultsScreen(
          propositions: previousRoundResults!,
          roundNumber: roundNum,
          roundId: previousRoundId,
          myParticipantId: myParticipantId,
          showTutorialHint: showTutorialHintOnResults,
        ),
      ),
    ).then((_) {
      // Call the callback when user returns from grid view
      onResultsViewed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (previousRoundWinners.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Text(l10n.noPreviousWinner),
      );
    }

    final hasMultipleWinners = previousRoundWinners.length > 1;
    final currentWinner = previousRoundWinners[currentWinnerIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tie indicator (only shown for multiple winners)
          if (hasMultipleWinners) ...[
            TieBadge(count: previousRoundWinners.length),
            const SizedBox(height: 8),
          ],

          // Winner index (for multiple winners)
          if (hasMultipleWinners)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${currentWinnerIndex + 1} of ${previousRoundWinners.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),

          // Winner card with navigation arrows
          Row(
            children: [
              // Left arrow (for multiple winners)
              if (hasMultipleWinners)
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: currentWinnerIndex > 0
                      ? () => onWinnerIndexChanged(currentWinnerIndex - 1)
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 24,
                ),

              // Winner content using PropositionContentCard
              Expanded(
                child: PropositionContentCard(
                  content: currentWinner.displayContent ?? l10n.unknownProposition,
                  maxHeight: 100,
                  borderColor: hasMultipleWinners ? Colors.orange.shade300 : null,
                  borderWidth: hasMultipleWinners ? 2 : 1,
                ),
              ),

              // Right arrow (for multiple winners)
              if (hasMultipleWinners)
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: currentWinnerIndex < previousRoundWinners.length - 1
                      ? () => onWinnerIndexChanged(currentWinnerIndex + 1)
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 24,
                ),
            ],
          ),

          // See Results button (when showPreviousResults is enabled)
          if (showResultsButton && previousRoundResults != null && previousRoundResults!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _navigateToResultsGrid(context),
                icon: const Icon(Icons.grid_view, size: 18),
                label: Text(l10n.seeAllResults),
              ),
            ),
          ],

          // Page indicator dots for multiple winners
          if (hasMultipleWinners) ...[
            const SizedBox(height: 8),
            WinnerPageIndicator(
              count: previousRoundWinners.length,
              currentIndex: currentWinnerIndex,
              onIndexChanged: onWinnerIndexChanged,
            ),
          ],
        ],
      ),
    );
  }
}

/// A badge showing the tie count (e.g., "3-WAY TIE").
class TieBadge extends StatelessWidget {
  final int count;

  const TieBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count-WAY TIE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.orange.shade800,
        ),
      ),
    );
  }
}

/// Page indicator dots for navigating between tied winners.
class WinnerPageIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;
  final void Function(int) onIndexChanged;

  const WinnerPageIndicator({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => GestureDetector(
          onTap: () => onIndexChanged(index),
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == currentIndex
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}
