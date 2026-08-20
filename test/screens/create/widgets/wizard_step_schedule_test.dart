import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart'
    as state;
import 'package:onemind_app/screens/create/widgets/wizard_step_schedule.dart';

void main() {
  late state.ScheduleSettings scheduleSettings;

  setUp(() {
    scheduleSettings = state.ScheduleSettings(
      type: state.ScheduleType.once,
      scheduledStartAt: DateTime(2026, 6, 15, 10, 0),
      windows: const [
        state.ScheduleWindow(
          startDay: 'monday',
          startTime: TimeOfDay(hour: 9, minute: 0),
          endDay: 'monday',
          endTime: TimeOfDay(hour: 17, minute: 0),
        ),
      ],
      timezone: 'America/New_York',
      visibleOutsideSchedule: true,
    );
  });

  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
      );

  // Step ① — the mode picker.
  Widget picker({
    ScheduleMode scheduleMode = ScheduleMode.always,
    void Function(ScheduleMode)? onScheduleModeChanged,
    VoidCallback? onContinue,
  }) =>
      wrap(WizardStepSchedule(
        scheduleMode: scheduleMode,
        onScheduleModeChanged: onScheduleModeChanged ?? (_) {},
        onContinue: onContinue ?? () {},
      ));

  // Step ② — the per-mode config screen.
  Widget config({
    ScheduleMode scheduleMode = ScheduleMode.once,
    void Function(state.ScheduleSettings)? onScheduleSettingsChanged,
    VoidCallback? onContinue,
  }) =>
      wrap(WizardStepScheduleConfig(
        scheduleMode: scheduleMode,
        scheduleSettings: scheduleSettings,
        onScheduleSettingsChanged: onScheduleSettingsChanged ?? (_) {},
        onContinue: onContinue ?? () {},
      ));

  group('WizardStepSchedule (mode picker)', () {
    testWidgets('shows heading and the three mode cards', (tester) async {
      await tester.pumpWidget(picker());
      expect(find.text('Set a schedule?'), findsOneWidget);
      expect(find.text('Always Active'), findsOneWidget);
      expect(find.text('Starts at a specific time'), findsOneWidget);
      expect(find.text('Weekly schedule'), findsOneWidget);
    });

    testWidgets('Always Active is the default selection', (tester) async {
      await tester.pumpWidget(picker(scheduleMode: ScheduleMode.always));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.all_inclusive), findsOneWidget);
    });

    testWidgets('tapping a card reports the chosen mode', (tester) async {
      ScheduleMode? captured;
      await tester
          .pumpWidget(picker(onScheduleModeChanged: (m) => captured = m));

      await tester.tap(find.text('Starts at a specific time'));
      await tester.pump();
      expect(captured, ScheduleMode.once);

      await tester.tap(find.text('Weekly schedule'));
      await tester.pump();
      expect(captured, ScheduleMode.recurring);

      await tester.tap(find.text('Always Active'));
      await tester.pump();
      expect(captured, ScheduleMode.always);
    });

    testWidgets('continue button fires onContinue', (tester) async {
      var called = false;
      await tester.pumpWidget(picker(onContinue: () => called = true));
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pump();
      expect(called, true);
    });
  });

  group('Schedule details - Always Active', () {
    // The wizard never shows this step for Always Active anymore (it goes
    // straight to timing, then the dedicated First-deadline step). The widget
    // keeps a defensive empty branch — assert it stays inert.
    testWidgets('renders no config controls (wizard skips this step)',
        (tester) async {
      await tester.pumpWidget(config(scheduleMode: ScheduleMode.always));
      expect(find.text('When should it start?'), findsNothing);
      expect(find.text('Right away'), findsNothing);
      expect(find.text('At a fixed time'), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text('Start Date & Time'), findsNothing);
      expect(find.byIcon(Icons.calendar_today), findsNothing);
      expect(find.text('Timezone'), findsNothing);
    });
  });

  group('Schedule details - One-time', () {
    testWidgets('shows timezone + start date/time pickers', (tester) async {
      await tester.pumpWidget(config(scheduleMode: ScheduleMode.once));
      expect(find.text('Timezone'), findsOneWidget);
      expect(find.text('Start Date & Time'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('formats the start date and time', (tester) async {
      await tester.pumpWidget(config(scheduleMode: ScheduleMode.once));
      expect(find.text('6/15/2026'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget);
    });

    testWidgets('shows "Set an end time" by default', (tester) async {
      await tester.pumpWidget(config(scheduleMode: ScheduleMode.once));
      expect(find.text('Set an end time'), findsOneWidget);
    });
  });

  group('Schedule details - Recurring', () {
    setUp(() {
      scheduleSettings =
          scheduleSettings.copyWith(type: state.ScheduleType.recurring);
    });

    testWidgets('shows timezone, windows header, add button, window card',
        (tester) async {
      await tester.pumpWidget(config(scheduleMode: ScheduleMode.recurring));
      expect(find.text('Timezone'), findsOneWidget);
      expect(find.text('Schedule Windows'), findsOneWidget);
      expect(find.text('Add Window'), findsOneWidget);
      expect(find.text('Window 1'), findsOneWidget);
    });

    testWidgets('Add Window reports an extra window', (tester) async {
      state.ScheduleSettings? captured;
      await tester.pumpWidget(config(
        scheduleMode: ScheduleMode.recurring,
        onScheduleSettingsChanged: (s) => captured = s,
      ));
      await tester.ensureVisible(find.text('Add Window'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Window'));
      await tester.pump();
      expect(captured?.windows.length, 2);
    });
  });
}
