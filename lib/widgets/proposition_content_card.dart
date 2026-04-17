import 'package:flutter/material.dart';

/// A reusable card for displaying proposition content.
/// Used anywhere propositions need to be shown consistently.
class PropositionContentCard extends StatelessWidget {
  final String content;
  final String? label;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double maxHeight;
  final Color? glowColor;
  final double contentOpacity;

  const PropositionContentCard({
    super.key,
    required this.content,
    this.label,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.maxHeight = 150,
    this.glowColor,
    this.contentOpacity = 1.0,
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
        boxShadow: glowColor != null
            ? [
                BoxShadow(
                  color: glowColor!.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: glowColor!.withValues(alpha: 0.1),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: SingleChildScrollView(
        child: Opacity(
          opacity: contentOpacity,
          child: label != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      content,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Text(
                  content,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    );
  }
}
