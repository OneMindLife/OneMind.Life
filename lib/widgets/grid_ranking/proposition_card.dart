import 'package:flutter/material.dart';
import 'grid_ranking_model.dart';

/// Simple proposition card widget for the grid ranking
class PropositionCard extends StatelessWidget {
  final RankingProposition proposition;
  final bool isActive;
  final bool isBinaryPhase;
  final Color? activeGlowColor;

  const PropositionCard({
    super.key,
    required this.proposition,
    required this.isActive,
    this.isBinaryPhase = false,
    this.activeGlowColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = activeGlowColor ?? theme.colorScheme.primary;

    Widget cardContent = Container(
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isActive || isBinaryPhase)
              ? primaryColor
              : theme.colorScheme.outline.withValues(alpha:0.3),
          width: (isActive || isBinaryPhase) ? 2 : 1,
        ),
      ),
      child: Text(
        proposition.content,
        style: theme.textTheme.bodyMedium,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );

    // Show glow if active OR if in binary phase
    if (isActive || isBinaryPhase) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha:0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: primaryColor.withValues(alpha:0.2),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: cardContent,
      );
    }

    return cardContent;
  }
}
