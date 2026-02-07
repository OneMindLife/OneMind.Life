import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart' as state;
import 'package:onemind_app/screens/create/widgets/schedule_settings.dart';

void main() {
  group('ScheduleSettingsCard', () {
    late ScheduleType scheduleType;
    late DateTime scheduledStartAt;
    late List<state.ScheduleWindow> windows;
    late String scheduleTimezone;
    late bool visibleOutsideSchedule;

    setUp(() {
      scheduleType = ScheduleType.once;
      scheduledStartAt = DateTime(2026, 1, 15, 10, 0);
      windows = [
        const state.ScheduleWindow(
          startDay: 'monday',
          startTime: TimeOfDay(hour: 9, minute: 0),
          endDay: 'monday',
          endTime: TimeOfDay(hour: 17, minute: 0),
        ),
      ];
      scheduleTimezone = 'America/New_York';
      visibleOutsideSchedule = true;
    });

    Widget createTestWidget({
      void Function(ScheduleType)? onScheduleTypeChanged,
      void Function(DateTime)? onScheduledStartAtChanged,
      void Function(List<state.ScheduleWindow>)? onWindowsChanged,
      void Function(String)? onScheduleTimezoneChanged,
      void Function(bool)? onVisibleOutsideScheduleChanged,
    }) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScheduleSettingsCard(
              scheduleType: scheduleType,
              scheduledStartAt: scheduledStartAt,
              windows: windows,
              scheduleTimezone: scheduleTimezone,
              visibleOutsideSchedule: visibleOutsideSchedule,
              onScheduleTypeChanged: onScheduleTypeChanged ?? (_) {},
              onScheduledStartAtChanged: onScheduledStartAtChanged ?? (_) {},
              onWindowsChanged: onWindowsChanged ?? (_) {},
              onScheduleTimezoneChanged: onScheduleTimezoneChanged ?? (_) {},
              onVisibleOutsideScheduleChanged:
                  onVisibleOutsideScheduleChanged ?? (_) {},
            ),
          ),
        ),
      );
    }

    group('Schedule Type Selection', () {
      testWidgets('displays schedule type segmented button', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Schedule Type'), findsOneWidget);
        expect(find.byType(SegmentedButton<ScheduleType>), findsOneWidget);
      });

      testWidgets('shows One-time and Recurring options', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('One-time'), findsOneWidget);
        expect(find.text('Recurring'), findsOneWidget);
      });

      testWidgets('calls onScheduleTypeChanged when type changes',
          (tester) async {
        ScheduleType? changedType;

        await tester.pumpWidget(createTestWidget(
          onScheduleTypeChanged: (type) => changedType = type,
        ));

        // Tap on Recurring
        await tester.tap(find.text('Recurring'));
        await tester.pump();

        expect(changedType, ScheduleType.recurring);
      });
    });

    group('One-Time Schedule', () {
      testWidgets('displays date picker button in one-time mode',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Start Date & Time'), findsOneWidget);
        expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      });

      testWidgets('displays time picker button in one-time mode',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.byIcon(Icons.access_time), findsOneWidget);
      });

      testWidgets('displays formatted date', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Format is M/D/YYYY
        expect(find.text('1/15/2026'), findsOneWidget);
      });

      testWidgets('displays formatted time', (tester) async {
        await tester.pumpWidget(createTestWidget());

        // 10:00 AM
        expect(find.text('10:00 AM'), findsOneWidget);
      });
    });

    group('Recurring Schedule', () {
      setUp(() {
        scheduleType = ScheduleType.recurring;
      });

      testWidgets('displays timezone autocomplete in recurring mode',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Timezone'), findsOneWidget);
        // Timezone uses Autocomplete widget now
        expect(find.byType(Autocomplete<String>), findsOneWidget);
        // Day dropdowns are still DropdownButtonFormField
        expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
      });

      testWidgets('displays schedule windows section in recurring mode',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Schedule Windows'), findsOneWidget);
      });

      testWidgets('displays Add Window button in recurring mode',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Add Window'), findsOneWidget);
      });

      testWidgets('displays window card with start/end day dropdowns',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Window 1'), findsOneWidget);
        expect(find.text('Start Day'), findsOneWidget);
        expect(find.text('End Day'), findsOneWidget);
      });

      testWidgets('calls onWindowsChanged when Add Window is tapped',
          (tester) async {
        List<state.ScheduleWindow>? changedWindows;

        await tester.pumpWidget(createTestWidget(
          onWindowsChanged: (w) => changedWindows = w,
        ));

        // Tap on Add Window
        await tester.tap(find.text('Add Window'));
        await tester.pump();

        expect(changedWindows?.length, 2);
      });

      testWidgets('displays multiple windows when provided', (tester) async {
        windows = [
          const state.ScheduleWindow(
            startDay: 'monday',
            startTime: TimeOfDay(hour: 9, minute: 0),
            endDay: 'monday',
            endTime: TimeOfDay(hour: 12, minute: 0),
          ),
          const state.ScheduleWindow(
            startDay: 'wednesday',
            startTime: TimeOfDay(hour: 14, minute: 0),
            endDay: 'wednesday',
            endTime: TimeOfDay(hour: 17, minute: 0),
          ),
        ];

        await tester.pumpWidget(createTestWidget());

        expect(find.text('Window 1'), findsOneWidget);
        expect(find.text('Window 2'), findsOneWidget);
      });

      testWidgets('shows delete button when multiple windows exist',
          (tester) async {
        windows = [
          const state.ScheduleWindow(
            startDay: 'monday',
            startTime: TimeOfDay(hour: 9, minute: 0),
            endDay: 'monday',
            endTime: TimeOfDay(hour: 12, minute: 0),
          ),
          const state.ScheduleWindow(
            startDay: 'wednesday',
            startTime: TimeOfDay(hour: 14, minute: 0),
            endDay: 'wednesday',
            endTime: TimeOfDay(hour: 17, minute: 0),
          ),
        ];

        await tester.pumpWidget(createTestWidget());

        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      });

      testWidgets('does not show delete button when only one window',
          (tester) async {
        await tester.pumpWidget(createTestWidget());

        // Only one window, so delete should not be shown
        expect(find.byIcon(Icons.delete_outline), findsNothing);
      });
    });

    group('Visibility Toggle', () {
      testWidgets('displays visibility switch', (tester) async {
        await tester.pumpWidget(createTestWidget());

        expect(find.text('Hide when outside schedule'), findsOneWidget);
        expect(find.byType(SwitchListTile), findsOneWidget);
      });

      testWidgets('shows correct subtitle when visible outside schedule',
          (tester) async {
        visibleOutsideSchedule = true;

        await tester.pumpWidget(createTestWidget());

        expect(find.text('Chat visible but paused outside schedule'),
            findsOneWidget);
      });

      testWidgets('shows correct subtitle when hidden outside schedule',
          (tester) async {
        visibleOutsideSchedule = false;

        await tester.pumpWidget(createTestWidget());

        expect(find.text('Chat hidden until next scheduled window'),
            findsOneWidget);
      });

      testWidgets('calls onVisibleOutsideScheduleChanged when toggled',
          (tester) async {
        bool? changedValue;
        visibleOutsideSchedule = true;

        await tester.pumpWidget(createTestWidget(
          onVisibleOutsideScheduleChanged: (v) => changedValue = v,
        ));

        // Toggle the switch (it's inverted in UI)
        await tester.tap(find.byType(Switch));
        await tester.pump();

        // Switch is inverted: toggling "Hide when outside" to true
        // means visibleOutsideSchedule should become false
        expect(changedValue, isFalse);
      });
    });

    group('Time Formatting', () {
      testWidgets('formats 12 PM correctly', (tester) async {
        scheduledStartAt = DateTime(2026, 1, 15, 12, 0);

        await tester.pumpWidget(createTestWidget());

        expect(find.text('12:00 PM'), findsOneWidget);
      });

      testWidgets('formats 12 AM (midnight) correctly', (tester) async {
        scheduledStartAt = DateTime(2026, 1, 15, 0, 0);

        await tester.pumpWidget(createTestWidget());

        expect(find.text('12:00 AM'), findsOneWidget);
      });
    });
  });
}
