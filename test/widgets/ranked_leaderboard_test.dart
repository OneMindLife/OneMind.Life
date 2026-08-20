import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/ranked_leaderboard.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders one numbered row per entry, in order', (tester) async {
    await tester.pumpWidget(wrap(const RankedLeaderboard(
      entries: ['Alpha', 'Beta', 'Gamma', 'Delta'],
    )));

    for (final label in ['Alpha', 'Beta', 'Gamma', 'Delta']) {
      expect(find.text(label), findsOneWidget);
    }
    // Ranks 1..4 shown.
    for (final rank in ['1', '2', '3', '4']) {
      expect(find.text(rank), findsOneWidget);
    }
  });

  testWidgets('only the #1 entry gets the winner trophy', (tester) async {
    await tester.pumpWidget(wrap(const RankedLeaderboard(
      entries: ['Winner', 'Second', 'Third'],
    )));

    // The trophy (Icons.emoji_events) marks the winner only — exactly once.
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
  });

  testWidgets('a single entry still renders as the winner', (tester) async {
    await tester.pumpWidget(wrap(const RankedLeaderboard(entries: ['Only'])));

    expect(find.text('Only'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
  });
}
