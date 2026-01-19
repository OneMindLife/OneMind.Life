import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/minimum_advance_section.dart';

void main() {
  group('MinimumAdvanceSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Minimum to Advance'), findsOneWidget);
    });

    testWidgets('displays helper text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('If not met when timer ends, time extends automatically'),
        findsOneWidget,
      );
    });

    testWidgets('displays proposing minimum input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Proposing minimum'), findsOneWidget);
    });

    testWidgets('displays rating minimum input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Rating minimum'), findsOneWidget);
    });

    testWidgets('displays default values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Default proposingMinimum is 3 (users can't rate own, need 2+ visible)
      // Default ratingMinimum is 2
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('displays custom values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: const MinimumSettings(
                proposingMinimum: 3,
                ratingMinimum: 5,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('calls onChanged when incrementing proposing minimum',
        (tester) async {
      MinimumSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      // Tap the first add button (proposing)
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.proposingMinimum, 4); // 3 + 1 (default is 3)
    });

    testWidgets('calls onChanged when incrementing rating minimum',
        (tester) async {
      MinimumSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      // Tap the last add button (rating)
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.ratingMinimum, 3); // 2 + 1
    });
  });
}
