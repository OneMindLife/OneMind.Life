import 'package:flutter/material.dart';
import '../proposition_content_card.dart';
import 'rating_model.dart';

/// Proposition card widget for the grid ranking with glow effects
class PropositionCard extends StatelessWidget {
  final RatingProposition proposition;
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
    final showGlow = isActive || isBinaryPhase;

    Widget cardContent = PropositionContentCard(
      content: proposition.content,
      backgroundColor: theme.colorScheme.surface,
      borderColor: showGlow
          ? primaryColor
          : theme.colorScheme.outline.withValues(alpha: 0.3),
      borderWidth: showGlow ? 2 : 1,
    );

    // Show glow if active OR if in binary phase
    if (showGlow) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.2),
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
