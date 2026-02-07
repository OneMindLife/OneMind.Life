import 'package:flutter/material.dart';
import 'rating_model.dart';

/// Custom painter for the ranking grid
class RatingPainter extends CustomPainter {
  final List<RatingProposition> propositions;
  final double scrollOffset;
  final Color gridColor;
  final Color activeColor;
  final TextStyle labelStyle;
  final double? activePosition;
  final double viewportHeight;

  RatingPainter({
    required this.propositions,
    required this.scrollOffset,
    required this.gridColor,
    required this.activeColor,
    required this.labelStyle,
    required this.viewportHeight,
    this.activePosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawYAxisLabels(canvas, size);

    if (activePosition != null) {
      _drawActivePositionLabel(canvas, size);
    }
  }

  void _drawYAxisLabels(Canvas canvas, Size size) {
    // Draw labels every 10 units (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100)
    for (int position = 0; position <= 100; position += 10) {
      final y = (1 - position / 100) * size.height;

      // Check visibility
      final isVisible =
          !(y < scrollOffset - 20 || y > scrollOffset + viewportHeight + 20);

      if (!isVisible) continue;

      final textPainter = TextPainter(
        text: TextSpan(
          text: position.toString(),
          style: labelStyle,
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

  void _drawActivePositionLabel(Canvas canvas, Size size) {
    if (activePosition == null) return;

    final y = (1 - activePosition! / 100) * size.height;

    // Check visibility
    if (y < scrollOffset - 20 || y > scrollOffset + viewportHeight + 20) {
      return;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: activePosition!.round().toString(),
        style: labelStyle.copyWith(
          color: activeColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    textPainter.paint(
      canvas,
      Offset(8, y - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(RatingPainter oldDelegate) {
    return oldDelegate.propositions != propositions ||
        oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.activePosition != activePosition ||
        oldDelegate.viewportHeight != viewportHeight;
  }
}
