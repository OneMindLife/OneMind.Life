import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/tutorial/widgets/tutorial_template_panel.dart';

import '../../../helpers/pump_app.dart';

void main() {
  group('TutorialTemplatePanel', () {
    testWidgets('displays header text', (tester) async {
      await tester.pumpApp(
        TutorialTemplatePanel(
          onSelect: (_) {},
          onBack: () {},
        ),
      );

      expect(find.text('Personalize Your Tutorial'), findsOneWidget);
      expect(find.text('Choose a scenario that matters to you'), findsOneWidget);
    });

    testWidgets('displays all template cards', (tester) async {
      await tester.pumpApp(
        TutorialTemplatePanel(
          onSelect: (_) {},
          onBack: () {},
        ),
      );

      expect(find.text('Personal Decision'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('Community Decision'), findsOneWidget);
      expect(find.text('Workplace Culture'), findsOneWidget);
      expect(find.text('City Budget'), findsOneWidget);
      expect(find.text('Global Issues'), findsOneWidget);
    });

    testWidgets('displays template descriptions', (tester) async {
      await tester.pumpApp(
        TutorialTemplatePanel(
          onSelect: (_) {},
          onBack: () {},
        ),
      );

      expect(find.text('What should I do after graduation?'), findsOneWidget);
      expect(find.text('Where should we go on vacation?'), findsOneWidget);
      expect(find.text('What should our neighborhood do together?'), findsOneWidget);
      expect(find.text('What should our team focus on?'), findsOneWidget);
      expect(find.text('How should we spend the city budget?'), findsOneWidget);
      expect(find.text('What global issue matters most?'), findsOneWidget);
    });

    testWidgets('tapping a template calls onSelect with correct key', (tester) async {
      String? selectedKey;

      await tester.pumpApp(
        TutorialTemplatePanel(
          onSelect: (key) => selectedKey = key,
          onBack: () {},
        ),
      );

      await tester.tap(find.text('Community Decision'));
      await tester.pumpAndSettle();

      expect(selectedKey, 'community');
    });

    testWidgets('tapping workplace template calls onSelect with workplace key', (tester) async {
      String? selectedKey;

      await tester.pumpApp(
        TutorialTemplatePanel(
          onSelect: (key) => selectedKey = key,
          onBack: () {},
        ),
      );

      await tester.tap(find.text('Workplace Culture'));
      await tester.pumpAndSettle();

      expect(selectedKey, 'workplace');
    });

    testWidgets('back button calls onBack', (tester) async {
      var backCalled = false;

      await tester.pumpApp(
        TutorialTemplatePanel(
          onSelect: (_) {},
          onBack: () => backCalled = true,
        ),
      );

      await tester.tap(find.byKey(const Key('template-back-button')));
      await tester.pumpAndSettle();

      expect(backCalled, isTrue);
    });
  });
}
