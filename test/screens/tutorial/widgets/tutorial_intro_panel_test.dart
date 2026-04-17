import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/widgets/tutorial_intro_panel.dart';

import '../../../helpers/pump_app.dart';

void main() {
  group('TutorialIntroPanel', () {
    testWidgets('displays play button', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () {},
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('See how it works'), findsOneWidget);
    });

    testWidgets('calls onSelect with saturday key when play tapped',
        (tester) async {
      String? selectedKey;

      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (key) => selectedKey = key,
          onSkip: () {},
        ),
      );

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();

      expect(selectedKey, 'saturday');
    });

    testWidgets('displays skip button', (tester) async {
      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () {},
        ),
      );

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('calls onSkip when skip button tapped', (tester) async {
      var skipCalled = false;

      await tester.pumpApp(
        TutorialIntroPanel(
          onSelect: (_) {},
          onSkip: () => skipCalled = true,
        ),
      );

      await tester.tap(find.text('Skip'));
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
