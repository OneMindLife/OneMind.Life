import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
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

  /// Custom callback for viewing results. When provided, overrides the default
  /// navigation to ReadOnlyResultsScreen. Useful for the tutorial which needs
  /// to translate propositions before displaying.
  final VoidCallback? onViewResults;

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
    this.onViewResults,
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

    final theme = Theme.of(context);
    final hasResults = showResultsButton && (onViewResults != null || (previousRoundResults != null && previousRoundResults!.isNotEmpty));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.consensus.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.consensus.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tie indicator (only shown for multiple winners)
                if (hasMultipleWinners) ...[
                  TieBadge(count: previousRoundWinners.length),
                  const SizedBox(height: 4),
                ],

                // Main content row: arrows + label/content
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                        iconSize: 20,
                      ),

                    // Winner content
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.previousWinner,
                            style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 2),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 80),
                            child: SingleChildScrollView(
                              child: Text(
                                currentWinner.displayContent ?? l10n.unknownProposition,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ),
                        ],
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
                        iconSize: 20,
                      ),
                  ],
                ),

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
          ),
        ),

        // See results button (outside the card)
        if (hasResults)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: onViewResults ?? () => _navigateToResultsGrid(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.labelSmall,
              ),
              child: Text(l10n.viewAllRatings),
            ),
          ),
      ],
    );
  }
}

/// A badge showing the tie count (e.g., "3-WAY TIE").
class TieBadge extends StatelessWidget {
  final int count;

  const TieBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.consensusLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        l10n.nWayTie(count),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF92400E), // amber-800
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
