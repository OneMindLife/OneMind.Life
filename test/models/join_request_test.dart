import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/join_request.dart';

void main() {
  group('JoinRequest', () {
    group('fromJson', () {
      test('parses basic fields correctly', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'session_token': 'abc-123',
          'display_name': 'Test User',
          'is_authenticated': false,
          'status': 'pending',
          'created_at': '2026-01-13T10:00:00Z',
        };

        final request = JoinRequest.fromJson(json);

        expect(request.id, 1);
        expect(request.chatId, 10);
        expect(request.sessionToken, 'abc-123');
        expect(request.displayName, 'Test User');
        expect(request.isAuthenticated, false);
        expect(request.status, JoinRequestStatus.pending);
        expect(request.resolvedAt, isNull);
      });

      test('parses nested chat data', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'session_token': 'abc-123',
          'display_name': 'Test User',
          'is_authenticated': false,
          'status': 'pending',
          'created_at': '2026-01-13T10:00:00Z',
          'chats': {
            'name': 'Test Chat',
            'initial_message': 'Welcome!',
          },
        };

        final request = JoinRequest.fromJson(json);

        expect(request.chatName, 'Test Chat');
        expect(request.chatInitialMessage, 'Welcome!');
      });

      test('parses all status values correctly', () {
        final statuses = {
          'pending': JoinRequestStatus.pending,
          'approved': JoinRequestStatus.approved,
          'denied': JoinRequestStatus.denied,
          'cancelled': JoinRequestStatus.cancelled,
        };

        for (final entry in statuses.entries) {
          final json = {
            'id': 1,
            'chat_id': 10,
            'display_name': 'Test',
            'status': entry.key,
            'created_at': '2026-01-13T10:00:00Z',
          };

          final request = JoinRequest.fromJson(json);
          expect(request.status, entry.value);
        }
      });

      test('defaults to pending for unknown status', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'display_name': 'Test',
          'status': 'unknown_status',
          'created_at': '2026-01-13T10:00:00Z',
        };

        final request = JoinRequest.fromJson(json);
        expect(request.status, JoinRequestStatus.pending);
      });

      test('handles resolved_at field', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'display_name': 'Test',
          'status': 'approved',
          'created_at': '2026-01-13T10:00:00Z',
          'resolved_at': '2026-01-13T11:00:00Z',
        };

        final request = JoinRequest.fromJson(json);

        expect(request.resolvedAt, isNotNull);
        expect(request.resolvedAt!.hour, 11);
      });

      test('handles null resolved_at', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'display_name': 'Test',
          'status': 'pending',
          'created_at': '2026-01-13T10:00:00Z',
          'resolved_at': null,
        };

        final request = JoinRequest.fromJson(json);
        expect(request.resolvedAt, isNull);
      });

      test('handles authenticated user with user_id', () {
        final json = {
          'id': 1,
          'chat_id': 10,
          'user_id': 'user-uuid-123',
          'display_name': 'Auth User',
          'is_authenticated': true,
          'status': 'pending',
          'created_at': '2026-01-13T10:00:00Z',
        };

        final request = JoinRequest.fromJson(json);

        expect(request.userId, 'user-uuid-123');
        expect(request.sessionToken, isNull);
        expect(request.isAuthenticated, true);
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final request = JoinRequest(
          id: 1,
          chatId: 10,
          sessionToken: 'token-123',
          displayName: 'Test User',
          isAuthenticated: false,
          status: JoinRequestStatus.pending,
          createdAt: DateTime(2026, 1, 13, 10, 0, 0),
        );

        final json = request.toJson();

        expect(json['chat_id'], 10);
        expect(json['session_token'], 'token-123');
        expect(json['display_name'], 'Test User');
        expect(json['is_authenticated'], false);
        expect(json['status'], 'pending');
      });
    });

    group('equality', () {
      test('equal requests have same props', () {
        final fixedDate = DateTime.utc(2024, 1, 1);
        final request1 = JoinRequest(
          id: 1,
          chatId: 10,
          displayName: 'Test',
          isAuthenticated: false,
          status: JoinRequestStatus.pending,
          createdAt: fixedDate,
        );

        final request2 = JoinRequest(
          id: 1,
          chatId: 10,
          displayName: 'Test',
          isAuthenticated: false,
          status: JoinRequestStatus.pending,
          createdAt: fixedDate,
        );

        expect(request1, equals(request2));
      });

      test('different ids are not equal', () {
        final request1 = JoinRequest(
          id: 1,
          chatId: 10,
          displayName: 'Test',
          isAuthenticated: false,
          status: JoinRequestStatus.pending,
          createdAt: DateTime.now(),
        );

        final request2 = JoinRequest(
          id: 2,
          chatId: 10,
          displayName: 'Test',
          isAuthenticated: false,
          status: JoinRequestStatus.pending,
          createdAt: DateTime.now(),
        );

        expect(request1, isNot(equals(request2)));
      });
    });
  });
}
