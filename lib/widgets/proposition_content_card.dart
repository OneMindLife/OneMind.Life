import 'package:flutter/material.dart';

/// A reusable card for displaying proposition content.
/// Used anywhere propositions need to be shown consistently.
///
/// By default the card grows to fit the full content (no scroll). Rating
/// screens — where many propositions share a grid and must fit on one
/// screen — set [bounded] to `true` to apply [maxHeight] and allow scroll.
///
/// When [glowColor] is non-null the card renders with a static halo of
/// that color.
class PropositionContentCard extends StatelessWidget {
  final String content;
  final String? label;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double maxHeight;
  final Color? glowColor;
  final double contentOpacity;
  final Widget? mediaAbove;

  /// Optional widget rendered after the text section (inside the card's
  /// border). Use this when the visual should appear below the caption,
  /// e.g. a video that supplements the proposition text.
  final Widget? mediaBelow;

  final Widget? trailing;

  /// When true (and [trailing] is non-null), the trailing widget is laid
  /// out as a [WidgetSpan] at the end of the content text — so it sits
  /// inline with the last word instead of stacked below the paragraph.
  final bool inlineTrailing;

  /// When true, applies [maxHeight] and scrolls overflow. When false
  /// (default), the card expands to fit the full text.
  final bool bounded;

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
    this.mediaAbove,
    this.mediaBelow,
    this.trailing,
    this.inlineTrailing = false,
    this.bounded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Body text. When inline trailing is requested and a trailing widget
    // exists, build with Text.rich + WidgetSpan so the icon flows at the
    // end of the last line instead of stacked below the paragraph.
    final bodyStyle = theme.textTheme.bodyMedium;
    // For inline trailing, cap the widget height so it doesn't blow up
    // the line containing it. We pick a compromise: large enough to be
    // a reliable tap target on mobile, but small enough that the line
    // it lives on isn't dramatically taller than its neighbors.
    final inlineTrailingHeight = 32.0;
    final Widget bodyText = (inlineTrailing && trailing != null)
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$content '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: SizedBox(
                    height: inlineTrailingHeight,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: trailing,
                    ),
                  ),
                ),
              ],
            ),
            style: bodyStyle,
            textAlign: TextAlign.center,
          )
        : Text(
            content,
            style: bodyStyle,
            textAlign: TextAlign.center,
          );

    final textColumn = Opacity(
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
                bodyText,
              ],
            )
          : bodyText,
    );

    // Only wrap in SingleChildScrollView when bounded; otherwise the card
    // grows with the content and scrolling belongs to the parent screen.
    final Widget textSection = bounded
        ? SingleChildScrollView(child: textColumn)
        : textColumn;

    final decoration = BoxDecoration(
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
    );

    // Inline trailing was already absorbed into bodyText; for the
    // stacked variant keep the existing column layout.
    final textWithTrailing = (trailing == null || inlineTrailing)
        ? textSection
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bounded ? Flexible(child: textSection) : textSection,
              const SizedBox(height: 4),
              trailing!,
            ],
          );

    final textPane = bounded
        ? ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: textWithTrailing,
          )
        : textWithTrailing;

    if (mediaAbove != null || mediaBelow != null) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mediaAbove != null) mediaAbove!,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: textPane,
            ),
            if (mediaBelow != null) mediaBelow!,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: decoration,
      child: textPane,
    );
  }
}
