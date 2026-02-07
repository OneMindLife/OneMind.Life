import 'package:flutter/material.dart';

/// A reusable card for displaying proposition content.
/// Used anywhere propositions need to be shown consistently.
class PropositionContentCard extends StatelessWidget {
  final String content;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double maxHeight;

  const PropositionContentCard({
    super.key,
    required this.content,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.maxHeight = 150,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor ?? theme.colorScheme.outline.withValues(alpha: 0.3),
          width: borderWidth,
        ),
      ),
      child: SingleChildScrollView(
        child: Text(
          content,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
