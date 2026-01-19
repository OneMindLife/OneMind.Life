import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/services/winner_calculator.dart';

void main() {
  group('WinnerCalculator', () {
    group('calculateWinners', () {
      test('returns empty results for empty rankings', () {
        final result = WinnerCalculator.calculateWinners([]);

        expect(result['winnerIds'], isEmpty);
        expect(result['highestScore'], 0.0);
        expect(result['isSoleWinner'], false);
      });

      test('identifies sole winner with highest position (higher = better)', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 100}, // best (top)
          {'proposition_id': 2, 'grid_position': 50},  // middle
          {'proposition_id': 3, 'grid_position': 25},  // worst (bottom)
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [1]); // Highest position wins
        expect(result['highestScore'], 100.0);
        expect(result['isSoleWinner'], true);
      });

      test('identifies 2-way tie at highest position', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 100}, // tied for best
          {'proposition_id': 2, 'grid_position': 100}, // tied for best
          {'proposition_id': 3, 'grid_position': 50},  // worse
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], containsAll([1, 2]));
        expect((result['winnerIds'] as List).length, 2);
        expect(result['highestScore'], 100.0);
        expect(result['isSoleWinner'], false);
      });

      test('identifies 3-way tie', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 75},
          {'proposition_id': 2, 'grid_position': 75},
          {'proposition_id': 3, 'grid_position': 75},
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], containsAll([1, 2, 3]));
        expect((result['winnerIds'] as List).length, 3);
        expect(result['highestScore'], 75.0);
        expect(result['isSoleWinner'], false);
      });

      test('calculates average from multiple ratings - highest wins', () {
        // Proposition 1: ratings 100, 80 → avg 90 (better)
        // Proposition 2: ratings 70, 90 → avg 80 (worse)
        final rankings = [
          {'proposition_id': 1, 'grid_position': 100},
          {'proposition_id': 1, 'grid_position': 80},
          {'proposition_id': 2, 'grid_position': 70},
          {'proposition_id': 2, 'grid_position': 90},
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [1]); // Higher avg wins
        expect(result['highestScore'], 90.0);
        expect(result['isSoleWinner'], true);
      });

      test('handles tie when averages are equal', () {
        // Proposition 1: ratings 100, 0 → avg 50
        // Proposition 2: ratings 50, 50 → avg 50
        final rankings = [
          {'proposition_id': 1, 'grid_position': 100},
          {'proposition_id': 1, 'grid_position': 0},
          {'proposition_id': 2, 'grid_position': 50},
          {'proposition_id': 2, 'grid_position': 50},
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], containsAll([1, 2]));
        expect((result['winnerIds'] as List).length, 2);
        expect(result['highestScore'], 50.0);
        expect(result['isSoleWinner'], false);
      });

      test('handles single proposition with single rating', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 65},
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [1]);
        expect(result['highestScore'], 65.0);
        expect(result['isSoleWinner'], true);
      });

      test('handles single proposition with multiple ratings', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 60},
          {'proposition_id': 1, 'grid_position': 80},
          {'proposition_id': 1, 'grid_position': 100},
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [1]);
        expect(result['highestScore'], 80.0); // (60+80+100)/3 = 80
        expect(result['isSoleWinner'], true);
      });

      test('handles decimal grid positions - highest wins', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 33.33}, // loser (lower)
          {'proposition_id': 2, 'grid_position': 66.67}, // winner (higher)
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [2]); // Higher position wins
        expect(result['highestScore'], 66.67);
        expect(result['isSoleWinner'], true);
      });

      test('handles zero scores - all tied at bottom', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 0},
          {'proposition_id': 2, 'grid_position': 0},
          {'proposition_id': 3, 'grid_position': 0},
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect((result['winnerIds'] as List).length, 3);
        expect(result['highestScore'], 0.0);
        expect(result['isSoleWinner'], false);
      });

      test('handles mixed integer and double grid positions', () {
        final rankings = [
          {'proposition_id': 1, 'grid_position': 100},  // int, winner
          {'proposition_id': 2, 'grid_position': 99.5}, // double, loser
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [1]); // Higher position wins
        expect(result['highestScore'], 100.0);
        expect(result['isSoleWinner'], true);
      });

      test('realistic scenario: 3 participants rating 3 propositions', () {
        // Each participant rates 2 propositions (not their own)
        // Participant 1 submitted prop A, rates B=80, C=20
        // Participant 2 submitted prop B, rates A=60, C=90
        // Participant 3 submitted prop C, rates A=40, B=70
        // Averages: A=(60+40)/2=50, B=(80+70)/2=75, C=(20+90)/2=55
        // Winner: B with highest avg of 75
        final rankings = [
          // Participant 1's ratings
          {'proposition_id': 2, 'grid_position': 80}, // B
          {'proposition_id': 3, 'grid_position': 20}, // C
          // Participant 2's ratings
          {'proposition_id': 1, 'grid_position': 60}, // A
          {'proposition_id': 3, 'grid_position': 90}, // C
          // Participant 3's ratings
          {'proposition_id': 1, 'grid_position': 40}, // A
          {'proposition_id': 2, 'grid_position': 70}, // B
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [2]); // Proposition B wins (highest avg = 75)
        expect(result['highestScore'], 75.0);
        expect(result['isSoleWinner'], true);
      });

      test('realistic scenario: all participants agree (unanimous winner)', () {
        // All 3 participants give proposition 1 a score of 100 (top/best)
        // and proposition 2 a score of 0 (bottom/worst)
        final rankings = [
          {'proposition_id': 1, 'grid_position': 100},
          {'proposition_id': 1, 'grid_position': 100},
          {'proposition_id': 1, 'grid_position': 100},
          {'proposition_id': 2, 'grid_position': 0},
          {'proposition_id': 2, 'grid_position': 0},
          {'proposition_id': 2, 'grid_position': 0},
        ];

        final result = WinnerCalculator.calculateWinners(rankings);

        expect(result['winnerIds'], [1]); // Prop 1 wins with 100 (best)
        expect(result['highestScore'], 100.0);
        expect(result['isSoleWinner'], true);
      });
    });
  });
}
