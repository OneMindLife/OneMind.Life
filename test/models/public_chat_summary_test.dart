import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/public_chat_summary.dart';

void main() {
  group('PublicChatSummary', () {
    group('fromJson', () {
      test('parses all fields correctly', () {
        final json = {
          'id': 1,
          'name': 'Public Test Chat',
          'description': 'A public chat for testing',
          'initial_message': 'What should we discuss?',
          'participant_count': 10,
          'created_at': '2024-01-01T00:00:00Z',
          'last_activity_at': '2024-06-15T12:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.id, 1);
        expect(summary.name, 'Public Test Chat');
        expect(summary.description, 'A public chat for testing');
        expect(summary.initialMessage, 'What should we discuss?');
        expect(summary.participantCount, 10);
        expect(summary.createdAt, DateTime.utc(2024, 1, 1, 0, 0, 0));
        expect(summary.lastActivityAt, DateTime.utc(2024, 6, 15, 12, 0, 0));
      });

      test('handles null description', () {
        final json = {
          'id': 2,
          'name': 'No Description Chat',
          'description': null,
          'initial_message': 'Test message',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
          'last_activity_at': null,
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.id, 2);
        expect(summary.name, 'No Description Chat');
        expect(summary.description, isNull);
        expect(summary.lastActivityAt, isNull);
      });

      test('handles missing participant_count', () {
        final json = {
          'id': 3,
          'name': 'Test Chat',
          'initial_message': 'Test message',
          'participant_count': null,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.participantCount, 0);
      });

      test('handles participant_count as double', () {
        final json = {
          'id': 4,
          'name': 'Test Chat',
          'initial_message': 'Test message',
          'participant_count': 7.0,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.participantCount, 7);
      });
    });

    group('equality', () {
      test('two summaries with same props are equal', () {
        final summary1 = PublicChatSummary(
          id: 1,
          name: 'Test',
          description: 'Desc',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final summary2 = PublicChatSummary(
          id: 1,
          name: 'Test',
          description: 'Desc',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(summary1, equals(summary2));
      });

      test('two summaries with different IDs are not equal', () {
        final summary1 = PublicChatSummary(
          id: 1,
          name: 'Test',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final summary2 = PublicChatSummary(
          id: 2,
          name: 'Test',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(summary1, isNot(equals(summary2)));
      });
    });
  });
}
