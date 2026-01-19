import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/proposition.dart';

void main() {
  group('Proposition', () {
    group('fromJson', () {
      test('parses minimal fields', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final proposition = Proposition.fromJson(json);

        expect(proposition.id, 1);
        expect(proposition.roundId, 10);
        expect(proposition.content, 'A great idea');
        expect(proposition.participantId, isNull);
        expect(proposition.finalRating, isNull);
        expect(proposition.rank, isNull);
      });

      test('parses all fields without ratings', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final proposition = Proposition.fromJson(json);

        expect(proposition.id, 1);
        expect(proposition.roundId, 10);
        expect(proposition.participantId, 5);
        expect(proposition.content, 'A great idea');
        expect(proposition.finalRating, isNull);
        expect(proposition.rank, isNull);
      });

      test('parses with proposition_movda_ratings', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
          'proposition_movda_ratings': {
            'rating': 85.5,
            'rank': 1,
          },
        };

        final proposition = Proposition.fromJson(json);

        expect(proposition.id, 1);
        expect(proposition.finalRating, 85.5);
        expect(proposition.rank, 1);
      });

      test('handles integer rating', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
          'proposition_movda_ratings': {
            'rating': 85,
            'rank': 1,
          },
        };

        final proposition = Proposition.fromJson(json);
        expect(proposition.finalRating, 85.0);
      });

      test('handles null rating in proposition_movda_ratings', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
          'proposition_movda_ratings': {
            'rating': null,
            'rank': null,
          },
        };

        final proposition = Proposition.fromJson(json);
        expect(proposition.finalRating, isNull);
        expect(proposition.rank, isNull);
      });

      test('parses with proposition_global_scores (0-100 percentile)', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
          'proposition_global_scores': {
            'global_score': 87.5,
          },
        };

        final proposition = Proposition.fromJson(json);

        expect(proposition.id, 1);
        expect(proposition.finalRating, 87.5);
      });

      test('parses proposition_global_scores as array (PostgREST format)', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
          'proposition_global_scores': [
            {'global_score': 92.3},
          ],
        };

        final proposition = Proposition.fromJson(json);
        expect(proposition.finalRating, 92.3);
      });

      test('prefers proposition_global_scores over proposition_movda_ratings', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
          'proposition_global_scores': {
            'global_score': 75.0,
          },
          'proposition_movda_ratings': {
            'rating': 1650.5, // Raw MOVDA Elo - should be ignored
            'rank': 1,
          },
        };

        final proposition = Proposition.fromJson(json);
        // Should use global_score (0-100), not raw MOVDA Elo
        expect(proposition.finalRating, 75.0);
      });

      test('falls back to proposition_movda_ratings if global_scores absent', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'content': 'A great idea',
          'created_at': '2024-01-01T00:00:00Z',
          'proposition_movda_ratings': {
            'rating': 85.5,
            'rank': 2,
          },
        };

        final proposition = Proposition.fromJson(json);
        expect(proposition.finalRating, 85.5);
        expect(proposition.rank, 2);
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final proposition = Proposition(
          id: 1,
          roundId: 10,
          participantId: 5,
          content: 'A great idea',
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final json = proposition.toJson();

        expect(json['round_id'], 10);
        expect(json['participant_id'], 5);
        expect(json['content'], 'A great idea');
      });

      test('serializes without participant_id', () {
        final proposition = Proposition(
          id: 1,
          roundId: 10,
          content: 'A great idea',
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final json = proposition.toJson();

        expect(json['round_id'], 10);
        expect(json['participant_id'], isNull);
        expect(json['content'], 'A great idea');
      });
    });

    group('equality', () {
      test('two propositions with same id are equal', () {
        final p1 = Proposition(
          id: 1,
          roundId: 10,
          content: 'A great idea',
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final p2 = Proposition(
          id: 1,
          roundId: 10,
          content: 'A great idea',
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(p1, equals(p2));
      });
    });
  });
}
