import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/config/app_colors.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/screens/rating/matches_results_view.dart';
import 'package:onemind_app/widgets/tts_button.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  // Pre-sorted best-first, as the proposition service returns.
  List<Proposition> sampleProps() => [
        Proposition(
          id: 1,
          roundId: 1,
          content: 'Winner idea',
          createdAt: DateTime(2024, 1, 1),
          finalRating: 88.0,
        ),
        Proposition(
          id: 2,
          roundId: 1,
          content: 'Runner up',
          createdAt: DateTime(2024, 1, 1),
          finalRating: 60.5,
        ),
        Proposition(
          id: 3,
          roundId: 1,
          content: 'Third idea',
          createdAt: DateTime(2024, 1, 1),
          finalRating: 30.0,
        ),
      ];

  testWidgets('renders one ranked card per proposition, best-first',
      (tester) async {
    await tester.pumpWidget(wrap(MatchesResultsView(propositions: sampleProps())));
    await tester.pumpAndSettle();

    // Each idea is shown.
    expect(find.text('Winner idea'), findsOneWidget);
    expect(find.text('Runner up'), findsOneWidget);
    expect(find.text('Third idea'), findsOneWidget);

    // Rank numbers 1..3 in order.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Rank 1 is rendered above rank 3 (best-first ordering preserved).
    final rank1Y = tester.getTopLeft(find.text('1')).dy;
    final rank3Y = tester.getTopLeft(find.text('3')).dy;
    expect(rank1Y, lessThan(rank3Y));
  });

  testWidgets('only the top-ranked card shows the winner trophy',
      (tester) async {
    await tester.pumpWidget(wrap(MatchesResultsView(propositions: sampleProps())));
    await tester.pumpAndSettle();

    // The trophy marks the winner only — exactly once.
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
  });

  testWidgets('does not display raw numeric scores (ranking only)',
      (tester) async {
    await tester.pumpWidget(wrap(MatchesResultsView(propositions: sampleProps())));
    await tester.pumpAndSettle();

    // The score (finalRating) is used only to pre-sort the cards best-first;
    // it is intentionally NOT shown — results read as rank + content, never
    // raw numbers (consistent with the no-numbers results UX).
    expect(find.textContaining('Score'), findsNothing);
    expect(find.text('88'), findsNothing);
    expect(find.text('60.5'), findsNothing);
  });

  testWidgets('renders a TtsButton (read-aloud) per card', (tester) async {
    await tester.pumpWidget(wrap(MatchesResultsView(propositions: sampleProps())));
    await tester.pumpAndSettle();

    expect(find.byType(TtsButton), findsNWidgets(3));
  });

  testWidgets('winner card uses the consensus accent', (tester) async {
    await tester.pumpWidget(wrap(MatchesResultsView(propositions: sampleProps())));
    await tester.pumpAndSettle();

    // The winner trophy is painted in the consensus color.
    final trophy = tester.widget<Icon>(find.byIcon(Icons.emoji_events));
    expect(trophy.color, AppColors.consensus);
  });

  testWidgets('a single proposition still renders as the winner',
      (tester) async {
    await tester.pumpWidget(wrap(MatchesResultsView(
      propositions: [
        Proposition(
          id: 1,
          roundId: 1,
          content: 'Only idea',
          createdAt: DateTime(2024, 1, 1),
          finalRating: 50.0,
        ),
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Only idea'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    expect(find.byType(TtsButton), findsOneWidget);
  });

  testWidgets('omits the score line when finalRating is null', (tester) async {
    await tester.pumpWidget(wrap(MatchesResultsView(
      propositions: [
        Proposition(
          id: 1,
          roundId: 1,
          content: 'No score',
          createdAt: DateTime(2024, 1, 1),
          finalRating: null,
        ),
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.text('No score'), findsOneWidget);
    expect(find.textContaining('Score'), findsNothing);
  });
}
