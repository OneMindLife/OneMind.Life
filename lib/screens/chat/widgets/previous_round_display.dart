import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../../../widgets/proposition_content_card.dart';

/// Displays the previous round winner(s) with support for tied winners.
/// Uses PropositionContentCard for consistent styling with other content displays.
/// Navigation is handled by the parent via [onTap].
class PreviousWinnerPanel extends StatelessWidget {
  final List<RoundWinner> previousRoundWinners;
  final int currentWinnerIndex;
  final void Function(int) onWinnerIndexChanged;

  /// The round number this winner is from (for "Round X Winner" label).
  final int? roundNumber;

  /// Optional label override (e.g. "Placeholder" in the tutorial).
  final String? labelOverride;

  /// Called when the card is tapped (parent handles navigation).
  final VoidCallback? onTap;

  const PreviousWinnerPanel({
    super.key,
    required this.previousRoundWinners,
    required this.currentWinnerIndex,
    required this.onWinnerIndexChanged,
    this.roundNumber,
    this.labelOverride,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (previousRoundWinners.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(l10n.noPreviousWinner),
      );
    }

    final hasMultipleWinners = previousRoundWinners.length > 1;
    final currentWinner = previousRoundWinners[currentWinnerIndex];
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Card with winner content (tappable)
        GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: UnconstrainedBox(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 64,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tie navigation: arrows + card (label inside)
                    if (hasMultipleWinners)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Left chevron (loops to last)
                          GestureDetector(
                            onTap: () {
                              final newIndex = currentWinnerIndex > 0
                                  ? currentWinnerIndex - 1
                                  : previousRoundWinners.length - 1;
                              onWinnerIndexChanged(newIndex);
                            },
                            child: Icon(
                              Icons.chevron_left,
                              size: 24,
                              color: AppColors.consensus,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: PropositionContentCard(
                              content: currentWinner.displayContent ??
                                  l10n.unknownProposition,
                              label: labelOverride
                                ?? (roundNumber != null
                                    ? l10n.roundWinner(roundNumber!)
                                    : l10n.previousWinner),
                              borderColor: AppColors.consensus,
                              glowColor: AppColors.consensus,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Right chevron (loops to first)
                          GestureDetector(
                            onTap: () {
                              final newIndex = currentWinnerIndex <
                                      previousRoundWinners.length - 1
                                  ? currentWinnerIndex + 1
                                  : 0;
                              onWinnerIndexChanged(newIndex);
                            },
                            child: Icon(
                              Icons.chevron_right,
                              size: 24,
                              color: AppColors.consensus,
                            ),
                          ),
                        ],
                      )
                    else
                      PropositionContentCard(
                        content: currentWinner.displayContent ??
                            l10n.unknownProposition,
                        label: labelOverride
                                ?? (roundNumber != null
                                    ? l10n.roundWinner(roundNumber!)
                                    : l10n.previousWinner),
                        borderColor: AppColors.consensus,
                        glowColor: AppColors.consensus,
                      ),

                    // Page dots (only when multiple winners)
                    if (hasMultipleWinners) ...[
                      const SizedBox(height: 6),
                      WinnerPageIndicator(
                        count: previousRoundWinners.length,
                        currentIndex: currentWinnerIndex,
                        onIndexChanged: onWinnerIndexChanged,
                        activeColor: AppColors.consensus,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Page indicator dots for navigating between tied winners.
class WinnerPageIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;
  final void Function(int) onIndexChanged;
  final Color? activeColor;

  const WinnerPageIndicator({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.onIndexChanged,
    this.activeColor,
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
                  ? (activeColor ?? Theme.of(context).colorScheme.primary)
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}
