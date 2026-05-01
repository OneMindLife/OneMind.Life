import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/home_tour/models/home_tour_state.dart';
import 'package:onemind_app/screens/home_tour/notifiers/home_tour_notifier.dart';

void main() {
  group('HomeTourStep', () {
    test('has 7 steps before complete', () {
      final steps = HomeTourStep.values.where((s) => s != HomeTourStep.complete).toList();
      expect(steps.length, 7);
    });

    test('steps are in correct order: body first, then app bar', () {
      expect(HomeTourStep.values, [
        HomeTourStep.welcomeName,
        HomeTourStep.searchBar,
        HomeTourStep.yourChats,
        HomeTourStep.pendingRequest,
        HomeTourStep.createFab,
        HomeTourStep.languageSelector,
        HomeTourStep.menu,
        HomeTourStep.complete,
      ]);
    });

    test('languageSelector is at index 5', () {
      expect(HomeTourStep.values.indexOf(HomeTourStep.languageSelector), 5);
    });
  });

  group('HomeTourState', () {
    test('defaults to welcomeName step at index 0', () {
      const state = HomeTourState();
      expect(state.currentStep, HomeTourStep.welcomeName);
      expect(state.stepIndex, 0);
      expect(state.totalSteps, HomeTourState.total);
    });

    test('total is 7', () {
      expect(HomeTourState.total, 7);
    });

    test('copyWith creates new instance with updated fields', () {
      const state = HomeTourState();
      final updated = state.copyWith(
        currentStep: HomeTourStep.languageSelector,
        stepIndex: 5,
      );
      expect(updated.currentStep, HomeTourStep.languageSelector);
      expect(updated.stepIndex, 5);
      expect(updated.totalSteps, 7);
    });
  });

  group('HomeTourNotifier', () {
    late HomeTourNotifier notifier;

    setUp(() {
      notifier = HomeTourNotifier();
    });

    test('starts at welcomeName step', () {
      expect(notifier.state.currentStep, HomeTourStep.welcomeName);
      expect(notifier.state.stepIndex, 0);
    });

    test('nextStep advances to next step', () {
      notifier.nextStep();
      expect(notifier.state.currentStep, HomeTourStep.searchBar);
      expect(notifier.state.stepIndex, 1);
    });

    test('nextStep progresses through all steps', () {
      final expectedSteps = [
        HomeTourStep.searchBar,
        HomeTourStep.yourChats,
        HomeTourStep.pendingRequest,
        HomeTourStep.createFab,
        HomeTourStep.languageSelector,
        HomeTourStep.menu,
        HomeTourStep.complete,
      ];

      for (final expected in expectedSteps) {
        notifier.nextStep();
        expect(notifier.state.currentStep, expected);
      }
    });

    test('languageSelector step shows at step index 5', () {
      for (int i = 0; i < 5; i++) {
        notifier.nextStep();
      }
      expect(notifier.state.currentStep, HomeTourStep.languageSelector);
      expect(notifier.state.stepIndex, 5);
    });

    test('last step before complete is menu', () {
      for (int i = 0; i < 6; i++) {
        notifier.nextStep();
      }
      expect(notifier.state.currentStep, HomeTourStep.menu);
      expect(notifier.state.stepIndex, 6);

      notifier.nextStep();
      expect(notifier.state.currentStep, HomeTourStep.complete);
    });

    test('skip jumps to complete', () {
      notifier.skip();
      expect(notifier.state.currentStep, HomeTourStep.complete);
      expect(notifier.state.stepIndex, HomeTourState.total);
    });

    test('skip from middle jumps to complete', () {
      notifier.nextStep();
      notifier.nextStep();
      notifier.skip();
      expect(notifier.state.currentStep, HomeTourStep.complete);
    });

    test('reset returns to welcomeName after progression', () {
      notifier.nextStep();
      notifier.nextStep();
      notifier.nextStep();
      notifier.reset();
      expect(notifier.state.currentStep, HomeTourStep.welcomeName);
      expect(notifier.state.stepIndex, 0);
    });

    test('reset returns to welcomeName after complete', () {
      notifier.skip();
      expect(notifier.state.currentStep, HomeTourStep.complete);
      notifier.reset();
      expect(notifier.state.currentStep, HomeTourStep.welcomeName);
      expect(notifier.state.stepIndex, 0);
    });
  });
}
