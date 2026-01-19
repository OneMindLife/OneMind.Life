import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/models/round_winner.dart';
import 'package:onemind_app/screens/chat/widgets/previous_round_display.dart';

void main() {
  final testDate = DateTime(2024, 1, 1);

  /// Helper to create a test widget with localization support
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );
  }

  group('PreviousWinnerPanel', () {
    testWidgets('displays winner content', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          PreviousWinnerPanel(
              previousRoundWinners: [
                RoundWinner(
                  id: 1,
                  roundId: 1,
                  propositionId: 1,
                  content: 'Winning proposition',
                  globalScore: 85.5,
                  rank: 1,
                  createdAt: testDate,
                ),
              ],
              currentWinnerIndex: 0,
              isSoleWinner: true,
              consecutiveSoleWins: 2,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (_) {},
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Winning proposition'), findsOneWidget);
      expect(find.text('Score: 85.5'), findsOneWidget);
      expect(find.text('Sole wins: 2/3'), findsOneWidget);
    });

    testWidgets('shows tie badge for multiple winners', (tester) async {
      await tester.pumpWidget(
        createTestWidget( PreviousWinnerPanel(
              previousRoundWinners: [
                RoundWinner(id: 1, roundId: 1, propositionId: 1, content: 'Winner 1', globalScore: 80.0, rank: 1, createdAt: testDate),
                RoundWinner(id: 2, roundId: 1, propositionId: 2, content: 'Winner 2', globalScore: 80.0, rank: 1, createdAt: testDate),
              ],
              currentWinnerIndex: 0,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (_) {},
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2-WAY TIE'), findsOneWidget);
      expect(find.text('Tied win (does not count toward consensus)'), findsOneWidget);
    });

    testWidgets('hides See Results button when showResultsButton is false', (tester) async {
      await tester.pumpWidget(
        createTestWidget( PreviousWinnerPanel(
              previousRoundWinners: [
                RoundWinner(id: 1, roundId: 1, propositionId: 1, content: 'Winner', globalScore: 85.0, rank: 1, createdAt: testDate),
              ],
              currentWinnerIndex: 0,
              isSoleWinner: true,
              consecutiveSoleWins: 1,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (_) {},
              showResultsButton: false,
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('See All Results'), findsNothing);
    });

    testWidgets('shows See Results button when showResultsButton is true with results', (tester) async {
      await tester.pumpWidget(
        createTestWidget( PreviousWinnerPanel(
              previousRoundWinners: [
                RoundWinner(id: 1, roundId: 1, propositionId: 1, content: 'Winner', globalScore: 85.0, rank: 1, createdAt: testDate),
              ],
              currentWinnerIndex: 0,
              isSoleWinner: true,
              consecutiveSoleWins: 1,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (_) {},
              showResultsButton: true,
              previousRoundResults: [
                Proposition(
                  id: 1,
                  roundId: 1,
                  content: 'Prop 1',
                  createdAt: testDate,
                  finalRating: 85.0,
                ),
                Proposition(
                  id: 2,
                  roundId: 1,
                  content: 'Prop 2',
                  createdAt: testDate,
                  finalRating: 50.0,
                ),
              ],
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('See All Results'), findsOneWidget);
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
    });

    testWidgets('hides See Results button when previousRoundResults is empty', (tester) async {
      await tester.pumpWidget(
        createTestWidget( PreviousWinnerPanel(
              previousRoundWinners: [
                RoundWinner(id: 1, roundId: 1, propositionId: 1, content: 'Winner', globalScore: 85.0, rank: 1, createdAt: testDate),
              ],
              currentWinnerIndex: 0,
              isSoleWinner: true,
              consecutiveSoleWins: 1,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (_) {},
              showResultsButton: true,
              previousRoundResults: [], // Empty
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('See All Results'), findsNothing);
    });

    testWidgets('hides See Results button when previousRoundResults is null', (tester) async {
      await tester.pumpWidget(
        createTestWidget( PreviousWinnerPanel(
              previousRoundWinners: [
                RoundWinner(id: 1, roundId: 1, propositionId: 1, content: 'Winner', globalScore: 85.0, rank: 1, createdAt: testDate),
              ],
              currentWinnerIndex: 0,
              isSoleWinner: true,
              consecutiveSoleWins: 1,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (_) {},
              showResultsButton: true,
              previousRoundResults: null, // Null
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('See All Results'), findsNothing);
    });

    testWidgets('navigation arrows for multiple winners', (tester) async {
      int? selectedIndex;
      await tester.pumpWidget(
        createTestWidget( PreviousWinnerPanel(
              previousRoundWinners: [
                RoundWinner(id: 1, roundId: 1, propositionId: 1, content: 'Winner 1', globalScore: 80.0, rank: 1, createdAt: testDate),
                RoundWinner(id: 2, roundId: 1, propositionId: 2, content: 'Winner 2', globalScore: 80.0, rank: 1, createdAt: testDate),
              ],
              currentWinnerIndex: 0,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (index) => selectedIndex = index,
            ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially showing winner 1
      expect(find.text('Winner 1'), findsOneWidget);

      // Tap right arrow to go to winner 2
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();

      expect(selectedIndex, 1);
    });

    testWidgets('displays no previous winner message when list is empty', (tester) async {
      await tester.pumpWidget(
        createTestWidget( PreviousWinnerPanel(
              previousRoundWinners: [],
              currentWinnerIndex: 0,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 3,
              currentRoundCustomId: 2,
              onWinnerIndexChanged: (_) {},
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No previous winner'), findsOneWidget);
    });
  });

  group('TieBadge', () {
    testWidgets('displays correct count', (tester) async {
      await tester.pumpWidget(
        createTestWidget( TieBadge(count: 3),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3-WAY TIE'), findsOneWidget);
    });
  });

  group('WinnerPageIndicator', () {
    testWidgets('shows correct number of dots', (tester) async {
      await tester.pumpWidget(
        createTestWidget( WinnerPageIndicator(
              count: 4,
              currentIndex: 1,
              onIndexChanged: (_) {},
            ),
        ),
      );
      await tester.pumpAndSettle();

      // Should have 4 dots
      final containers = find.byType(Container);
      // Each dot is a Container with BoxDecoration circle shape
      expect(containers.evaluate().length, greaterThanOrEqualTo(4));
    });

    testWidgets('hides when count is 1', (tester) async {
      await tester.pumpWidget(
        createTestWidget( WinnerPageIndicator(
              count: 1,
              currentIndex: 0,
              onIndexChanged: (_) {},
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
