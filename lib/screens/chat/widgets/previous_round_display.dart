import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../../grid_ranking/read_only_grid_results_screen.dart';

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
  });

  void _navigateToResultsGrid(BuildContext context) {
    if (previousRoundResults == null || previousRoundResults!.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReadOnlyGridResultsScreen(
          propositions: previousRoundResults!,
          roundNumber: (currentRoundCustomId ?? 1) - 1,
        ),
      ),
    );
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
    final previousRoundNumber = (currentRoundCustomId ?? 1) - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with tie indicator
          Row(
            children: [
              Text(
                hasMultipleWinners
                    ? l10n.roundWinners(previousRoundNumber)
                    : l10n.roundWinner(previousRoundNumber),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (hasMultipleWinners) ...[
                const SizedBox(width: 8),
                TieBadge(count: previousRoundWinners.length),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Winner card with navigation
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: hasMultipleWinners
                  ? Border.all(color: Colors.orange.shade300, width: 2)
                  : null,
            ),
            child: Row(
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

                // Winner content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasMultipleWinners)
                        Text(
                          '${currentWinnerIndex + 1} of ${previousRoundWinners.length}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      const SizedBox(height: 4),
                      Text(currentWinner.displayContent ?? l10n.unknownProposition),
                      if (currentWinner.globalScore != null)
                        Text(
                          l10n.score(currentWinner.globalScore!.toStringAsFixed(1)),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
                    iconSize: 24,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Consensus tracking
          Text(
            isSoleWinner
                ? l10n.soleWinsProgress(consecutiveSoleWins, confirmationRoundsRequired)
                : l10n.tiedWinNoConsensus,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isSoleWinner
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Colors.orange.shade700,
                ),
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
