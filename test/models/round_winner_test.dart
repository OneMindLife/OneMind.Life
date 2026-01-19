import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';

void main() {
  group('RoundWinner', () {
    group('fromJson', () {
      test('parses basic fields correctly', () {
        final json = {
          'id': 1,
          'round_id': 100,
          'proposition_id': 200,
          'rank': 1,
          'global_score': 75.5,
          'created_at': '2026-01-10T12:00:00Z',
        };

        final winner = RoundWinner.fromJson(json);

        expect(winner.id, 1);
        expect(winner.roundId, 100);
        expect(winner.propositionId, 200);
        expect(winner.rank, 1);
        expect(winner.globalScore, 75.5);
        expect(winner.createdAt, DateTime.utc(2026, 1, 10, 12, 0, 0));
        expect(winner.content, isNull);
      });

      test('parses nested proposition content (Map)', () {
        final json = {
          'id': 1,
          'round_id': 100,
          'proposition_id': 200,
          'rank': 1,
          'created_at': '2026-01-10T12:00:00Z',
          'propositions': {
            'content': 'This is the winning proposition',
          },
        };

        final winner = RoundWinner.fromJson(json);

        expect(winner.content, 'This is the winning proposition');
      });

      test('parses nested proposition content (List)', () {
        final json = {
          'id': 1,
          'round_id': 100,
          'proposition_id': 200,
          'rank': 1,
          'created_at': '2026-01-10T12:00:00Z',
          'propositions': [
            {'content': 'First proposition content'},
          ],
        };

        final winner = RoundWinner.fromJson(json);

        expect(winner.content, 'First proposition content');
      });

      test('handles null global_score', () {
        final json = {
          'id': 1,
          'round_id': 100,
          'proposition_id': 200,
          'rank': 1,
          'global_score': null,
          'created_at': '2026-01-10T12:00:00Z',
        };

        final winner = RoundWinner.fromJson(json);

        expect(winner.globalScore, isNull);
      });

      test('defaults rank to 1 if missing', () {
        final json = {
          'id': 1,
          'round_id': 100,
          'proposition_id': 200,
          'created_at': '2026-01-10T12:00:00Z',
        };

        final winner = RoundWinner.fromJson(json);

        expect(winner.rank, 1);
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final winner = RoundWinner(
          id: 1,
          roundId: 100,
          propositionId: 200,
          rank: 1,
          globalScore: 75.5,
          createdAt: DateTime.utc(2026, 1, 10, 12, 0, 0),
        );

        final json = winner.toJson();

        expect(json['id'], 1);
        expect(json['round_id'], 100);
        expect(json['proposition_id'], 200);
        expect(json['rank'], 1);
        expect(json['global_score'], 75.5);
        expect(json['created_at'], '2026-01-10T12:00:00.000Z');
      });
    });

    group('equality', () {
      test('two winners with same id/roundId/propositionId/rank are equal', () {
        final fixedDate = DateTime.utc(2024, 1, 1);
        final winner1 = RoundWinner(
          id: 1,
          roundId: 100,
          propositionId: 200,
          rank: 1,
          createdAt: fixedDate,
        );

        final winner2 = RoundWinner(
          id: 1,
          roundId: 100,
          propositionId: 200,
          rank: 1,
          createdAt: fixedDate,
        );

        expect(winner1, equals(winner2));
      });

      test('winners with different ids are not equal', () {
        final winner1 = RoundWinner(
          id: 1,
          roundId: 100,
          propositionId: 200,
          rank: 1,
          createdAt: DateTime.now(),
        );

        final winner2 = RoundWinner(
          id: 2,
          roundId: 100,
          propositionId: 200,
          rank: 1,
          createdAt: DateTime.now(),
        );

        expect(winner1, isNot(equals(winner2)));
      });
    });

    group('toString', () {
      test('includes key information', () {
        final winner = RoundWinner(
          id: 1,
          roundId: 100,
          propositionId: 200,
          rank: 1,
          globalScore: 75.5,
          createdAt: DateTime.now(),
        );

        final str = winner.toString();

        expect(str, contains('id: 1'));
        expect(str, contains('roundId: 100'));
        expect(str, contains('propositionId: 200'));
        expect(str, contains('rank: 1'));
        expect(str, contains('score: 75.5'));
      });
    });
  });

  group('Round with isSoleWinner', () {
    test('parses is_sole_winner correctly', () {
      final json = {
        'id': 1,
        'cycle_id': 10,
        'custom_id': 1,
        'phase': 'rating',
        'winning_proposition_id': 100,
        'is_sole_winner': true,
        'created_at': '2026-01-10T12:00:00Z',
      };

      final round = Round.fromJson(json);

      expect(round.isSoleWinner, true);
    });

    test('parses is_sole_winner as false', () {
      final json = {
        'id': 1,
        'cycle_id': 10,
        'custom_id': 1,
        'phase': 'rating',
        'winning_proposition_id': 100,
        'is_sole_winner': false,
        'created_at': '2026-01-10T12:00:00Z',
      };

      final round = Round.fromJson(json);

      expect(round.isSoleWinner, false);
    });

    test('handles null is_sole_winner', () {
      final json = {
        'id': 1,
        'cycle_id': 10,
        'custom_id': 1,
        'phase': 'rating',
        'created_at': '2026-01-10T12:00:00Z',
      };

      final round = Round.fromJson(json);

      expect(round.isSoleWinner, isNull);
    });

    test('isSoleWinner is included in props', () {
      final round1 = Round(
        id: 1,
        cycleId: 10,
        customId: 1,
        phase: RoundPhase.rating,
        isSoleWinner: true,
        createdAt: DateTime.now(),
      );

      final round2 = Round(
        id: 1,
        cycleId: 10,
        customId: 1,
        phase: RoundPhase.rating,
        isSoleWinner: false,
        createdAt: DateTime.now(),
      );

      // Different isSoleWinner values should make them not equal
      expect(round1, isNot(equals(round2)));
    });
  });
}
