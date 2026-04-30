import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/round_winner.dart';
import 'package:onemind_app/screens/chat/widgets/previous_round_display.dart';
import 'package:onemind_app/screens/chat/widgets/convergence_video_card.dart';
import 'package:onemind_app/widgets/tts_button.dart';

void main() {
  final testDate = DateTime(2024, 1, 1);

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
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(id: 1, roundId: 1, propositionId: 1,
                content: 'Winning proposition', globalScore: 85.5,
                rank: 1, createdAt: testDate),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Winning proposition'), findsOneWidget);
    });

    testWidgets('shows chevron arrows for multiple winners', (tester) async {
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(id: 1, roundId: 1, propositionId: 1,
                content: 'Winner 1', globalScore: 80.0,
                rank: 1, createdAt: testDate),
            RoundWinner(id: 2, roundId: 1, propositionId: 2,
                content: 'Winner 2', globalScore: 80.0,
                rank: 1, createdAt: testDate),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('calls onWinnerIndexChanged on chevron tap', (tester) async {
      int? selectedIndex;
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(id: 1, roundId: 1, propositionId: 1,
                content: 'Winner 1', globalScore: 80.0,
                rank: 1, createdAt: testDate),
            RoundWinner(id: 2, roundId: 1, propositionId: 2,
                content: 'Winner 2', globalScore: 80.0,
                rank: 1, createdAt: testDate),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (index) => selectedIndex = index,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();

      expect(selectedIndex, 1);
    });

    testWidgets('chevrons loop around', (tester) async {
      int? selectedIndex;
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(id: 1, roundId: 1, propositionId: 1,
                content: 'Winner 1', globalScore: 80.0,
                rank: 1, createdAt: testDate),
            RoundWinner(id: 2, roundId: 1, propositionId: 2,
                content: 'Winner 2', globalScore: 80.0,
                rank: 1, createdAt: testDate),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (index) => selectedIndex = index,
        ),
      ));
      await tester.pumpAndSettle();

      // Left from index 0 should loop to last (index 1)
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();

      expect(selectedIndex, 1);
    });

    testWidgets('calls onTap when card is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(id: 1, roundId: 1, propositionId: 1,
                content: 'Winner', globalScore: 85.0,
                rank: 1, createdAt: testDate),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
          onTap: () => tapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Winner'));
      expect(tapped, isTrue);
    });

    testWidgets('displays empty message when no winners', (tester) async {
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No top candidate yet'), findsOneWidget);
    });

    testWidgets('renders TtsButton with audioUrl when single winner', (tester) async {
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(
              id: 1, roundId: 1, propositionId: 1,
              content: 'Winner', rank: 1, createdAt: testDate,
              audioUrl: 'https://example.com/round.mp3',
            ),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TtsButton), findsOneWidget);
    });

    testWidgets('renders inline ConvergenceVideoCard when videoUrl is present', (tester) async {
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(
              id: 1, roundId: 1, propositionId: 1,
              content: 'Winner', rank: 1, createdAt: testDate,
              videoUrl: 'https://example.com/round.mp4',
            ),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
        ),
      ));
      await tester.pump();

      expect(find.byType(ConvergenceVideoCard), findsOneWidget);
    });

    testWidgets('hides ConvergenceVideoCard when videoUrl is null', (tester) async {
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(
              id: 1, roundId: 1, propositionId: 1,
              content: 'Winner', rank: 1, createdAt: testDate,
            ),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ConvergenceVideoCard), findsNothing);
    });

    testWidgets('TtsButton present even when audioUrl is null (falls back to device TTS)',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        PreviousWinnerPanel(
          previousRoundWinners: [
            RoundWinner(
              id: 1, roundId: 1, propositionId: 1,
              content: 'Winner', rank: 1, createdAt: testDate,
            ),
          ],
          currentWinnerIndex: 0,
          onWinnerIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TtsButton), findsOneWidget);
    });
  });

  group('WinnerPageIndicator', () {
    testWidgets('shows correct number of dots', (tester) async {
      await tester.pumpWidget(createTestWidget(
        WinnerPageIndicator(
          count: 4,
          currentIndex: 1,
          onIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      final containers = find.byType(Container);
      expect(containers.evaluate().length, greaterThanOrEqualTo(4));
    });

    testWidgets('hides when count is 1', (tester) async {
      await tester.pumpWidget(createTestWidget(
        WinnerPageIndicator(
          count: 1,
          currentIndex: 0,
          onIndexChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
