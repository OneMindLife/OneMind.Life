import 'package:flutter/material.dart';

import '../models/tutorial_state.dart';

/// Progress indicator showing current position in the tutorial
class TutorialProgressDots extends StatelessWidget {
  final TutorialStep currentStep;

  const TutorialProgressDots({
    super.key,
    required this.currentStep,
  });

  /// Map steps to progress segments (aligned with actual tutorial flow)
  /// Flow: intro → R1 propose/rate/result → R2 prompt/rate/result → R3 propose/rate/consensus → shareDemo → complete
  static const _stepSegments = {
    TutorialStep.intro: 0,
    // Round 1
    TutorialStep.round1Proposing: 1,
    TutorialStep.round1Rating: 2,
    TutorialStep.round1Result: 3,
    // Round 2 (round2Prompt shows proposing input)
    TutorialStep.round2Prompt: 4,
    TutorialStep.round2Proposing: 4, // Same as prompt
    TutorialStep.round2Rating: 5,
    TutorialStep.round2Result: 6,
    // Round 3
    TutorialStep.round3CarryForward: 7, // Legacy, maps to proposing
    TutorialStep.round3Proposing: 7,
    TutorialStep.round3Rating: 8,
    TutorialStep.round3Consensus: 9,
    // Share demo and completion
    TutorialStep.shareDemo: 10,
    TutorialStep.complete: 11,
  };

  static const _totalSegments = 11;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentSegment = _stepSegments[currentStep] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_totalSegments, (index) {
          final isActive = index <= currentSegment;
          final isCurrent = index == currentSegment;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isCurrent ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }
}
