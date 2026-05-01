import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/widgets/rating/rating_model.dart';
import 'package:onemind_app/widgets/rating/rating_widget.dart';
import 'package:onemind_app/widgets/rating_help_modal.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('RatingHelpModal', () {
    // Note: the demo widgets schedule recursive Future.delayed polling
    // for button positions (up to 10 × 500ms). To avoid timer-leak
    // failures we drain those by pumping past the polling window before
    // disposal, then close the modal cleanly.
    Future<void> drainAndClose(WidgetTester tester) async {
      // Pump past the 5s polling window so all queued timers complete.
      await tester.pump(const Duration(seconds: 6));
      // Tap close to dispose any active animation controllers.
      if (find.byIcon(Icons.close).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('binary modal renders generic Idea 1 / Idea 2 content',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const RatingHelpModal(phase: RatingPhase.binary)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Idea 1'), findsOneWidget);
      expect(find.text('Idea 2'), findsOneWidget);
      // The 3rd idea is a positioning-phase card; should be absent here.
      expect(find.text('Idea 3'), findsNothing);

      await drainAndClose(tester);
    });

    testWidgets('positioning modal feeds in Idea 3 as the active card',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const RatingHelpModal(phase: RatingPhase.positioning)),
      );
      // Pump past the post-frame callback that pushes the third proposition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Idea 1'), findsOneWidget);
      expect(find.text('Idea 2'), findsOneWidget);
      expect(find.text('Idea 3'), findsOneWidget);

      await drainAndClose(tester);
    });

    testWidgets('close icon dismisses the modal', (tester) async {
      // Push it onto a host so we can verify it pops.
      bool popped = false;
      await tester.pumpWidget(_wrap(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                await RatingHelpModal.show(context, RatingPhase.binary);
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      )));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.close), findsOneWidget);

      // Drain demo polling, then close.
      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
    });
  });

  group('RatingWidget help button', () {
    testWidgets('shows help icon under controls when showHelpButton is true',
        (tester) async {
      RatingPhase? requestedPhase;
      await tester.pumpWidget(_wrap(Scaffold(
        body: RatingWidget(
          propositions: const [
            {'id': '1', 'content': 'A'},
            {'id': '2', 'content': 'B'},
          ],
          onRankingComplete: (_) {},
          showHelpButton: true,
          onHelpPressed: (phase) => requestedPhase = phase,
        ),
      )));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.help_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pump();

      expect(requestedPhase, RatingPhase.binary);
    });

    testWidgets('hides help icon when showHelpButton is false (default)',
        (tester) async {
      await tester.pumpWidget(_wrap(Scaffold(
        body: RatingWidget(
          propositions: const [
            {'id': '1', 'content': 'A'},
            {'id': '2', 'content': 'B'},
          ],
          onRankingComplete: (_) {},
        ),
      )));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.help_outline), findsNothing);
    });
  });
}
