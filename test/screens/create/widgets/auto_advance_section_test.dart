import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/auto_advance_section.dart';

void main() {
  group('AutoAdvanceSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AutoAdvanceSection(
              settings: AutoAdvanceSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Auto-Advance At'), findsOneWidget);
    });

    testWidgets('displays helper text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AutoAdvanceSection(
              settings: AutoAdvanceSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Skip timer early when thresholds are reached'),
        findsOneWidget,
      );
    });

    testWidgets('displays both enable switches', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AutoAdvanceSection(
              settings: AutoAdvanceSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Enable auto-advance (proposing)'), findsOneWidget);
      expect(find.text('Enable auto-advance (rating)'), findsOneWidget);
    });

    testWidgets('hides proposing options when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: false,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: false,
                  ratingThresholdPercent: 80,
                  ratingThresholdCount: 5,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('When 80% of participants submit'), findsNothing);
    });

    testWidgets('shows proposing options when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: true,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: false,
                  ratingThresholdPercent: 80,
                  ratingThresholdCount: 5,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Percent threshold first, then minimum
      expect(find.text('When 80% of participants submit'), findsOneWidget);
      expect(find.text('Minimum propositions required'), findsOneWidget);
    });

    testWidgets('shows rating options when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: false,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: true,
                  ratingThresholdPercent: 75,
                  ratingThresholdCount: 10,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Only minimum for rating (percent removed due to math constraints)
      expect(find.text('Minimum avg raters per proposition'), findsOneWidget);
    });

    testWidgets('calls onChanged when toggling proposing', (tester) async {
      AutoAdvanceSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: AutoAdvanceSettings.defaults(),
                onChanged: (v) => updatedSettings = v,
              ),
            ),
          ),
        ),
      );

      // Tap the proposing switch
      final switches = find.byType(Switch);
      await tester.tap(switches.first);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.enableProposing, isTrue);
    });

    testWidgets('calls onChanged when toggling rating', (tester) async {
      AutoAdvanceSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: AutoAdvanceSettings.defaults(),
                onChanged: (v) => updatedSettings = v,
              ),
            ),
          ),
        ),
      );

      // Tap the rating switch (second one)
      final switches = find.byType(Switch);
      await tester.tap(switches.last);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.enableRating, isTrue);
    });

    testWidgets('shows both option sections when both enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: true,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: true,
                  ratingThresholdPercent: 75,
                  ratingThresholdCount: 10,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Proposing shows minimum, rating shows minimum avg raters
      expect(find.text('Minimum propositions required'), findsOneWidget);
      expect(find.text('Minimum avg raters per proposition'), findsOneWidget);
    });
  });
}
