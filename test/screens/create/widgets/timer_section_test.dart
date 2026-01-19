import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/timer_section.dart';

void main() {
  group('TimerSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerSection(
              settings: TimerSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Timers'), findsOneWidget);
    });

    testWidgets('displays proposing and rating presets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerSection(
              settings: TimerSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Proposing'), findsOneWidget);
      expect(find.text('Rating'), findsOneWidget);
    });

    testWidgets('displays timer preset options including Custom', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerSection(
              settings: TimerSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Each preset section shows these options (max is 1 day now)
      expect(find.text('5 min'), findsNWidgets(2));
      expect(find.text('30 min'), findsNWidgets(2));
      expect(find.text('1 hour'), findsNWidgets(2));
      expect(find.text('1 day'), findsNWidgets(2));
      expect(find.text('Custom'), findsNWidgets(2));
    });

    testWidgets('calls onChanged when proposing preset selected', (tester) async {
      TimerSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerSection(
              settings: TimerSettings.defaults(),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      // Tap the first '5 min' chip (proposing)
      await tester.tap(find.text('5 min').first);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.proposingPreset, '5min');
      expect(updatedSettings!.proposingDuration, 300);
    });

    testWidgets('calls onChanged when rating preset selected', (tester) async {
      TimerSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerSection(
              settings: TimerSettings.defaults(),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      // Tap the second '30 min' chip (rating)
      await tester.tap(find.text('30 min').last);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.ratingPreset, '30min');
      expect(updatedSettings!.ratingDuration, 1800);
    });

    testWidgets('highlights selected presets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerSection(
              settings: const TimerSettings(
                proposingPreset: '1hour',
                ratingPreset: '1day',
                proposingDuration: 3600,
                ratingDuration: 86400,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify the selected chips are marked
      final proposingChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('1 hour').first,
          matching: find.byType(ChoiceChip),
        ).first,
      );
      expect(proposingChip.selected, isTrue);

      final ratingChip = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('1 day').last,
          matching: find.byType(ChoiceChip),
        ).first,
      );
      expect(ratingChip.selected, isTrue);
    });

    testWidgets('selecting Custom shows hour/minute fields', (tester) async {
      TimerSettings settings = TimerSettings.defaults();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return TimerSection(
                    settings: settings,
                    onChanged: (v) => setState(() => settings = v),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Initially no hour/minute fields
      expect(find.text('Hours'), findsNothing);
      expect(find.text('Minutes'), findsNothing);

      // Tap the first Custom chip (proposing)
      await tester.tap(find.text('Custom').first);
      await tester.pumpAndSettle();

      // Now hour/minute fields should appear
      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('Minutes'), findsOneWidget);

      // Verify state was updated with custom preset
      expect(settings.proposingPreset, 'custom');
    });

    testWidgets('custom duration calculates correctly from hours and minutes', (tester) async {
      TimerSettings settings = const TimerSettings(
        proposingPreset: 'custom',
        ratingPreset: '1day',
        proposingDuration: 300, // 5 minutes
        ratingDuration: 86400,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return TimerSection(
                    settings: settings,
                    onChanged: (v) => setState(() => settings = v),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Should show hour/minute fields since custom is selected
      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('Minutes'), findsOneWidget);

      // Clear and enter new values
      await tester.enterText(find.byType(TextField).first, '2');
      await tester.enterText(find.byType(TextField).at(1), '30');
      await tester.pumpAndSettle();

      // 2 hours 30 minutes = 9000 seconds
      expect(settings.proposingDuration, 9000);
    });

    testWidgets('custom duration respects minimum of 1 minute', (tester) async {
      TimerSettings settings = const TimerSettings(
        proposingPreset: 'custom',
        ratingPreset: '1day',
        proposingDuration: 300,
        ratingDuration: 86400,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return TimerSection(
                    settings: settings,
                    onChanged: (v) => setState(() => settings = v),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Enter 0 hours 0 minutes (should clamp to 1 minute = 60 seconds)
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.enterText(find.byType(TextField).at(1), '0');
      await tester.pumpAndSettle();

      // Should clamp to minimum 60 seconds
      expect(settings.proposingDuration, 60);
    });
  });
}
