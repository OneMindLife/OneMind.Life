import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/widgets/tutorial_intro_panel.dart';
import 'package:onemind_app/widgets/language_selector.dart';

import '../../../helpers/pump_app.dart';

void main() {
  group('TutorialIntroPanel', () {
    testWidgets('displays language selector', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () {},
          onSkip: () {},
        ),
      );

      expect(find.byType(LanguageSelector), findsOneWidget);
    });

    testWidgets('displays welcome message', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () {},
          onSkip: () {},
        ),
      );

      expect(find.text('Welcome to OneMind'), findsOneWidget);
    });

    testWidgets('displays the question', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () {},
          onSkip: () {},
        ),
      );

      expect(find.textContaining('What do we value?'), findsOneWidget);
    });

    testWidgets('displays bullet points of what user will learn', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () {},
          onSkip: () {},
        ),
      );

      expect(find.text('Submit your ideas anonymously'), findsOneWidget);
      expect(find.text('Rate ideas from others'), findsOneWidget);
      expect(find.text('See how consensus is reached'), findsOneWidget);
    });

    testWidgets('displays start button', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () {},
          onSkip: () {},
        ),
      );

      expect(find.text('Start Tutorial'), findsOneWidget);
    });

    testWidgets('displays skip button', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () {},
          onSkip: () {},
        ),
      );

      expect(find.text('Skip tutorial'), findsOneWidget);
    });

    testWidgets('calls onStart when start button tapped', (tester) async {
      var startCalled = false;

      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () => startCalled = true,
          onSkip: () {},
        ),
      );

      await tester.ensureVisible(find.text('Start Tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Tutorial'));
      await tester.pumpAndSettle();

      expect(startCalled, isTrue);
    });

    testWidgets('calls onSkip when skip button tapped', (tester) async {
      var skipCalled = false;

      await tester.pumpApp(
        TutorialIntroPanel(
          onStart: () {},
          onSkip: () => skipCalled = true,
        ),
      );

      await tester.ensureVisible(find.text('Skip tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip tutorial'));
      await tester.pumpAndSettle();

      expect(skipCalled, isTrue);
    });
  });
}
