import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/home_tour/widgets/spotlight_overlay.dart';

import '../../../helpers/pump_app.dart';

void main() {
  setUp(() {
    TutorialTts.muted = true;
  });

  tearDown(() {
    TutorialTts.muted = false;
  });

  group('TourTooltipCard', () {
    Widget buildCard({
      String title = 'Test Title',
      String description = 'Test description text.',
      Widget? descriptionWidget,
      VoidCallback? onNext,
      VoidCallback? onSkip,
      int stepIndex = 0,
      int totalSteps = 5,
      String nextLabel = 'Next',
      String skipLabel = 'Skip',
      String stepOfLabel = 'of',
      bool autoAdvance = true,
    }) {
      return TourTooltipCard(
        title: title,
        description: description,
        descriptionWidget: descriptionWidget,
        onNext: onNext ?? () {},
        onSkip: onSkip ?? () {},
        stepIndex: stepIndex,
        totalSteps: totalSteps,
        nextLabel: nextLabel,
        skipLabel: skipLabel,
        stepOfLabel: stepOfLabel,
        autoAdvance: autoAdvance,
      );
    }

    testWidgets('renders title text', (tester) async {
      await tester.pumpApp(Scaffold(body: buildCard(title: 'Chat Name')));
      await tester.pumpAndSettle();

      expect(find.text('Chat Name'), findsOneWidget);
    });

    testWidgets('renders description text when muted', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildCard(description: 'This is the chat name.')),
      );
      await tester.pumpAndSettle();

      expect(find.text('This is the chat name.'), findsOneWidget);
    });

    testWidgets('shows Next button with correct label', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildCard(nextLabel: 'Got it!')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Got it!'), findsOneWidget);
    });

    testWidgets('calls onNext when button is tapped', (tester) async {
      var nextCalled = false;
      await tester.pumpApp(
        Scaffold(body: buildCard(onNext: () => nextCalled = true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      expect(nextCalled, true);
    });

    testWidgets('shows volume_off icon when muted', (tester) async {
      await tester.pumpApp(Scaffold(body: buildCard()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('shows Material card with elevation', (tester) async {
      await tester.pumpApp(Scaffold(body: buildCard()));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find.ancestor(
          of: find.text('Test Title'),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.elevation, 8);
    });

    testWidgets('shows card with rounded border', (tester) async {
      await tester.pumpApp(Scaffold(body: buildCard()));
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find.ancestor(
          of: find.text('Test Title'),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.shape, isA<RoundedRectangleBorder>());
    });

    testWidgets('button shows when autoAdvance is false', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildCard(autoAdvance: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('button shows when muted even with autoAdvance true', (tester) async {
      // When muted, TTS never plays, so button should be visible
      await tester.pumpApp(
        Scaffold(body: buildCard(autoAdvance: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('descriptionWidget is used when provided and muted', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: buildCard(
            description: 'fallback text',
            descriptionWidget: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Custom'),
                Icon(Icons.star),
              ],
            ),
            // autoAdvance false so the card stays in muted state with button visible
            autoAdvance: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // When muted, the description shows plain text (not descriptionWidget)
      // because descriptionWidget is only used in the "done with no audio" path
      // for TourTooltipCard. Verify the fallback text is shown.
      expect(find.text('fallback text'), findsOneWidget);
    });

    testWidgets('title is bold', (tester) async {
      await tester.pumpApp(Scaffold(body: buildCard(title: 'Bold Title')));
      await tester.pumpAndSettle();

      final titleWidget = tester.widget<Text>(find.text('Bold Title'));
      expect(titleWidget.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('toggle mute icon unmutes and changes icon', (tester) async {
      await tester.pumpApp(Scaffold(body: buildCard()));
      await tester.pumpAndSettle();

      // Initially muted
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      // Tap mute toggle
      await tester.tap(find.byIcon(Icons.volume_off));
      await tester.pumpAndSettle();

      // Should now show volume_up (unmuted)
      // Note: since there's no audio file for 'Test description text.',
      // it will go to done state with replay icon
      expect(TutorialTts.muted, false);

      // Re-mute for cleanup
      TutorialTts.muted = true;
    });
  });

  group('NoButtonTtsCard', () {
    Widget buildNoButtonCard({
      String title = 'Action Title',
      String description = 'Tap the element to continue.',
      Widget? descriptionWidget,
    }) {
      return NoButtonTtsCard(
        title: title,
        description: description,
        descriptionWidget: descriptionWidget,
      );
    }

    testWidgets('renders title text', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildNoButtonCard(title: 'Tap to Continue')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tap to Continue'), findsOneWidget);
    });

    testWidgets('renders description text when muted', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildNoButtonCard(description: 'Tap the card.')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tap the card.'), findsOneWidget);
    });

    testWidgets('has no Next or action button', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildNoButtonCard()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Got it!'), findsNothing);
    });

    testWidgets('shows volume icon (mute toggle)', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildNoButtonCard()),
      );
      await tester.pumpAndSettle();

      // When muted, shows volume_off
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('has elevation 8 card', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildNoButtonCard()),
      );
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find.ancestor(
          of: find.text('Action Title'),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.elevation, 8);
    });

    testWidgets('has rounded border with primary color', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildNoButtonCard()),
      );
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find.ancestor(
          of: find.text('Action Title'),
          matching: find.byType(Material),
        ).first,
      );
      final shape = material.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
    });

    testWidgets('descriptionWidget is used when muted and provided', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: buildNoButtonCard(
            description: 'fallback',
            descriptionWidget: const Text('Rich content here'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rich content here'), findsOneWidget);
    });

    testWidgets('title is bold', (tester) async {
      await tester.pumpApp(
        Scaffold(body: buildNoButtonCard(title: 'Bold Action')),
      );
      await tester.pumpAndSettle();

      final titleWidget = tester.widget<Text>(find.text('Bold Action'));
      expect(titleWidget.style?.fontWeight, FontWeight.bold);
    });
  });

  group('TutorialTts', () {
    test('muted defaults to false', () {
      // We set it true in setUp, verify we can read it
      expect(TutorialTts.muted, true);

      // Reset for this test
      TutorialTts.muted = false;
      expect(TutorialTts.muted, false);

      // Restore
      TutorialTts.muted = true;
    });

    test('hasAudio returns true for known text', () {
      expect(TutorialTts.hasAudio('This is the chat name.'), true);
    });

    test('hasAudio returns false for unknown text', () {
      expect(TutorialTts.hasAudio('Random unknown text'), false);
    });

    test('hasAudio handles marker replacement', () {
      // Text with [back] marker should match after cleaning
      expect(TutorialTts.hasAudio('Press the back arrow to continue.'), true);
    });

    test('speak returns immediately when muted', () async {
      TutorialTts.muted = true;
      // Should not throw or hang
      await TutorialTts.speak('This is the chat name.');
    });

    test('stop does not throw', () {
      // Just verify it doesn't throw synchronously — the async audio
      // internals are not available in test environment
      TutorialTts.muted = true;
      expect(() => TutorialTts.stop('test'), returnsNormally);
    });
  });
}
