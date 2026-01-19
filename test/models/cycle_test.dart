import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/cycle.dart';

void main() {
  group('Cycle', () {
    group('fromJson', () {
      test('parses minimal fields', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final cycle = Cycle.fromJson(json);

        expect(cycle.id, 1);
        expect(cycle.chatId, 10);
        expect(cycle.winningPropositionId, isNull);
        expect(cycle.completedAt, isNull);
      });

      test('parses all fields', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'winning_proposition_id': 5,
          'created_at': '2024-01-01T00:00:00Z',
          'completed_at': '2024-01-01T12:00:00Z',
        };

        final cycle = Cycle.fromJson(json);

        expect(cycle.id, 1);
        expect(cycle.chatId, 10);
        expect(cycle.winningPropositionId, 5);
        expect(cycle.createdAt, DateTime.utc(2024, 1, 1));
        expect(cycle.completedAt, DateTime.utc(2024, 1, 1, 12, 0, 0));
      });
    });

    group('isComplete', () {
      test('returns true when winningPropositionId is set', () {
        final cycle = Cycle(
          id: 1,
          chatId: 10,
          winningPropositionId: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(cycle.isComplete, true);
      });

      test('returns false when winningPropositionId is null', () {
        final cycle = Cycle(
          id: 1,
          chatId: 10,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(cycle.isComplete, false);
      });
    });

    group('equality', () {
      test('two cycles with same id are equal', () {
        final c1 = Cycle(
          id: 1,
          chatId: 10,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final c2 = Cycle(
          id: 1,
          chatId: 10,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(c1, equals(c2));
      });
    });
  });
}
