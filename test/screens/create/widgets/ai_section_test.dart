import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/ai_section.dart';

void main() {
  group('AISection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: AISettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('AI Participant'), findsOneWidget);
    });

    testWidgets('displays enable switch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: AISettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Enable OneMind AI'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('hides proposition count when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: const AISettings(enabled: false, propositionCount: 3),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('AI propositions per round'), findsNothing);
    });

    testWidgets('shows proposition count when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: const AISettings(enabled: true, propositionCount: 3),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('AI propositions per round'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('calls onChanged when toggling enabled', (tester) async {
      AISettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: const AISettings(enabled: false, propositionCount: 3),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.enabled, isTrue);
    });

    testWidgets('calls onChanged when incrementing proposition count',
        (tester) async {
      AISettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: const AISettings(enabled: true, propositionCount: 3),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.propositionCount, 4);
    });

    testWidgets('calls onChanged when decrementing proposition count',
        (tester) async {
      AISettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: const AISettings(enabled: true, propositionCount: 3),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.propositionCount, 2);
    });

    testWidgets('respects min limit of 1', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: const AISettings(enabled: true, propositionCount: 1),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final decrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(decrementButton.onPressed, isNull);
    });

    testWidgets('respects max limit of 10', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AISection(
              settings: const AISettings(enabled: true, propositionCount: 10),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final incrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(incrementButton.onPressed, isNull);
    });
  });
}
