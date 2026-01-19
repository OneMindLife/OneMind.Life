import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/adaptive_duration_section.dart';

void main() {
  group('AdaptiveDurationSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveDurationSection(
              settings: AdaptiveDurationSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Adaptive Duration'), findsOneWidget);
    });

    testWidgets('displays helper text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveDurationSection(
              settings: AdaptiveDurationSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Auto-adjust phase duration based on participation'),
        findsOneWidget,
      );
    });

    testWidgets('displays enable switch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveDurationSection(
              settings: AdaptiveDurationSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Enable adaptive duration'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('shows disabled subtitle when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveDurationSection(
              settings: AdaptiveDurationSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Fixed phase durations'), findsOneWidget);
    });

    testWidgets('shows enabled subtitle when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdaptiveDurationSection(
                settings: const AdaptiveDurationSettings(
                  enabled: true,
                  adjustmentPercent: 20,
                  minDurationSeconds: 60,
                  maxDurationSeconds: 3600,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('Duration adjusts based on participation'),
        findsOneWidget,
      );
    });

    testWidgets('hides options when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveDurationSection(
              settings: AdaptiveDurationSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Options should be hidden when disabled
      expect(find.text('Minimum duration'), findsNothing);
      expect(find.text('Maximum duration'), findsNothing);
    });

    testWidgets('shows options when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdaptiveDurationSection(
                settings: const AdaptiveDurationSettings(
                  enabled: true,
                  adjustmentPercent: 20,
                  minDurationSeconds: 60,
                  maxDurationSeconds: 3600,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Minimum duration'), findsOneWidget);
      expect(find.text('Maximum duration'), findsOneWidget);
    });

    testWidgets('displays threshold explanation text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdaptiveDurationSection(
                settings: const AdaptiveDurationSettings(
                  enabled: true,
                  adjustmentPercent: 20,
                  minDurationSeconds: 60,
                  maxDurationSeconds: 3600,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Now uses early advance thresholds instead of separate threshold count
      expect(
        find.text('Uses early advance thresholds to determine participation'),
        findsOneWidget,
      );
    });

    testWidgets('displays adjustment slider label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdaptiveDurationSection(
                settings: const AdaptiveDurationSettings(
                  enabled: true,
                  adjustmentPercent: 25,
                  minDurationSeconds: 60,
                  maxDurationSeconds: 3600,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Adjustment: 25%'), findsOneWidget);
    });

    testWidgets('calls onChanged when toggling enabled', (tester) async {
      AdaptiveDurationSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveDurationSection(
              settings: AdaptiveDurationSettings.defaults(),
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
  });
}
