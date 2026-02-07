import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/chat/widgets/phase_panels.dart';

/// Helper to wrap widgets with localization support
Widget createTestWidget(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('ScheduledWaitingPanel', () {
    group('One-time scheduled chat', () {
      testWidgets('shows scheduled start time when in future', (tester) async {
        final scheduledStartAt = DateTime.now().add(const Duration(hours: 2));

        await tester.pumpWidget(
          createTestWidget(
            ScheduledWaitingPanel(
              isHost: true,
              scheduledStartAt: scheduledStartAt,
              scheduleTimezone: 'America/New_York',
            ),
          ),
        );

        // Should show scheduled info
        expect(find.text('Scheduled to start'), findsOneWidget);
        // Should NOT show "Start Phase" button
        expect(find.text('Start Phase'), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
      });

      testWidgets('shows timezone information', (tester) async {
        final scheduledStartAt = DateTime.now().add(const Duration(hours: 2));

        await tester.pumpWidget(
          createTestWidget(
            ScheduledWaitingPanel(
              isHost: false,
              scheduledStartAt: scheduledStartAt,
              scheduleTimezone: 'America/New_York',
            ),
          ),
        );

        // Should show timezone
        expect(find.text('New York'), findsOneWidget);
      });

      testWidgets('non-host sees same scheduled info as host', (tester) async {
        final scheduledStartAt = DateTime.now().add(const Duration(hours: 1));

        await tester.pumpWidget(
          createTestWidget(
            ScheduledWaitingPanel(
              isHost: false,
              scheduledStartAt: scheduledStartAt,
              scheduleTimezone: 'UTC',
            ),
          ),
        );

        // Non-host should see scheduled info, not "Waiting for host"
        expect(find.text('Scheduled to start'), findsOneWidget);
        expect(find.text('Waiting for host to start...'), findsNothing);
      });
    });

    group('Recurring scheduled chat', () {
      testWidgets('shows outside schedule window message', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            ScheduledWaitingPanel(
              isHost: true,
              isRecurring: true,
              nextWindowStart: DateTime.now().add(const Duration(days: 1)),
              scheduleTimezone: 'Europe/London',
            ),
          ),
        );

        // Should indicate chat is outside schedule window
        expect(find.text('Chat is outside schedule window'), findsOneWidget);
        // Should NOT show "Start Phase" button
        expect(find.text('Start Phase'), findsNothing);
      });

      testWidgets('shows next window start time', (tester) async {
        final nextWindow = DateTime.now().add(const Duration(hours: 5));

        await tester.pumpWidget(
          createTestWidget(
            ScheduledWaitingPanel(
              isHost: true,
              isRecurring: true,
              nextWindowStart: nextWindow,
              scheduleTimezone: 'Asia/Tokyo',
            ),
          ),
        );

        // Should show when next window starts
        expect(find.textContaining('Next window starts'), findsOneWidget);
      });
    });

    group('No Start Phase button', () {
      testWidgets('host cannot manually start scheduled one-time chat', (tester) async {
        final scheduledStartAt = DateTime.now().add(const Duration(minutes: 30));

        await tester.pumpWidget(
          createTestWidget(
            ScheduledWaitingPanel(
              isHost: true,
              scheduledStartAt: scheduledStartAt,
              scheduleTimezone: 'America/Los_Angeles',
            ),
          ),
        );

        // Host should NOT be able to start early
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.text('Start Phase'), findsNothing);
      });

      testWidgets('host cannot manually start recurring chat outside window', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            ScheduledWaitingPanel(
              isHost: true,
              isRecurring: true,
              nextWindowStart: DateTime.now().add(const Duration(hours: 10)),
              scheduleTimezone: 'Europe/Paris',
            ),
          ),
        );

        // Host should NOT be able to start early
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.text('Start Phase'), findsNothing);
      });
    });
  });
}
