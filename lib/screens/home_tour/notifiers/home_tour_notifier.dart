import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/analytics_service.dart';
import '../models/home_tour_state.dart';

/// Notifier that manages the home screen tour step progression
class HomeTourNotifier extends StateNotifier<HomeTourState> {
  final AnalyticsService? _analytics;

  HomeTourNotifier({AnalyticsService? analytics})
      : _analytics = analytics,
        super(const HomeTourState());

  /// Advance to the next tour step, or mark complete
  void nextStep() {
    final steps = HomeTourStep.values;
    final nextIndex = state.stepIndex + 1;
    if (nextIndex >= HomeTourState.total) {
      state = state.copyWith(
        currentStep: HomeTourStep.complete,
        stepIndex: nextIndex,
      );
      _analytics?.logHomeTourCompleted();
    } else {
      state = state.copyWith(
        currentStep: steps[nextIndex],
        stepIndex: nextIndex,
      );
      _analytics?.logHomeTourStepCompleted(
        stepName: steps[nextIndex].name,
        stepIndex: nextIndex,
      );
    }
  }

  /// Reset tour to the beginning
  void reset() {
    state = const HomeTourState();
  }

  /// Skip remaining steps and mark tour complete
  void skip() {
    state = state.copyWith(
      currentStep: HomeTourStep.complete,
      stepIndex: HomeTourState.total,
    );
    _analytics?.logHomeTourCompleted();
  }
}
