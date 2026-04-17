import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart'
    as state;
import 'package:onemind_app/screens/create/widgets/wizard_step_schedule.dart';

void main() {
  group('WizardStepSchedule', () {
    late bool enableSchedule;
    late state.ScheduleSettings scheduleSettings;

    setUp(() {
      enableSchedule = false;
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

    Widget buildWidget({
      void Function(bool)? onEnableScheduleChanged,
      void Function(state.ScheduleSettings)? onScheduleSettingsChanged,
      VoidCallback? onContinue,
    }) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: WizardStepSchedule(
            enableSchedule: enableSchedule,
            scheduleSettings: scheduleSettings,
            onEnableScheduleChanged: onEnableScheduleChanged ?? (_) {},
            onScheduleSettingsChanged:
                onScheduleSettingsChanged ?? (_) {},
            onContinue: onContinue ?? () {},
          ),
        ),
      );
    }

    group('Layout', () {
      testWidgets('displays calendar icon and heading', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
        expect(find.text('Set a schedule?'), findsOneWidget);
      });

      testWidgets('displays all three mode cards', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Always Active'), findsOneWidget);
        expect(find.text('Starts at a specific time'), findsOneWidget);
        expect(find.text('Weekly schedule'), findsOneWidget);
      });

      testWidgets('displays continue button', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      });
    });

    group('Mode Selection', () {
      testWidgets('Always Active is selected by default', (tester) async {
        await tester.pumpWidget(buildWidget());

        // Check icon appears (selected cards show a check_circle)
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        // The always-active card has the all_inclusive icon
        expect(find.byIcon(Icons.all_inclusive), findsOneWidget);
      });

      testWidgets('tapping One-time enables schedule with once type',
          (tester) async {
        bool? capturedEnable;
        state.ScheduleSettings? capturedSettings;

        await tester.pumpWidget(buildWidget(
          onEnableScheduleChanged: (v) => capturedEnable = v,
          onScheduleSettingsChanged: (s) => capturedSettings = s,
        ));

        await tester.tap(find.text('Starts at a specific time'));
        await tester.pump();

        expect(capturedEnable, true);
        expect(capturedSettings?.type, state.ScheduleType.once);
      });

      testWidgets('tapping Recurring enables schedule with recurring type',
          (tester) async {
        bool? capturedEnable;
        state.ScheduleSettings? capturedSettings;

        await tester.pumpWidget(buildWidget(
          onEnableScheduleChanged: (v) => capturedEnable = v,
          onScheduleSettingsChanged: (s) => capturedSettings = s,
        ));

        await tester.tap(find.text('Weekly schedule'));
        await tester.pump();

        expect(capturedEnable, true);
        expect(capturedSettings?.type, state.ScheduleType.recurring);
      });

      testWidgets('tapping Always Active disables schedule', (tester) async {
        enableSchedule = true;
        bool? capturedEnable;

        await tester.pumpWidget(buildWidget(
          onEnableScheduleChanged: (v) => capturedEnable = v,
        ));

        await tester.tap(find.text('Always Active'));
        await tester.pump();

        expect(capturedEnable, false);
      });
    });

    group('One-Time Settings', () {
      setUp(() {
        enableSchedule = true;
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.once,
        );
      });

      testWidgets('shows timezone and date/time pickers when once selected',
          (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Timezone'), findsOneWidget);
        expect(find.text('Start Date & Time'), findsOneWidget);
        expect(find.byIcon(Icons.calendar_today), findsOneWidget);
        expect(find.byIcon(Icons.access_time), findsOneWidget);
      });

      testWidgets('displays formatted date', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('6/15/2026'), findsOneWidget);
      });

      testWidgets('displays formatted time', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('10:00 AM'), findsOneWidget);
      });

      testWidgets('shows visibility toggle', (tester) async {
        await tester.pumpWidget(buildWidget());

        await tester.ensureVisible(find.text('Hide when outside schedule'));
        await tester.pumpAndSettle();
        expect(find.text('Hide when outside schedule'), findsOneWidget);
        expect(find.byType(SwitchListTile), findsOneWidget);
      });

      testWidgets('shows "Set an end time" button by default',
          (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Set an end time'), findsOneWidget);
      });

      testWidgets('shows end date/time pickers when end time is set',
          (tester) async {
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.once,
          scheduledEndAt: DateTime(2026, 6, 15, 18, 0),
        );

        await tester.pumpWidget(buildWidget());

        expect(
            find.text('End Date & Time (optional)'), findsOneWidget);
        expect(find.text('Remove end time'), findsOneWidget);
        // Two date pickers (start + end)
        expect(find.byIcon(Icons.calendar_today), findsNWidgets(2));
        expect(find.byIcon(Icons.access_time), findsNWidgets(2));
      });

      testWidgets('calls onScheduleSettingsChanged to clear end time',
          (tester) async {
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.once,
          scheduledEndAt: DateTime(2026, 6, 15, 18, 0),
        );
        state.ScheduleSettings? captured;

        await tester.pumpWidget(buildWidget(
          onScheduleSettingsChanged: (s) => captured = s,
        ));

        await tester.ensureVisible(find.text('Remove end time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove end time'));
        await tester.pump();

        expect(captured?.scheduledEndAt, isNull);
      });

      testWidgets(
          'calls onScheduleSettingsChanged with end time when Set tapped',
          (tester) async {
        state.ScheduleSettings? captured;

        await tester.pumpWidget(buildWidget(
          onScheduleSettingsChanged: (s) => captured = s,
        ));

        await tester.ensureVisible(find.text('Set an end time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Set an end time'));
        await tester.pump();

        expect(captured?.scheduledEndAt, isNotNull);
      });
    });

    group('Recurring Settings', () {
      setUp(() {
        enableSchedule = true;
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.recurring,
        );
      });

      testWidgets('shows timezone, windows header, and add button',
          (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Timezone'), findsOneWidget);
        expect(find.text('Schedule Windows'), findsOneWidget);
        expect(find.text('Add Window'), findsOneWidget);
      });

      testWidgets('displays window card with start/end controls',
          (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Window 1'), findsOneWidget);
        expect(find.text('Start Day'), findsOneWidget);
        expect(find.text('End Day'), findsOneWidget);
      });

      testWidgets('calls onScheduleSettingsChanged when Add Window tapped',
          (tester) async {
        state.ScheduleSettings? captured;

        await tester.pumpWidget(buildWidget(
          onScheduleSettingsChanged: (s) => captured = s,
        ));

        await tester.ensureVisible(find.text('Add Window'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Window'));
        await tester.pump();

        expect(captured?.windows.length, 2);
      });

      testWidgets('shows delete button only with multiple windows',
          (tester) async {
        // One window — no delete
        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.delete_outline), findsNothing);

        // Two windows — delete buttons appear
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.recurring,
          windows: const [
            state.ScheduleWindow(
              startDay: 'monday',
              startTime: TimeOfDay(hour: 9, minute: 0),
              endDay: 'monday',
              endTime: TimeOfDay(hour: 12, minute: 0),
            ),
            state.ScheduleWindow(
              startDay: 'wednesday',
              startTime: TimeOfDay(hour: 14, minute: 0),
              endDay: 'wednesday',
              endTime: TimeOfDay(hour: 17, minute: 0),
            ),
          ],
        );

        await tester.pumpWidget(buildWidget());
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
        expect(find.text('Window 1'), findsOneWidget);
        expect(find.text('Window 2'), findsOneWidget);
      });

      testWidgets('shows visibility toggle', (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Hide when outside schedule'), findsOneWidget);
      });
    });

    group('Visibility Toggle', () {
      setUp(() {
        enableSchedule = true;
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.once,
        );
      });

      testWidgets('shows correct subtitle when visible outside schedule',
          (tester) async {
        await tester.pumpWidget(buildWidget());

        expect(find.text('Chat visible but paused outside schedule'),
            findsOneWidget);
      });

      testWidgets('shows correct subtitle when hidden outside schedule',
          (tester) async {
        scheduleSettings = scheduleSettings.copyWith(
          visibleOutsideSchedule: false,
        );

        await tester.pumpWidget(buildWidget());

        expect(find.text('Chat hidden until next scheduled window'),
            findsOneWidget);
      });

      testWidgets('calls onScheduleSettingsChanged when toggled',
          (tester) async {
        state.ScheduleSettings? captured;

        await tester.pumpWidget(buildWidget(
          onScheduleSettingsChanged: (s) => captured = s,
        ));

        await tester.ensureVisible(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch));
        await tester.pump();

        // Switch is inverted: toggling "Hide" on → visibleOutsideSchedule = false
        expect(captured?.visibleOutsideSchedule, false);
      });

      testWidgets('not shown when Always Active mode', (tester) async {
        enableSchedule = false;

        await tester.pumpWidget(buildWidget());

        expect(find.text('Hide when outside schedule'), findsNothing);
        expect(find.byType(SwitchListTile), findsNothing);
      });
    });

    group('Navigation', () {
      testWidgets('calls onContinue when continue button tapped',
          (tester) async {
        bool continueCalled = false;

        await tester.pumpWidget(buildWidget(
          onContinue: () => continueCalled = true,
        ));

        await tester.tap(find.byIcon(Icons.arrow_forward));
        await tester.pump();

        expect(continueCalled, true);
      });
    });

    group('Time Formatting', () {
      testWidgets('formats noon correctly', (tester) async {
        enableSchedule = true;
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.once,
          scheduledStartAt: DateTime(2026, 6, 15, 12, 0),
        );

        await tester.pumpWidget(buildWidget());

        expect(find.text('12:00 PM'), findsOneWidget);
      });

      testWidgets('formats midnight correctly', (tester) async {
        enableSchedule = true;
        scheduleSettings = scheduleSettings.copyWith(
          type: state.ScheduleType.once,
          scheduledStartAt: DateTime(2026, 6, 15, 0, 0),
        );

        await tester.pumpWidget(buildWidget());

        expect(find.text('12:00 AM'), findsOneWidget);
      });
    });
  });
}
