import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// A styled card for displaying labeled content (initial messages, convergence items, etc.).
///
/// Used in both the real chat screen and tutorial to ensure consistent styling.
class MessageCard extends StatelessWidget {
  final String label;
  final String content;
  final bool isPrimary;
  final bool isConsensus;

  const MessageCard({
    super.key,
    required this.label,
    required this.content,
    this.isPrimary = false,
    this.isConsensus = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor;
    final Color backgroundColor;
    if (isConsensus) {
      accentColor = AppColors.consensus;
      backgroundColor = AppColors.consensus.withValues(alpha: 0.08);
    } else if (isPrimary) {
      accentColor = Theme.of(context).colorScheme.primary;
      backgroundColor =
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.08);
    } else {
      accentColor = Theme.of(context).colorScheme.outline;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
