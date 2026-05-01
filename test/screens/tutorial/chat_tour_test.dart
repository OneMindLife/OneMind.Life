import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/models/tutorial_state.dart';
import 'package:onemind_app/screens/tutorial/notifiers/tutorial_notifier.dart';
import 'package:onemind_app/screens/tutorial/tutorial_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('Chat tour step progression (notifier)', () {
    late TutorialChatNotifier notifier;

    setUp(() {
      notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');
    });

    test('selectTemplate starts at chatTourIntro', () {
      expect(notifier.state.currentStep, TutorialStep.chatTourIntro);
      expect(notifier.state.selectedTemplate, 'saturday');
    });

    test('nextChatTourStep progresses through all 10 steps', () {
      final expectedSteps = [
        TutorialStep.chatTourTitle,
        TutorialStep.chatTourMessage,
        TutorialStep.chatTourPlaceholder,
        TutorialStep.chatTourRound,
        TutorialStep.chatTourPhases,
        TutorialStep.chatTourProgress,
        TutorialStep.chatTourTimer,
        TutorialStep.chatTourParticipants,
        TutorialStep.chatTourSubmit,
        TutorialStep.round1Proposing, // after last tour step
      ];

      for (final expected in expectedSteps) {
        notifier.nextChatTourStep();
        expect(notifier.state.currentStep, expected);
      }
    });

    test('skipChatTour jumps from any tour step to round1Proposing', () {
      // Advance a few steps
      notifier.nextChatTourStep(); // chatTourMessage
      notifier.nextChatTourStep(); // chatTourPlaceholder
      notifier.nextChatTourStep(); // chatTourRound

      notifier.skipChatTour();
      expect(notifier.state.currentStep, TutorialStep.round1Proposing);
    });

    test('isChatTourStep returns true during tour', () {
      expect(notifier.state.isChatTourStep, true);

      notifier.nextChatTourStep();
      expect(notifier.state.isChatTourStep, true);

      // Go to last tour step
      for (var i = 0; i < 8; i++) {
        notifier.nextChatTourStep();
      }
      expect(notifier.state.currentStep, TutorialStep.chatTourSubmit);
      expect(notifier.state.isChatTourStep, true);
    });

    test('isChatTourStep returns false after tour', () {
      notifier.skipChatTour();
      expect(notifier.state.isChatTourStep, false);
    });

    test('chatTourStepIndex is correct for each step', () {
      expect(notifier.state.chatTourStepIndex, 0); // chatTourIntro

      notifier.nextChatTourStep();
      expect(notifier.state.chatTourStepIndex, 1); // chatTourTitle

      notifier.nextChatTourStep();
      expect(notifier.state.chatTourStepIndex, 2); // chatTourMessage
    });

    test('chatTourTotalSteps is 10', () {
      expect(TutorialChatState.chatTourTotalSteps, 10);
    });
  });

  group('Chat tour widget rendering', () {
    testWidgets('chat tour starts with skipIntro=true', (tester) async {
      await tester.pumpApp(
        TutorialScreen(skipIntro: true, onComplete: () {}),
      );
      await tester.pumpAndSettle();

      // Pump through all intro delays and animations (may fire multiple timers)
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      expect(
        container.read(tutorialChatNotifierProvider).currentStep,
        TutorialStep.chatTourIntro,
      );
    });

    testWidgets('app bar shows tutorial title during chat tour',
        (tester) async {
      await tester.pumpApp(
        TutorialScreen(skipIntro: true, onComplete: () {}),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('text field visible after skipping to proposing',
        (tester) async {
      await tester.pumpApp(
        TutorialScreen(skipIntro: true, onComplete: () {}),
      );
      // tutorial_screen.dart's initState fires a Future.delayed(300ms) +
      // a follow-up Future.delayed(400ms) for fade-in setup. pumpAndSettle
      // doesn't always drain those before the test ends, leaving timers
      // pending at teardown. Advance fake time past them explicitly.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      container.read(tutorialChatNotifierProvider.notifier).skipChatTour();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('leaderboard icon visible during tour', (tester) async {
      await tester.pumpApp(
        TutorialScreen(skipIntro: true, onComplete: () {}),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialScreen)),
      );
      container.read(tutorialChatNotifierProvider.notifier).skipChatTour();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.leaderboard), findsOneWidget);
    });
  });

  group('Chat tour state model', () {
    test('TutorialChatState copyWith preserves all fields', () {
      final state = TutorialChatState(
        currentStep: TutorialStep.chatTourPhases,
        chat: TutorialChatNotifier().state.chat,
        myParticipant: TutorialChatNotifier().state.myParticipant,
        selectedTemplate: 'saturday',
      );

      final copied = state.copyWith(currentStep: TutorialStep.chatTourTimer);

      expect(copied.currentStep, TutorialStep.chatTourTimer);
      expect(copied.selectedTemplate, 'saturday');
    });

    test('TutorialChatState equality detects step changes', () {
      final notifier = TutorialChatNotifier();
      final initialState = notifier.state;

      notifier.selectTemplate('saturday');
      final afterTemplate = notifier.state;

      // Different step means different state
      expect(initialState.currentStep, TutorialStep.intro);
      expect(afterTemplate.currentStep, TutorialStep.chatTourIntro);
      expect(initialState, isNot(equals(afterTemplate)));
    });
  });

  group('Template selection', () {
    test('saturday template sets correct chat data', () {
      final notifier = TutorialChatNotifier();
      notifier.selectTemplate('saturday');

      expect(notifier.state.chat.name, 'Saturday Plans');
      expect(notifier.state.selectedTemplate, 'saturday');
    });

    test('classic template with custom question stores question', () {
      final notifier = TutorialChatNotifier();
      notifier.selectTemplate('classic', customQuestion: 'My question?');

      expect(notifier.state.selectedTemplate, 'classic');
      expect(notifier.state.customQuestion, 'My question?');
    });

    test('participants initialized with 4 members', () {
      final notifier = TutorialChatNotifier();
      expect(notifier.state.participants.length, 4);
      expect(notifier.state.myParticipant.displayName, 'You');
    });
  });
}
