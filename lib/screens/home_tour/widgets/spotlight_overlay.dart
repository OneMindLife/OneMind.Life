import 'package:flutter/material.dart';

/// A tooltip card shown during the home tour.
/// Displays title, description, progress dots, and Next/Skip buttons.
/// Title and description crossfade when they change between steps.
class TourTooltipCard extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final int stepIndex;
  final int totalSteps;
  final String nextLabel;
  final String skipLabel;
  final String stepOfLabel;

  const TourTooltipCard({
    super.key,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
    required this.stepIndex,
    required this.totalSteps,
    required this.nextLabel,
    required this.skipLabel,
    required this.stepOfLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                title,
                key: ValueKey('title_$stepIndex'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                description,
                key: ValueKey('desc_$stepIndex'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),

            // Progress dots row
            Row(
              children: [
                ...List.generate(totalSteps, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == stepIndex
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  );
                }),
                const SizedBox(width: 8),
                Text(
                  stepOfLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onSkip,
                  child: Text(skipLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onNext,
                  child: Text(nextLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
