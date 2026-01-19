import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/rating.dart';

void main() {
  group('Rating', () {
    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final json = {
          'id': 1,
          'proposition_id': 10,
          'participant_id': 5,
          'session_token': 'token-123',
          'rating': 75,
          'created_at': '2024-01-15T10:30:00Z',
        };

        final rating = Rating.fromJson(json);

        expect(rating.id, 1);
        expect(rating.propositionId, 10);
        expect(rating.participantId, 5);
        expect(rating.sessionToken, 'token-123');
        expect(rating.rating, 75);
        expect(rating.createdAt, DateTime.utc(2024, 1, 15, 10, 30, 0));
      });

      test('handles null participant_id', () {
        final json = {
          'id': 1,
          'proposition_id': 10,
          'participant_id': null,
          'session_token': 'token-123',
          'rating': 50,
          'created_at': '2024-01-15T10:30:00Z',
        };

        final rating = Rating.fromJson(json);

        expect(rating.participantId, isNull);
      });

      test('handles null session_token', () {
        final json = {
          'id': 1,
          'proposition_id': 10,
          'participant_id': 5,
          'session_token': null,
          'rating': 50,
          'created_at': '2024-01-15T10:30:00Z',
        };

        final rating = Rating.fromJson(json);

        expect(rating.sessionToken, isNull);
      });

      test('handles missing optional fields', () {
        final json = {
          'id': 1,
          'proposition_id': 10,
          'rating': 50,
          'created_at': '2024-01-15T10:30:00Z',
        };

        final rating = Rating.fromJson(json);

        expect(rating.participantId, isNull);
        expect(rating.sessionToken, isNull);
      });

      test('parses minimum rating (0)', () {
        final json = {
          'id': 1,
          'proposition_id': 10,
          'rating': 0,
          'created_at': '2024-01-15T10:30:00Z',
        };

        final rating = Rating.fromJson(json);

        expect(rating.rating, 0);
      });

      test('parses maximum rating (100)', () {
        final json = {
          'id': 1,
          'proposition_id': 10,
          'rating': 100,
          'created_at': '2024-01-15T10:30:00Z',
        };

        final rating = Rating.fromJson(json);

        expect(rating.rating, 100);
      });
    });

    group('toJson', () {
      test('serializes correctly with all fields', () {
        final rating = Rating(
          id: 1,
          propositionId: 10,
          participantId: 5,
          sessionToken: 'token-123',
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final json = rating.toJson();

        expect(json['proposition_id'], 10);
        expect(json['participant_id'], 5);
        expect(json['session_token'], 'token-123');
        expect(json['rating'], 75);
        // toJson doesn't include id or created_at (server-generated)
        expect(json.containsKey('id'), isFalse);
        expect(json.containsKey('created_at'), isFalse);
      });

      test('serializes correctly with null optional fields', () {
        final rating = Rating(
          id: 1,
          propositionId: 10,
          participantId: null,
          sessionToken: null,
          rating: 50,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final json = rating.toJson();

        expect(json['proposition_id'], 10);
        expect(json['participant_id'], isNull);
        expect(json['session_token'], isNull);
        expect(json['rating'], 50);
      });
    });

    group('equality', () {
      test('two ratings with same id, propositionId, and rating are equal', () {
        final rating1 = Rating(
          id: 1,
          propositionId: 10,
          participantId: 5,
          sessionToken: 'token-123',
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final rating2 = Rating(
          id: 1,
          propositionId: 10,
          participantId: 5,
          sessionToken: 'token-123',
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        expect(rating1, equals(rating2));
      });

      test('ratings with different ids are not equal', () {
        final rating1 = Rating(
          id: 1,
          propositionId: 10,
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final rating2 = Rating(
          id: 2,
          propositionId: 10,
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        expect(rating1, isNot(equals(rating2)));
      });

      test('ratings with different propositionIds are not equal', () {
        final rating1 = Rating(
          id: 1,
          propositionId: 10,
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final rating2 = Rating(
          id: 1,
          propositionId: 20,
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        expect(rating1, isNot(equals(rating2)));
      });

      test('ratings with different ratings are not equal', () {
        final rating1 = Rating(
          id: 1,
          propositionId: 10,
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final rating2 = Rating(
          id: 1,
          propositionId: 10,
          rating: 50,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        expect(rating1, isNot(equals(rating2)));
      });
    });

    group('hashCode', () {
      test('equal ratings have same hashCode', () {
        final rating1 = Rating(
          id: 1,
          propositionId: 10,
          participantId: 5,
          sessionToken: 'token-123',
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final rating2 = Rating(
          id: 1,
          propositionId: 10,
          participantId: 5,
          sessionToken: 'token-123',
          rating: 75,
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        expect(rating1.hashCode, equals(rating2.hashCode));
      });
    });
  });
}
