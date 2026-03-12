import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/home_tour/models/home_tour_state.dart';
import 'package:onemind_app/screens/home_tour/notifiers/home_tour_notifier.dart';

void main() {
  group('HomeTourStep', () {
    test('has 8 steps before complete', () {
      // All values except 'complete'
      final steps = HomeTourStep.values.where((s) => s != HomeTourStep.complete).toList();
      expect(steps.length, 8);
    });

    test('steps are in correct order: body first, then app bar', () {
      expect(HomeTourStep.values, [
        HomeTourStep.welcomeName,
        HomeTourStep.searchBar,
        HomeTourStep.pendingRequest,
        HomeTourStep.yourChats,
        HomeTourStep.createFab,
        HomeTourStep.exploreButton,
        HomeTourStep.languageSelector,
        HomeTourStep.menu,
        HomeTourStep.complete,
      ]);
    });

    test('exploreButton is at index 5', () {
      expect(HomeTourStep.values.indexOf(HomeTourStep.exploreButton), 5);
    });

    test('languageSelector is at index 6', () {
      expect(HomeTourStep.values.indexOf(HomeTourStep.languageSelector), 6);
    });
  });

  group('HomeTourState', () {
    test('defaults to welcomeName step at index 0', () {
      const state = HomeTourState();
      expect(state.currentStep, HomeTourStep.welcomeName);
      expect(state.stepIndex, 0);
      expect(state.totalSteps, HomeTourState.total);
    });

    test('total is 8', () {
      expect(HomeTourState.total, 8);
    });

    test('copyWith creates new instance with updated fields', () {
      const state = HomeTourState();
      final updated = state.copyWith(
        currentStep: HomeTourStep.exploreButton,
        stepIndex: 5,
      );
      expect(updated.currentStep, HomeTourStep.exploreButton);
      expect(updated.stepIndex, 5);
      expect(updated.totalSteps, 8);
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
        HomeTourStep.pendingRequest,
        HomeTourStep.yourChats,
        HomeTourStep.createFab,
        HomeTourStep.exploreButton,
        HomeTourStep.languageSelector,
        HomeTourStep.menu,
        HomeTourStep.complete,
      ];

      for (final expected in expectedSteps) {
        notifier.nextStep();
        expect(notifier.state.currentStep, expected);
      }
    });

    test('exploreButton step shows at step index 5', () {
      // Advance 5 times: welcomeName -> searchBar -> pendingRequest -> yourChats -> createFab -> exploreButton
      for (int i = 0; i < 5; i++) {
        notifier.nextStep();
      }
      expect(notifier.state.currentStep, HomeTourStep.exploreButton);
      expect(notifier.state.stepIndex, 5);
    });

    test('last step before complete is menu', () {
      // Advance 7 times to reach menu
      for (int i = 0; i < 7; i++) {
        notifier.nextStep();
      }
      expect(notifier.state.currentStep, HomeTourStep.menu);
      expect(notifier.state.stepIndex, 7);

      // One more advances to complete
      notifier.nextStep();
      expect(notifier.state.currentStep, HomeTourStep.complete);
    });

    test('skip jumps to complete', () {
      notifier.skip();
      expect(notifier.state.currentStep, HomeTourStep.complete);
      expect(notifier.state.stepIndex, HomeTourState.total);
    });

    test('skip from middle jumps to complete', () {
      notifier.nextStep(); // searchBar
      notifier.nextStep(); // pendingRequest
      notifier.skip();
      expect(notifier.state.currentStep, HomeTourStep.complete);
    });
  });
}
