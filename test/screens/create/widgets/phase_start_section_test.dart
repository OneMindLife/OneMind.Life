import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart' as state;
import 'package:onemind_app/screens/create/widgets/phase_start_section.dart';

void main() {
  group('PhaseStartSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Facilitation Mode'), findsOneWidget);
    });

    testWidgets('displays only Manual and Auto options (no Scheduled)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // With manual facilitation, rating start mode section is shown
      // So there are 2 sets of Manual/Auto - one for facilitation, one for rating start mode
      expect(find.text('Manual'), findsNWidgets(2));
      expect(find.text('Auto'), findsNWidgets(2));
      // Schedule is now a separate toggle, not a start mode
      expect(find.text('Scheduled'), findsNothing);
    });

    testWidgets('hides rating start mode section when facilitation is auto',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.auto,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // With auto facilitation, rating start mode section is hidden
      // Only 1 Manual/Auto pair for facilitation mode
      expect(find.text('Manual'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Rating Start Mode'), findsNothing);
    });

    testWidgets('shows rating start mode section when facilitation is manual',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // With manual facilitation, rating start mode section is shown
      expect(find.text('Rating Start Mode'), findsOneWidget);
      expect(find.text('Manual'), findsNWidgets(2));
      expect(find.text('Auto'), findsNWidgets(2));
    });

    testWidgets('hides auto-start count in manual mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Auto-start at X participants'), findsNothing);
    });

    testWidgets('shows auto-start count in auto mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.auto,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Auto-start at X participants'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('displays Enable Schedule toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Enable Schedule'), findsOneWidget);
      expect(find.text('Restrict when the chat room is open'), findsOneWidget);
    });

    testWidgets('hides schedule settings when enableSchedule is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // Schedule settings card specific text
      expect(find.text('One-time'), findsNothing);
      expect(find.text('Recurring'), findsNothing);
    });

    testWidgets('shows schedule settings when enableSchedule is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhaseStartSection(
                startMode: StartMode.manual,
                ratingStartMode: StartMode.auto,
                autoStartCount: 5,
                enableSchedule: true,
                scheduleSettings: state.ScheduleSettings.defaults(),
                onStartModeChanged: (_) {},
                onRatingStartModeChanged: (_) {},
                onAutoStartCountChanged: (_) {},
                onEnableScheduleChanged: (_) {},
                onScheduleSettingsChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('One-time'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);
    });

    testWidgets('schedule can be enabled with auto facilitation mode',
        (tester) async {
      // This tests the orthogonality of schedule and facilitation
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhaseStartSection(
                startMode: StartMode.auto,
                ratingStartMode: StartMode.auto,
                autoStartCount: 5,
                enableSchedule: true,
                scheduleSettings: state.ScheduleSettings.defaults(),
                onStartModeChanged: (_) {},
                onRatingStartModeChanged: (_) {},
                onAutoStartCountChanged: (_) {},
                onEnableScheduleChanged: (_) {},
                onScheduleSettingsChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Both auto-start count (from auto mode) and schedule settings should be visible
      expect(find.text('Auto-start at X participants'), findsOneWidget);
      expect(find.text('One-time'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);
    });

    testWidgets('calls onStartModeChanged when selecting auto',
        (tester) async {
      StartMode? updatedMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (v) => updatedMode = v,
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // Tap the first 'Auto' button (facilitation mode, not rating start mode)
      await tester.tap(find.text('Auto').first);
      await tester.pump();

      expect(updatedMode, StartMode.auto);
    });

    testWidgets('calls onAutoStartCountChanged when incrementing',
        (tester) async {
      int? updatedCount;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.auto,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (v) => updatedCount = v,
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(updatedCount, 6);
    });

    testWidgets('respects min limit of 3 for auto-start count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.auto,
              ratingStartMode: StartMode.auto,
              autoStartCount: 3,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      final decrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(decrementButton.onPressed, isNull);
    });

    testWidgets('calls onEnableScheduleChanged when toggling schedule',
        (tester) async {
      bool? updatedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhaseStartSection(
              startMode: StartMode.manual,
              ratingStartMode: StartMode.auto,
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onStartModeChanged: (_) {},
              onRatingStartModeChanged: (_) {},
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (v) => updatedValue = v,
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(updatedValue, true);
    });

    testWidgets('calls onScheduleSettingsChanged for schedule type',
        (tester) async {
      state.ScheduleSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhaseStartSection(
                startMode: StartMode.manual,
                ratingStartMode: StartMode.auto,
                autoStartCount: 5,
                enableSchedule: true,
                scheduleSettings: state.ScheduleSettings.defaults(),
                onStartModeChanged: (_) {},
                onRatingStartModeChanged: (_) {},
                onAutoStartCountChanged: (_) {},
                onEnableScheduleChanged: (_) {},
                onScheduleSettingsChanged: (v) => updatedSettings = v,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Recurring'));
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.type, state.ScheduleType.recurring);
    });
  });
}
