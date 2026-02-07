import 'package:flutter/material.dart';

/// Custom painter for the leaderboard grid background.
///
/// Draws a 0-100 scale on the left side with labels every 10 units.
/// Higher positions on screen correspond to higher scores.
class LeaderboardGridPainter extends CustomPainter {
  final Color labelColor;
  final TextStyle labelStyle;
  final double viewportHeight;
  final double scrollOffset;

  LeaderboardGridPainter({
    required this.labelColor,
    required this.labelStyle,
    required this.viewportHeight,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawYAxisLabels(canvas, size);
  }

  void _drawYAxisLabels(Canvas canvas, Size size) {
    // Draw labels every 10 units (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100)
    for (int position = 0; position <= 100; position += 10) {
      // Higher position = higher on screen (lower y value)
      final y = (1 - position / 100) * size.height;

      // Check visibility
      final isVisible =
          !(y < scrollOffset - 20 || y > scrollOffset + viewportHeight + 20);

      if (!isVisible) continue;

      final textPainter = TextPainter(
        text: TextSpan(
          text: position.toString(),
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(8, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(LeaderboardGridPainter oldDelegate) {
    return oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.viewportHeight != viewportHeight ||
        oldDelegate.labelColor != labelColor;
  }
}
