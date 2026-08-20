import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart'
    as state;
import 'package:onemind_app/screens/create/widgets/wizard_common.dart';
import 'package:onemind_app/screens/create/widgets/wizard_step_first_deadline.dart';

void main() {
  // Fixed clock: 2026-07-02 10:00 local. For 12h phases the runway is 1h, so
  // the anchor window is [11:00, 22:00] and the next 3am/3pm is 3 PM today.
  final now = DateTime(2026, 7, 2, 10, 0);

  Widget harness({
    bool adaptiveEnabled = false,
    int proposingDuration = 43200,
    int? ratingDuration,
    DateTime? initialAnchor,
    List<DateTime?>? changes,
  }) {
    DateTime? anchor = initialAnchor;
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => WizardStepFirstDeadline(
            timerSettings: state.TimerSettings(
              useSameDuration: ratingDuration == null,
              proposingPreset: 'custom',
              ratingPreset: 'custom',
              proposingDuration: proposingDuration,
              ratingDuration: ratingDuration ?? proposingDuration,
            ),
            cadenceAnchorAt: anchor,
            onCadenceAnchorChanged: (a) {
              changes?.add(a);
              setState(() => anchor = a);
            },
            timezoneName: 'America/New_York',
            adaptiveEnabled: adaptiveEnabled,
            nowProvider: () => now,
            onContinue: () {},
          ),
        ),
      ),
    );
  }

  // Selected option cards (and only they) show a check_circle icon.
  bool isSelected(WidgetTester tester, String cardTitle) {
    final check = find.descendant(
      of: find.ancestor(
        of: find.text(cardTitle),
        matching: find.byType(WizardSelectCard),
      ),
      matching: find.byIcon(Icons.check_circle),
    );
    return tester.any(check);
  }

  group('step chrome', () {
    testWidgets('shows the title, starts-now subtitle, and the question',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(find.text('First deadline'), findsOneWidget);
      expect(find.text('Your chat starts as soon as you create it.'),
          findsOneWidget);
      expect(find.text('When should the first phase end?'), findsOneWidget);
    });
  });

  group('controls availability', () {
    testWidgets('option cards shown for coherent durations + adaptive off',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(find.text('Full duration'), findsOneWidget);
      expect(find.text('3 AM / 3 PM rhythm'), findsOneWidget);
      expect(find.text('Custom time…'), findsOneWidget);
      expect(find.textContaining('A daily rhythm needs'), findsNothing);
    });

    testWidgets('unavailable note when durations differ', (tester) async {
      await tester.pumpWidget(
          harness(proposingDuration: 43200, ratingDuration: 86400));
      expect(find.textContaining('A daily rhythm needs'), findsOneWidget);
      expect(find.text('3 AM / 3 PM rhythm'), findsNothing);
      expect(find.byType(WizardSelectCard), findsNothing);
    });

    testWidgets('unavailable note when the duration does not divide 24h',
        (tester) async {
      await tester.pumpWidget(harness(proposingDuration: 18000)); // 5h
      expect(find.textContaining('A daily rhythm needs'), findsOneWidget);
      expect(find.byType(WizardSelectCard), findsNothing);
    });

    testWidgets('unavailable note when adaptive durations are on',
        (tester) async {
      await tester.pumpWidget(harness(adaptiveEnabled: true));
      expect(find.textContaining('A daily rhythm needs'), findsOneWidget);
      expect(find.byType(WizardSelectCard), findsNothing);
    });
  });

  group('option cards', () {
    testWidgets('Full duration is the default selection and preview is absent',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(isSelected(tester, 'Full duration'), isTrue);
      expect(isSelected(tester, '3 AM / 3 PM rhythm'), isFalse);
      expect(find.textContaining('Phases will flip at'), findsNothing);
      expect(find.textContaining('First phase will be shorter'), findsNothing);
    });

    testWidgets('tapping the 3am/3pm card sets the anchor and shows the '
        'preview + shortening notice', (tester) async {
      final changes = <DateTime?>[];
      await tester.pumpWidget(harness(changes: changes));

      await tester.ensureVisible(find.text('3 AM / 3 PM rhythm'));
      await tester.tap(find.text('3 AM / 3 PM rhythm'));
      await tester.pumpAndSettle();

      // Next 3am/3pm at/after 11:00 local is 3 PM today.
      expect(changes, [DateTime(2026, 7, 2, 15, 0)]);
      expect(isSelected(tester, '3 AM / 3 PM rhythm'), isTrue);
      expect(
        find.text('Phases will flip at 3:00 AM / 3:00 PM (America/New_York) '
            'every day.'),
        findsOneWidget,
      );
      // Anchor is 5h away but the full duration is 12h -> shorter notice.
      expect(find.text('First phase will be shorter: ends in 5h 0m.'),
          findsOneWidget);
    });

    testWidgets('24h durations get the Same time daily card and no custom '
        'card', (tester) async {
      await tester.pumpWidget(harness(proposingDuration: 86400));
      expect(find.text('Same time daily…'), findsOneWidget);
      expect(find.text('3 AM / 3 PM rhythm'), findsNothing);
      // The daily card IS the picker — no separate custom card.
      expect(find.text('Custom time…'), findsNothing);
    });

    testWidgets('other coherent durations get the On the hour card',
        (tester) async {
      final changes = <DateTime?>[];
      await tester
          .pumpWidget(harness(proposingDuration: 21600, changes: changes));
      expect(find.text('On the hour'), findsOneWidget);

      await tester.ensureVisible(find.text('On the hour'));
      await tester.tap(find.text('On the hour'));
      await tester.pumpAndSettle();

      // 6h duration -> 1h runway -> earliest 11:00, already a whole hour.
      expect(changes, [DateTime(2026, 7, 2, 11, 0)]);
    });

    testWidgets('Full duration resets the anchor to null and hides the '
        'preview', (tester) async {
      final changes = <DateTime?>[];
      await tester.pumpWidget(harness(
        initialAnchor: DateTime(2026, 7, 2, 15, 0),
        changes: changes,
      ));
      expect(find.textContaining('Phases will flip at'), findsOneWidget);

      await tester.ensureVisible(find.text('Full duration'));
      await tester.tap(find.text('Full duration'));
      await tester.pumpAndSettle();

      expect(changes, [null]);
      expect(find.textContaining('Phases will flip at'), findsNothing);
      expect(find.textContaining('First phase will be shorter'), findsNothing);
    });

    testWidgets('an anchor off the suggested value selects the custom card',
        (tester) async {
      // 17:00 is inside the window but is not the suggested 3 PM.
      await tester.pumpWidget(
          harness(initialAnchor: DateTime(2026, 7, 2, 17, 0)));
      expect(isSelected(tester, 'Custom time…'), isTrue);
      expect(isSelected(tester, '3 AM / 3 PM rhythm'), isFalse);
      expect(find.text('First deadline: 5:00 PM'), findsOneWidget);
    });
  });

  group('value display', () {
    testWidgets('cards describe their resulting first deadline',
        (tester) async {
      await tester.pumpWidget(harness());
      // Suggested 3am/3pm card announces the concrete resolved deadline.
      expect(find.text('First deadline: 3:00 PM'), findsOneWidget);
      // Full duration card announces the plain-chaining behavior.
      expect(find.textContaining('runs its full 12h'), findsOneWidget);
    });

    testWidgets('shows the anchor time when set', (tester) async {
      await tester.pumpWidget(
          harness(initialAnchor: DateTime(2026, 7, 2, 15, 0)));
      expect(isSelected(tester, '3 AM / 3 PM rhythm'), isTrue);
      expect(find.text('First deadline: 3:00 PM'), findsOneWidget);
    });
  });
}
