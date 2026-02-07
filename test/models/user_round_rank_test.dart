import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/user_round_rank.dart';

void main() {
  group('UserRoundRank', () {
    group('fromJson', () {
      test('parses all fields', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 75.5,
          'voting_rank': 80.0,
          'proposing_rank': 71.0,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.id, 1);
        expect(userRank.roundId, 10);
        expect(userRank.participantId, 5);
        expect(userRank.rank, 75.5);
        expect(userRank.votingRank, 80.0);
        expect(userRank.proposingRank, 71.0);
        expect(userRank.displayName, isNull);
      });

      test('parses with null voting_rank', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 85.0,
          'voting_rank': null,
          'proposing_rank': 85.0,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.votingRank, isNull);
        expect(userRank.proposingRank, 85.0);
        expect(userRank.rank, 85.0);
      });

      test('parses with null proposing_rank', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 90.0,
          'voting_rank': 90.0,
          'proposing_rank': null,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.votingRank, 90.0);
        expect(userRank.proposingRank, isNull);
        expect(userRank.rank, 90.0);
      });

      test('handles integer rank values', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 75,
          'voting_rank': 80,
          'proposing_rank': 70,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.rank, 75.0);
        expect(userRank.votingRank, 80.0);
        expect(userRank.proposingRank, 70.0);
      });

      test('parses joined participants data as Map', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 75.0,
          'voting_rank': null,
          'proposing_rank': null,
          'created_at': '2024-01-01T00:00:00Z',
          'participants': {
            'display_name': 'Alice',
          },
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.displayName, 'Alice');
      });

      test('parses joined participants data as List (PostgREST format)', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 75.0,
          'voting_rank': null,
          'proposing_rank': null,
          'created_at': '2024-01-01T00:00:00Z',
          'participants': [
            {'display_name': 'Bob'},
          ],
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.displayName, 'Bob');
      });

      test('handles empty participants list', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 75.0,
          'voting_rank': null,
          'proposing_rank': null,
          'created_at': '2024-01-01T00:00:00Z',
          'participants': <dynamic>[],
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.displayName, isNull);
      });

      test('handles null participants', () {
        final json = {
          'id': 1,
          'round_id': 10,
          'participant_id': 5,
          'rank': 75.0,
          'voting_rank': null,
          'proposing_rank': null,
          'created_at': '2024-01-01T00:00:00Z',
          'participants': null,
        };

        final userRank = UserRoundRank.fromJson(json);

        expect(userRank.displayName, isNull);
      });
    });

    group('equality', () {
      test('two UserRoundRanks with same values are equal', () {
        final u1 = UserRoundRank(
          id: 1,
          roundId: 10,
          participantId: 5,
          rank: 75.0,
          votingRank: 80.0,
          proposingRank: 70.0,
          createdAt: DateTime.utc(2024, 1, 1),
          displayName: 'Alice',
        );

        final u2 = UserRoundRank(
          id: 1,
          roundId: 10,
          participantId: 5,
          rank: 75.0,
          votingRank: 80.0,
          proposingRank: 70.0,
          createdAt: DateTime.utc(2024, 1, 1),
          displayName: 'Alice',
        );

        expect(u1, equals(u2));
      });

      test('two UserRoundRanks with different values are not equal', () {
        final u1 = UserRoundRank(
          id: 1,
          roundId: 10,
          participantId: 5,
          rank: 75.0,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final u2 = UserRoundRank(
          id: 2,
          roundId: 10,
          participantId: 5,
          rank: 75.0,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(u1, isNot(equals(u2)));
      });
    });
  });
}
