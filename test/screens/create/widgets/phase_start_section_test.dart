import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart' as state;
import 'package:onemind_app/screens/create/widgets/phase_start_section.dart';

void main() {
  group('PhaseStartSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PhaseStartSection(
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // Section header is now "Start when this many join" (auto-start count label)
      expect(find.text('Start when this many join'), findsWidgets);
    });

    // NOTE: Manual/Auto toggle has been removed - always auto now.
    // Host can't see propositions, so manual mode doesn't work.
    testWidgets('manual/auto toggle is removed (always auto)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PhaseStartSection(
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // Manual/Auto buttons should not exist
      expect(find.text('Manual'), findsNothing);
      expect(find.text('Auto'), findsNothing);
    });

    testWidgets('always shows auto-start count (no manual mode)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PhaseStartSection(
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // Auto-start count is always shown now (no manual mode)
      expect(find.text('Start when this many join'), findsWidgets);
      expect(find.text('5'), findsOneWidget);
    });

    // NOTE: Schedule UI is hidden for MVP. These tests verify it's not shown.
    // When re-enabling schedule, change findsNothing to findsOneWidget.
    testWidgets('schedule toggle is hidden (re-enable: change to findsOneWidget)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PhaseStartSection(
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // Schedule UI is hidden for MVP - change to findsOneWidget when re-enabled
      expect(find.text('Enable Schedule'), findsNothing);
      expect(find.text('Restrict when the chat room is open'), findsNothing);
    });

    testWidgets('schedule settings hidden when enableSchedule is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PhaseStartSection(
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
              onAutoStartCountChanged: (_) {},
              onEnableScheduleChanged: (_) {},
              onScheduleSettingsChanged: (_) {},
            ),
          ),
        ),
      );

      // Schedule settings card specific text - always hidden when enableSchedule is false
      expect(find.text('One-time'), findsNothing);
      expect(find.text('Recurring'), findsNothing);
    });

    // NOTE: Tests below are commented out since schedule UI is hidden for MVP.
    // Uncomment when schedule feature is re-enabled.
    //
    // testWidgets('shows schedule settings when enableSchedule is true',
    //     (tester) async {
    //   await tester.pumpWidget(
    //     MaterialApp(
    //       localizationsDelegates: AppLocalizations.localizationsDelegates,
    //       supportedLocales: AppLocalizations.supportedLocales,
    //       locale: const Locale('en'),
    //       home: Scaffold(
    //         body: SingleChildScrollView(
    //           child: PhaseStartSection(
    //             autoStartCount: 5,
    //             enableSchedule: true,
    //             scheduleSettings: state.ScheduleSettings.defaults(),
    //             onAutoStartCountChanged: (_) {},
    //             onEnableScheduleChanged: (_) {},
    //             onScheduleSettingsChanged: (_) {},
    //           ),
    //         ),
    //       ),
    //     ),
    //   );
    //
    //   expect(find.text('One-time'), findsOneWidget);
    //   expect(find.text('Recurring'), findsOneWidget);
    // });

    // NOTE: onStartModeChanged test removed - manual mode no longer exists.

    testWidgets('calls onAutoStartCountChanged when incrementing',
        (tester) async {
      int? updatedCount;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PhaseStartSection(
              autoStartCount: 5,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PhaseStartSection(
              autoStartCount: 3,
              enableSchedule: false,
              scheduleSettings: state.ScheduleSettings.defaults(),
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

    // NOTE: Schedule callback tests commented out since UI is hidden.
    // Uncomment when schedule feature is re-enabled.
    //
    // testWidgets('calls onEnableScheduleChanged when toggling schedule',
    //     (tester) async {
    //   bool? updatedValue;
    //
    //   await tester.pumpWidget(
    //     MaterialApp(
    //       localizationsDelegates: AppLocalizations.localizationsDelegates,
    //       supportedLocales: AppLocalizations.supportedLocales,
    //       locale: const Locale('en'),
    //       home: Scaffold(
    //         body: PhaseStartSection(
    //           startMode: StartMode.manual,
    //           autoStartCount: 5,
    //           enableSchedule: false,
    //           scheduleSettings: state.ScheduleSettings.defaults(),
    //           onStartModeChanged: (_) {},
    //           onAutoStartCountChanged: (_) {},
    //           onEnableScheduleChanged: (v) => updatedValue = v,
    //           onScheduleSettingsChanged: (_) {},
    //         ),
    //       ),
    //     ),
    //   );
    //
    //   await tester.tap(find.byType(Switch));
    //   await tester.pump();
    //
    //   expect(updatedValue, true);
    // });
    //
    // testWidgets('calls onScheduleSettingsChanged for schedule type',
    //     (tester) async {
    //   state.ScheduleSettings? updatedSettings;
    //
    //   await tester.pumpWidget(
    //     MaterialApp(
    //       localizationsDelegates: AppLocalizations.localizationsDelegates,
    //       supportedLocales: AppLocalizations.supportedLocales,
    //       locale: const Locale('en'),
    //       home: Scaffold(
    //         body: SingleChildScrollView(
    //           child: PhaseStartSection(
    //             startMode: StartMode.manual,
    //             autoStartCount: 5,
    //             enableSchedule: true,
    //             scheduleSettings: state.ScheduleSettings.defaults(),
    //             onStartModeChanged: (_) {},
    //             onAutoStartCountChanged: (_) {},
    //             onEnableScheduleChanged: (_) {},
    //             onScheduleSettingsChanged: (v) => updatedSettings = v,
    //           ),
    //         ),
    //       ),
    //     ),
    //   );
    //
    //   await tester.tap(find.text('Recurring'));
    //   await tester.pump();
    //
    //   expect(updatedSettings, isNotNull);
    //   expect(updatedSettings!.type, state.ScheduleType.recurring);
    // });
  });
}
