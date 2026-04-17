import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/chat.dart';

import '../fixtures/chat_fixtures.dart';

void main() {
  group('Chat skip settings', () {
    test('defaults to allowing skips when fields missing from JSON', () {
      final json = {
        'id': 1,
        'name': 'Test',
        'created_at': '2024-01-01T00:00:00Z',
      };

      final chat = Chat.fromJson(json);

      expect(chat.allowSkipProposing, true);
      expect(chat.allowSkipRating, true);
    });

    test('parses allow_skip_proposing = false', () {
      final json = ChatFixtures.json(allowSkipProposing: false);
      final chat = Chat.fromJson(json);

      expect(chat.allowSkipProposing, false);
      expect(chat.allowSkipRating, true);
    });

    test('parses allow_skip_rating = false', () {
      final json = ChatFixtures.json(allowSkipRating: false);
      final chat = Chat.fromJson(json);

      expect(chat.allowSkipProposing, true);
      expect(chat.allowSkipRating, false);
    });

    test('parses both skip settings as false', () {
      final chat = ChatFixtures.noSkip();

      expect(chat.allowSkipProposing, false);
      expect(chat.allowSkipRating, false);
    });

    test('skip settings included in equality check', () {
      final chat1 = Chat.fromJson(ChatFixtures.json(allowSkipProposing: true));
      final chat2 = Chat.fromJson(ChatFixtures.json(allowSkipProposing: false));

      expect(chat1, isNot(equals(chat2)));
    });
  });
}
