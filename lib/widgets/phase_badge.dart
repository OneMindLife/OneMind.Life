import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/round.dart';

/// Colored chip showing the current phase: "Proposing", "Rating", "Waiting", "Paused", "Idle"
class PhaseBadge extends StatelessWidget {
  final RoundPhase? phase;
  final bool isPaused;

  const PhaseBadge({
    super.key,
    required this.phase,
    this.isPaused = false,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color, textColor) = _phaseStyle();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  (String, Color, Color) _phaseStyle() {
    if (isPaused) return ('Paused', AppColors.waiting, AppColors.waiting);
    switch (phase) {
      case RoundPhase.proposing:
        return ('Proposing', AppColors.proposing, AppColors.proposing);
      case RoundPhase.rating:
        return ('Rating', AppColors.rating, AppColors.rating);
      case RoundPhase.waiting:
        return ('Waiting', AppColors.consensus, const Color(0xFF92400E));
      case null:
        return ('Idle', AppColors.waiting, AppColors.textMuted);
    }
  }
}
