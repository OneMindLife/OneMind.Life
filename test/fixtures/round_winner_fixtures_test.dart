import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import '../fixtures/fixtures.dart';

void main() {
  group('RoundWinnerFixtures', () {
    group('json()', () {
      test('creates valid JSON structure', () {
        final json = RoundWinnerFixtures.json();

        expect(json['id'], 1);
        expect(json['round_id'], 1);
        expect(json['proposition_id'], 1);
        expect(json['rank'], 1);
        expect(json['global_score'], 75.0);
        expect(json['created_at'], isNotNull);
      });

      test('includes nested proposition content when provided', () {
        final json = RoundWinnerFixtures.json(content: 'Test content');

        expect(json['propositions'], isNotNull);
        expect(json['propositions']['content'], 'Test content');
      });

      test('parses to valid RoundWinner model', () {
        final json = RoundWinnerFixtures.json(
          id: 5,
          roundId: 10,
          propositionId: 20,
          rank: 1,
          globalScore: 85.5,
        );

        final winner = RoundWinner.fromJson(json);

        expect(winner.id, 5);
        expect(winner.roundId, 10);
        expect(winner.propositionId, 20);
        expect(winner.rank, 1);
        expect(winner.globalScore, 85.5);
      });
    });

    group('model()', () {
      test('creates valid RoundWinner instance', () {
        final winner = RoundWinnerFixtures.model();

        expect(winner.id, 1);
        expect(winner.roundId, 1);
        expect(winner.propositionId, 1);
        expect(winner.rank, 1);
        expect(winner.globalScore, 75.0);
      });

      test('accepts custom parameters', () {
        final winner = RoundWinnerFixtures.model(
          id: 99,
          roundId: 50,
          propositionId: 200,
          globalScore: 92.5,
          content: 'Custom proposition',
        );

        expect(winner.id, 99);
        expect(winner.roundId, 50);
        expect(winner.propositionId, 200);
        expect(winner.globalScore, 92.5);
        expect(winner.content, 'Custom proposition');
      });
    });

    group('soleWinner()', () {
      test('creates winner with default values', () {
        final winner = RoundWinnerFixtures.soleWinner();

        expect(winner.globalScore, 85.0);
        expect(winner.content, 'Winning proposition');
      });

      test('creates winner with custom values', () {
        final winner = RoundWinnerFixtures.soleWinner(
          id: 10,
          roundId: 5,
          propositionId: 100,
          globalScore: 95.0,
          content: 'My winning idea',
        );

        expect(winner.id, 10);
        expect(winner.roundId, 5);
        expect(winner.propositionId, 100);
        expect(winner.globalScore, 95.0);
        expect(winner.content, 'My winning idea');
      });
    });

    group('tiedWinners()', () {
      test('creates two tied winners by default', () {
        final winners = RoundWinnerFixtures.tiedWinners();

        expect(winners, hasLength(2));
        expect(winners[0].rank, 1);
        expect(winners[1].rank, 1);
        expect(winners[0].globalScore, winners[1].globalScore);
      });

      test('creates specified number of tied winners', () {
        final winners = RoundWinnerFixtures.tiedWinners(count: 4);

        expect(winners, hasLength(4));
        for (final winner in winners) {
          expect(winner.rank, 1);
          expect(winner.globalScore, 50.0);
        }
      });

      test('all winners have same round ID', () {
        final winners = RoundWinnerFixtures.tiedWinners(roundId: 99, count: 3);

        for (final winner in winners) {
          expect(winner.roundId, 99);
        }
      });

      test('each winner has unique proposition ID', () {
        final winners = RoundWinnerFixtures.tiedWinners(count: 5);
        final propositionIds = winners.map((w) => w.propositionId).toSet();

        expect(propositionIds, hasLength(5));
      });
    });

    group('tiedWinnersJson()', () {
      test('creates JSON list for tied winners', () {
        final jsonList = RoundWinnerFixtures.tiedWinnersJson(count: 3);

        expect(jsonList, hasLength(3));
        for (final json in jsonList) {
          expect(json['rank'], 1);
          expect(json['global_score'], 50.0);
        }
      });

      test('JSON can be parsed to models', () {
        final jsonList = RoundWinnerFixtures.tiedWinnersJson(roundId: 10);

        final winners = jsonList.map((j) => RoundWinner.fromJson(j)).toList();

        expect(winners, hasLength(2));
        expect(winners[0].roundId, 10);
        expect(winners[1].roundId, 10);
      });
    });

    group('threeWayTie()', () {
      test('creates exactly three winners', () {
        final winners = RoundWinnerFixtures.threeWayTie();

        expect(winners, hasLength(3));
      });

      test('all three have rank 1 with equal scores', () {
        final winners = RoundWinnerFixtures.threeWayTie();

        for (final winner in winners) {
          expect(winner.rank, 1);
          expect(winner.globalScore, closeTo(33.33, 0.01));
        }
      });

      test('respects custom round ID', () {
        final winners = RoundWinnerFixtures.threeWayTie(roundId: 42);

        for (final winner in winners) {
          expect(winner.roundId, 42);
        }
      });
    });
  });

  group('RoundFixtures with isSoleWinner', () {
    group('json()', () {
      test('includes is_sole_winner when provided', () {
        final json = RoundFixtures.json(
          winningPropositionId: 1,
          isSoleWinner: true,
        );

        expect(json['is_sole_winner'], true);
      });

      test('is_sole_winner defaults to null', () {
        final json = RoundFixtures.json();

        expect(json['is_sole_winner'], isNull);
      });
    });

    group('soleWinner()', () {
      test('creates round with isSoleWinner = true', () {
        final round = RoundFixtures.soleWinner();

        expect(round.isSoleWinner, true);
        expect(round.winningPropositionId, isNotNull);
      });
    });

    group('tiedWinner()', () {
      test('creates round with isSoleWinner = false', () {
        final round = RoundFixtures.tiedWinner();

        expect(round.isSoleWinner, false);
        expect(round.winningPropositionId, isNotNull);
      });
    });

    group('completed()', () {
      test('defaults to sole winner', () {
        final round = RoundFixtures.completed();

        expect(round.isSoleWinner, true);
      });

      test('can specify tied winner', () {
        final round = RoundFixtures.completed(isSoleWinner: false);

        expect(round.isSoleWinner, false);
      });
    });
  });
}
