import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/home_tour_state.dart';

/// Notifier that manages the home screen tour step progression
class HomeTourNotifier extends StateNotifier<HomeTourState> {
  HomeTourNotifier() : super(const HomeTourState()) {
    if (kDebugMode) {
      debugPrint('[HomeTourNotifier] created, starting at ${state.currentStep}');
    }
  }

  /// Advance to the next tour step, or mark complete
  void nextStep() {
    final steps = HomeTourStep.values;
    final nextIndex = state.stepIndex + 1;
    if (nextIndex >= HomeTourState.total) {
      state = state.copyWith(
        currentStep: HomeTourStep.complete,
        stepIndex: nextIndex,
      );
    } else {
      state = state.copyWith(
        currentStep: steps[nextIndex],
        stepIndex: nextIndex,
      );
    }
    if (kDebugMode) {
      debugPrint('[HomeTourNotifier] nextStep → ${state.currentStep} '
          '(${state.stepIndex}/${state.totalSteps})');
    }
  }

  /// Skip remaining steps and mark tour complete
  void skip() {
    state = state.copyWith(
      currentStep: HomeTourStep.complete,
      stepIndex: HomeTourState.total,
    );
    if (kDebugMode) {
      debugPrint('[HomeTourNotifier] skip → complete');
    }
  }
}
