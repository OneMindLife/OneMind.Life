import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/leaderboard/user_rank_card.dart';

import '../../fixtures/user_round_rank_fixtures.dart';

void main() {
  group('UserRankCard', () {
    Widget buildTestWidget({
      required userRank,
      bool isCurrentUser = false,
      bool isWinner = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: UserRankCard(
              userRank: userRank,
              isCurrentUser: isCurrentUser,
              isWinner: isWinner,
            ),
          ),
        ),
      );
    }

    testWidgets('displays user name and rank', (tester) async {
      final userRank = UserRoundRankFixtures.model(
        displayName: 'Alice',
        rank: 85.5,
      );

      await tester.pumpWidget(buildTestWidget(userRank: userRank));

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Score: 85.5'), findsOneWidget);
    });

    testWidgets('displays "Unknown" when displayName is null', (tester) async {
      final userRank = UserRoundRankFixtures.model(displayName: null);

      await tester.pumpWidget(buildTestWidget(userRank: userRank));

      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('shows "(You)" indicator for current user', (tester) async {
      final userRank = UserRoundRankFixtures.model(displayName: 'Me');

      await tester.pumpWidget(buildTestWidget(
        userRank: userRank,
        isCurrentUser: true,
      ));

      expect(find.text('Me'), findsOneWidget);
      expect(find.text('(You)'), findsOneWidget);
    });

    testWidgets('does not show "(You)" for non-current user', (tester) async {
      final userRank = UserRoundRankFixtures.model(displayName: 'Alice');

      await tester.pumpWidget(buildTestWidget(
        userRank: userRank,
        isCurrentUser: false,
      ));

      expect(find.text('(You)'), findsNothing);
    });

    testWidgets('shows trophy icon for winner', (tester) async {
      final userRank = UserRoundRankFixtures.winner();

      await tester.pumpWidget(buildTestWidget(
        userRank: userRank,
        isWinner: true,
      ));

      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('does not show trophy for non-winner', (tester) async {
      final userRank = UserRoundRankFixtures.model();

      await tester.pumpWidget(buildTestWidget(
        userRank: userRank,
        isWinner: false,
      ));

      expect(find.byIcon(Icons.emoji_events), findsNothing);
    });

    testWidgets('winner card has border', (tester) async {
      final userRank = UserRoundRankFixtures.winner();

      await tester.pumpWidget(buildTestWidget(
        userRank: userRank,
        isWinner: true,
      ));

      final cardFinder = find.byType(Card);
      expect(cardFinder, findsOneWidget);

      final card = tester.widget<Card>(cardFinder);
      final shape = card.shape as RoundedRectangleBorder;
      expect(shape.side, isNot(BorderSide.none));
    });

    testWidgets('formats rank with one decimal place', (tester) async {
      final userRank = UserRoundRankFixtures.model(rank: 75.123);

      await tester.pumpWidget(buildTestWidget(userRank: userRank));

      expect(find.text('Score: 75.1'), findsOneWidget);
    });

    testWidgets('shows both (You) and trophy when current user is winner', (tester) async {
      final userRank = UserRoundRankFixtures.winner(displayName: 'Champion');

      await tester.pumpWidget(buildTestWidget(
        userRank: userRank,
        isCurrentUser: true,
        isWinner: true,
      ));

      expect(find.text('Champion'), findsOneWidget);
      expect(find.text('(You)'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });
  });
}
