import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/participant.dart';

void main() {
  group('Participant', () {
    group('fromJson', () {
      test('parses minimal fields', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'display_name': 'Test User',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final participant = Participant.fromJson(json);

        expect(participant.id, 1);
        expect(participant.chatId, 10);
        expect(participant.displayName, 'Test User');
        expect(participant.userId, isNull);
        expect(participant.sessionToken, isNull);
        expect(participant.isHost, false);
        expect(participant.isAuthenticated, false);
        expect(participant.status, ParticipantStatus.active);
      });

      test('parses all fields', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'user_id': 'user-123',
          'session_token': 'session-456',
          'display_name': 'Host User',
          'is_host': true,
          'is_authenticated': true,
          'status': 'active',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final participant = Participant.fromJson(json);

        expect(participant.id, 1);
        expect(participant.chatId, 10);
        expect(participant.userId, 'user-123');
        expect(participant.sessionToken, 'session-456');
        expect(participant.displayName, 'Host User');
        expect(participant.isHost, true);
        expect(participant.isAuthenticated, true);
        expect(participant.status, ParticipantStatus.active);
      });

      test('parses status pending', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'display_name': 'Test',
          'status': 'pending',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final participant = Participant.fromJson(json);
        expect(participant.status, ParticipantStatus.pending);
      });

      test('parses status kicked', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'display_name': 'Test',
          'status': 'kicked',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final participant = Participant.fromJson(json);
        expect(participant.status, ParticipantStatus.kicked);
      });

      test('parses status left', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'display_name': 'Test',
          'status': 'left',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final participant = Participant.fromJson(json);
        expect(participant.status, ParticipantStatus.left);
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final participant = Participant(
          id: 1,
          chatId: 10,
          userId: 'user-123',
          sessionToken: 'session-456',
          displayName: 'Test User',
          isHost: true,
          isAuthenticated: true,
          status: ParticipantStatus.active,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final json = participant.toJson();

        expect(json['chat_id'], 10);
        expect(json['user_id'], 'user-123');
        expect(json['session_token'], 'session-456');
        expect(json['display_name'], 'Test User');
        expect(json['is_host'], true);
        expect(json['is_authenticated'], true);
        expect(json['status'], 'active');
      });
    });

    group('equality', () {
      test('two participants with same id are equal', () {
        final p1 = Participant(
          id: 1,
          chatId: 10,
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: false,
          status: ParticipantStatus.active,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final p2 = Participant(
          id: 1,
          chatId: 10,
          displayName: 'Test User',
          isHost: false,
          isAuthenticated: false,
          status: ParticipantStatus.active,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(p1, equals(p2));
      });
    });
  });
}
