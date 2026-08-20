import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/chat/widgets/host_end_voting_bar.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int done,
    required int eligible,
    bool isEnding = false,
    VoidCallback? onEndVoting,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HostEndVotingBar(
            done: done,
            eligible: eligible,
            isEnding: isEnding,
            onEndVoting: onEndVoting ?? () {},
          ),
        ),
      ),
    );
  }

  group('HostEndVotingBar', () {
    testWidgets('before everyone has voted: shows progress + "End voting & show results"',
        (tester) async {
      await pump(tester, done: 1, eligible: 3);
      expect(find.text('End voting & show results'), findsOneWidget);
      expect(find.textContaining('1 of 3 voted'), findsOneWidget);
      // Not the 100% celebratory copy.
      expect(find.textContaining("Everyone's voted"), findsNothing);
    });

    testWidgets('when everyone has voted (group): promotes to "Show results"',
        (tester) async {
      await pump(tester, done: 3, eligible: 3);
      expect(find.text('Show results'), findsOneWidget);
      expect(find.textContaining("Everyone's voted (3 of 3)"), findsOneWidget);
      expect(find.text('End voting & show results'), findsNothing);
    });

    testWidgets('solo host (eligible 1) not yet done: ready-when-you-are copy',
        (tester) async {
      await pump(tester, done: 0, eligible: 1);
      expect(find.text('End voting & show results'), findsOneWidget);
      expect(find.textContaining("whenever you're ready"), findsOneWidget);
    });

    testWidgets('solo host done: "You\'ve voted" + Show results', (tester) async {
      await pump(tester, done: 1, eligible: 1);
      expect(find.text('Show results'), findsOneWidget);
      expect(find.textContaining("You've voted"), findsOneWidget);
    });

    testWidgets('tapping the button invokes onEndVoting', (tester) async {
      var tapped = 0;
      await pump(tester, done: 2, eligible: 2, onEndVoting: () => tapped++);
      await tester.tap(find.byKey(const Key('end-voting-button')));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('while ending: shows a spinner and is disabled', (tester) async {
      var tapped = 0;
      await pump(tester,
          done: 2, eligible: 2, isEnding: true, onEndVoting: () => tapped++);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('end-voting-button')));
      await tester.pump();
      expect(tapped, 0, reason: 'button disabled while ending');
    });
  });
}
