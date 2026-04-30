import 'package:flutter/material.dart';
import 'proposition_content_card.dart';

/// A styled card for displaying labeled content (initial messages, convergence items, etc.).
///
/// Uses PropositionContentCard internally for consistent styling with rating screens.
/// Shrinks to content width. Label above content, inside the border.
class MessageCard extends StatelessWidget {
  final String? label;
  final String content;
  final bool isPrimary;
  final bool isConsensus;
  final Widget? mediaAbove;
  final Widget? mediaBelow;
  final Widget? trailing;
  final bool inlineTrailing;

  const MessageCard({
    super.key,
    this.label,
    required this.content,
    this.isPrimary = false,
    this.isConsensus = false,
    this.mediaAbove,
    this.mediaBelow,
    this.trailing,
    this.inlineTrailing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Both consensus and primary use the primary (blue) border
    final Color? borderColor;
    if (isConsensus || isPrimary) {
      borderColor = theme.colorScheme.primary;
    } else {
      borderColor = null; // PropositionContentCard default
    }

    return UnconstrainedBox(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 64,
        ),
        child: PropositionContentCard(
          content: content,
          label: label,
          borderColor: borderColor,
          glowColor: borderColor,
          mediaAbove: mediaAbove,
          mediaBelow: mediaBelow,
          trailing: trailing,
          inlineTrailing: inlineTrailing,
        ),
      ),
    );
  }
}
