import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import '../fixtures/fixtures.dart';

// =============================================================================
// WINNER NAVIGATION WIDGET (Extracted for testing)
// =============================================================================
// This tests the winner navigation logic used in ChatScreen

class WinnerNavigationWidget extends StatefulWidget {
  final List<RoundWinner> winners;
  final bool isSoleWinner;
  final int consecutiveSoleWins;
  final int confirmationRoundsRequired;

  const WinnerNavigationWidget({
    super.key,
    required this.winners,
    required this.isSoleWinner,
    required this.consecutiveSoleWins,
    required this.confirmationRoundsRequired,
  });

  @override
  State<WinnerNavigationWidget> createState() => _WinnerNavigationWidgetState();
}

class _WinnerNavigationWidgetState extends State<WinnerNavigationWidget> {
  int _currentWinnerIndex = 0;

  void _previousWinner() {
    if (_currentWinnerIndex > 0) {
      setState(() {
        _currentWinnerIndex--;
      });
    }
  }

  void _nextWinner() {
    if (_currentWinnerIndex < widget.winners.length - 1) {
      setState(() {
        _currentWinnerIndex++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.winners.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentWinner = widget.winners[_currentWinnerIndex];
    final hasMultipleWinners = widget.winners.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with tie badge
        Row(
          children: [
            const Text(
              'Previous Winner',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (hasMultipleWinners) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.winners.length}-WAY TIE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // Winner content with navigation
        Row(
          children: [
            // Left arrow (previous)
            if (hasMultipleWinners)
              IconButton(
                key: const Key('prev_winner_button'),
                onPressed: _currentWinnerIndex > 0 ? _previousWinner : null,
                icon: const Icon(Icons.chevron_left),
              ),

            // Winner content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasMultipleWinners)
                    Text(
                      '${_currentWinnerIndex + 1} of ${widget.winners.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  Text(
                    currentWinner.content ?? 'No content',
                    key: const Key('winner_content'),
                  ),
                  if (currentWinner.globalScore != null)
                    Text(
                      'Score: ${currentWinner.globalScore!.toStringAsFixed(1)}',
                      key: const Key('winner_score'),
                    ),
                ],
              ),
            ),

            // Right arrow (next)
            if (hasMultipleWinners)
              IconButton(
                key: const Key('next_winner_button'),
                onPressed: _currentWinnerIndex < widget.winners.length - 1
                    ? _nextWinner
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // Consensus progress
        if (widget.isSoleWinner) ...[
          Text(
            'Consecutive wins: ${widget.consecutiveSoleWins}/${widget.confirmationRoundsRequired}',
            key: const Key('consecutive_wins'),
            style: const TextStyle(color: Colors.green),
          ),
        ] else ...[
          const Text(
            'Tied win (does not count toward consensus)',
            key: Key('tie_warning'),
            style: TextStyle(color: Colors.orange),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  group('WinnerNavigationWidget', () {
    group('Single Winner (Sole)', () {
      testWidgets('displays single winner without navigation arrows', (tester) async {
        final winners = [RoundWinnerFixtures.soleWinner(content: 'Winning idea')];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: true,
              consecutiveSoleWins: 1,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        // Should show content
        expect(find.text('Winning idea'), findsOneWidget);

        // Should NOT show navigation arrows
        expect(find.byKey(const Key('prev_winner_button')), findsNothing);
        expect(find.byKey(const Key('next_winner_button')), findsNothing);

        // Should NOT show tie badge
        expect(find.textContaining('TIE'), findsNothing);

        // Should show consecutive wins
        expect(find.byKey(const Key('consecutive_wins')), findsOneWidget);
        expect(find.text('Consecutive wins: 1/2'), findsOneWidget);
      });

      testWidgets('shows score when available', (tester) async {
        final winners = [RoundWinnerFixtures.soleWinner(globalScore: 85.5)];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: true,
              consecutiveSoleWins: 2,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.text('Score: 85.5'), findsOneWidget);
      });
    });

    group('Multiple Winners (Tie)', () {
      testWidgets('displays tie badge', (tester) async {
        final winners = RoundWinnerFixtures.tiedWinners(count: 2);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.text('2-WAY TIE'), findsOneWidget);
      });

      testWidgets('displays navigation arrows for multiple winners', (tester) async {
        final winners = RoundWinnerFixtures.tiedWinners(count: 3);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.byKey(const Key('prev_winner_button')), findsOneWidget);
        expect(find.byKey(const Key('next_winner_button')), findsOneWidget);
      });

      testWidgets('shows position indicator "1 of N"', (tester) async {
        final winners = RoundWinnerFixtures.tiedWinners(count: 3);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.text('1 of 3'), findsOneWidget);
      });

      testWidgets('shows tie warning instead of consecutive wins', (tester) async {
        final winners = RoundWinnerFixtures.tiedWinners(count: 2);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.byKey(const Key('tie_warning')), findsOneWidget);
        expect(find.byKey(const Key('consecutive_wins')), findsNothing);
      });

      testWidgets('three-way tie shows correct badge', (tester) async {
        final winners = RoundWinnerFixtures.threeWayTie();

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.text('3-WAY TIE'), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('can navigate to next winner', (tester) async {
        final winners = [
          RoundWinnerFixtures.model(id: 1, content: 'First proposition'),
          RoundWinnerFixtures.model(id: 2, content: 'Second proposition'),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        // Initially shows first winner
        expect(find.text('First proposition'), findsOneWidget);
        expect(find.text('1 of 2'), findsOneWidget);

        // Tap next
        await tester.tap(find.byKey(const Key('next_winner_button')));
        await tester.pump();

        // Should show second winner
        expect(find.text('Second proposition'), findsOneWidget);
        expect(find.text('2 of 2'), findsOneWidget);
      });

      testWidgets('can navigate to previous winner', (tester) async {
        final winners = [
          RoundWinnerFixtures.model(id: 1, content: 'First proposition'),
          RoundWinnerFixtures.model(id: 2, content: 'Second proposition'),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        // Navigate to second
        await tester.tap(find.byKey(const Key('next_winner_button')));
        await tester.pump();
        expect(find.text('Second proposition'), findsOneWidget);

        // Navigate back to first
        await tester.tap(find.byKey(const Key('prev_winner_button')));
        await tester.pump();
        expect(find.text('First proposition'), findsOneWidget);
      });

      testWidgets('previous button disabled on first winner', (tester) async {
        final winners = RoundWinnerFixtures.tiedWinners(count: 3);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        // At first position, prev button should be disabled
        final prevButton = tester.widget<IconButton>(
          find.byKey(const Key('prev_winner_button')),
        );
        expect(prevButton.onPressed, isNull);
      });

      testWidgets('next button disabled on last winner', (tester) async {
        final winners = [
          RoundWinnerFixtures.model(id: 1, content: 'First'),
          RoundWinnerFixtures.model(id: 2, content: 'Second'),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        // Navigate to last
        await tester.tap(find.byKey(const Key('next_winner_button')));
        await tester.pump();

        // Next button should be disabled
        final nextButton = tester.widget<IconButton>(
          find.byKey(const Key('next_winner_button')),
        );
        expect(nextButton.onPressed, isNull);
      });

      testWidgets('can cycle through all winners', (tester) async {
        final winners = [
          RoundWinnerFixtures.model(id: 1, content: 'Winner A'),
          RoundWinnerFixtures.model(id: 2, content: 'Winner B'),
          RoundWinnerFixtures.model(id: 3, content: 'Winner C'),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        // Verify we can see all three
        expect(find.text('Winner A'), findsOneWidget);

        await tester.tap(find.byKey(const Key('next_winner_button')));
        await tester.pump();
        expect(find.text('Winner B'), findsOneWidget);

        await tester.tap(find.byKey(const Key('next_winner_button')));
        await tester.pump();
        expect(find.text('Winner C'), findsOneWidget);

        // Navigate back
        await tester.tap(find.byKey(const Key('prev_winner_button')));
        await tester.pump();
        expect(find.text('Winner B'), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('renders nothing when no winners', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: const [],
              isSoleWinner: false,
              consecutiveSoleWins: 0,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.text('Previous Winner'), findsNothing);
      });
    });

    group('Consensus Progress', () {
      testWidgets('shows 0/2 for first sole win', (tester) async {
        final winners = [RoundWinnerFixtures.soleWinner()];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: true,
              consecutiveSoleWins: 1,
              confirmationRoundsRequired: 2,
            ),
          ),
        ));

        expect(find.text('Consecutive wins: 1/2'), findsOneWidget);
      });

      testWidgets('shows progress with custom confirmation rounds', (tester) async {
        final winners = [RoundWinnerFixtures.soleWinner()];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WinnerNavigationWidget(
              winners: winners,
              isSoleWinner: true,
              consecutiveSoleWins: 2,
              confirmationRoundsRequired: 3,
            ),
          ),
        ));

        expect(find.text('Consecutive wins: 2/3'), findsOneWidget);
      });
    });
  });
}
