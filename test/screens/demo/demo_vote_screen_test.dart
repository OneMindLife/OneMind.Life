import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/demo/demo_vote_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('demo lands tap-first (no fork, no typing) on the vote',
      (tester) async {
    await tester.pumpApp(const DemoVoteScreen());
    // pump() not pumpAndSettle() — the pre-first-vote affordance pulse repeats,
    // so the tree never "settles" until the user votes.
    await tester.pump();

    // First interaction is a tap-vote — not a fork choice, not a text field.
    expect(find.text("What's the best perk to add at work?"), findsOneWidget);
    expect(find.text('Which is better? Tap one.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('demo-top')), findsOneWidget);
    expect(find.byKey(const Key('demo-bottom')), findsOneWidget);
    // "VS" affordance badge signals "pick one of these two" pre-read.
    expect(find.text('VS'), findsOneWidget);
  });

  testWidgets('voting produces a full ranked leaderboard + create handoff',
      (tester) async {
    await tester.pumpApp(const DemoVoteScreen());
    await tester.pump(); // pulse repeats pre-vote; pumpAndSettle would hang

    // Keep picking the top option; full_rank covers all pairs (~6 taps) then
    // reveals the ranking. The first tap stops the pulse, so pumpAndSettle is
    // safe inside the loop. Stop as soon as the leaderboard appears.
    for (var i = 0;
        i < 15 &&
            find.text("Here's how the group ranked them").evaluate().isEmpty;
        i++) {
      await tester.tap(find.byKey(const Key('demo-top')));
      await tester.pumpAndSettle();
    }

    // Leaderboard reveal: header, the create handoff, and all four options ranked.
    expect(find.text("Here's how the group ranked them"), findsOneWidget);
    expect(find.text('Create your own decision'), findsOneWidget);
    for (final option in const [
      'A four-day work week',
      'Work from anywhere',
      'Better health insurance',
      'Unlimited PTO',
    ]) {
      expect(find.text(option), findsOneWidget);
    }
  });
}
