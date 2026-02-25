import 'package:flutter/material.dart';

/// A tooltip card shown during the home tour.
/// Displays title, description, progress dots, and Next/Skip buttons.
/// Title and description crossfade when they change between steps.
class TourTooltipCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget? descriptionWidget;
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
    this.descriptionWidget,
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
              child: KeyedSubtree(
                key: ValueKey('desc_$stepIndex'),
                child: descriptionWidget ??
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            // Button row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
