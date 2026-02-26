import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/widgets/tutorial_intro_panel.dart';

import '../../../helpers/pump_app.dart';

void main() {
  group('TutorialIntroPanel', () {
    testWidgets('displays welcome title', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () {},
        ),
      );

      expect(find.text('Welcome to OneMind!'), findsOneWidget);
    });

    testWidgets('displays all 6 template cards with correct names',
        (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () {},
        ),
      );

      expect(find.text('Personal Decision'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Community Decision'), findsOneWidget);
      expect(find.text('Workplace Culture'), findsOneWidget);
      expect(find.text('City Budget'), findsOneWidget);
      expect(find.text('Global Issues'), findsOneWidget);
    });

    testWidgets('calls onSelect with correct key when template card tapped',
        (tester) async {
      String? selectedKey;

      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (key) => selectedKey = key,
          onSkip: () {},
        ),
      );

      await tester.tap(find.text('Community Decision'));
      await tester.pumpAndSettle();

      expect(selectedKey, 'community');
    });

    testWidgets('calls onSelect with workplace key', (tester) async {
      String? selectedKey;

      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (key) => selectedKey = key,
          onSkip: () {},
        ),
      );

      await tester.ensureVisible(find.text('Workplace Culture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workplace Culture'));
      await tester.pumpAndSettle();

      expect(selectedKey, 'workplace');
    });

    testWidgets('displays skip button', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () {},
        ),
      );

      expect(find.text('Skip tutorial'), findsOneWidget);
    });

    testWidgets('calls onSkip when skip button tapped', (tester) async {
      var skipCalled = false;

      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () => skipCalled = true,
        ),
      );

      await tester.ensureVisible(find.text('Skip tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip tutorial'));
      await tester.pumpAndSettle();

      expect(skipCalled, isTrue);
    });

    testWidgets('displays legal text', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () {},
        ),
      );

      expect(find.textContaining('By continuing'), findsOneWidget);
    });
  });
}
