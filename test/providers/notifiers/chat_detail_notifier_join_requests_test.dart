import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/providers/notifiers/chat_detail_notifier.dart';

void main() {
  group('ChatDetailState pendingJoinRequests', () {
    test('default state has empty pendingJoinRequests', () {
      const state = ChatDetailState();
      expect(state.pendingJoinRequests, isEmpty);
    });

    test('copyWith updates pendingJoinRequests', () {
      const state = ChatDetailState();
      final requests = [
        {'id': 1, 'display_name': 'User1', 'is_authenticated': false},
        {'id': 2, 'display_name': 'User2', 'is_authenticated': true},
      ];

      final updated = state.copyWith(pendingJoinRequests: requests);

      expect(updated.pendingJoinRequests, hasLength(2));
      expect(updated.pendingJoinRequests[0]['display_name'], 'User1');
      expect(updated.pendingJoinRequests[1]['display_name'], 'User2');
    });

    test('copyWith preserves pendingJoinRequests when not specified', () {
      final requests = [
        {'id': 1, 'display_name': 'User1', 'is_authenticated': false},
      ];
      final state = ChatDetailState(pendingJoinRequests: requests);

      final updated = state.copyWith(hasRated: true);

      expect(updated.pendingJoinRequests, hasLength(1));
      expect(updated.hasRated, isTrue);
    });

    test('copyWith can clear pendingJoinRequests', () {
      final requests = [
        {'id': 1, 'display_name': 'User1', 'is_authenticated': false},
      ];
      final state = ChatDetailState(pendingJoinRequests: requests);

      final updated = state.copyWith(pendingJoinRequests: []);

      expect(updated.pendingJoinRequests, isEmpty);
    });
  });

  group('ChatDetailParams', () {
    test('equality works correctly', () {
      const params1 = ChatDetailParams(
        chatId: 1,
        showPreviousResults: false,
      );
      const params2 = ChatDetailParams(
        chatId: 1,
        showPreviousResults: false,
      );
      const params3 = ChatDetailParams(
        chatId: 2,
        showPreviousResults: false,
      );

      expect(params1, equals(params2));
      expect(params1, isNot(equals(params3)));
    });

    test('hashCode is consistent', () {
      const params1 = ChatDetailParams(
        chatId: 1,
        showPreviousResults: false,
      );
      const params2 = ChatDetailParams(
        chatId: 1,
        showPreviousResults: false,
      );

      expect(params1.hashCode, equals(params2.hashCode));
    });
  });
}
