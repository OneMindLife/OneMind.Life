import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/chat.dart';

import '../fixtures/fixtures.dart';

void main() {
  group('Chat.fromJson — cadence_anchor_at', () {
    test('parses a present timestamp', () {
      final json = ChatFixtures.json();
      json['cadence_anchor_at'] = '2026-07-02T19:00:00.000Z';

      final chat = Chat.fromJson(json);

      expect(chat.cadenceAnchorAt, DateTime.utc(2026, 7, 2, 19, 0));
    });

    test('tolerates an absent key (older RPC shapes)', () {
      final json = ChatFixtures.json();
      expect(json.containsKey('cadence_anchor_at'), isFalse);

      final chat = Chat.fromJson(json);

      expect(chat.cadenceAnchorAt, isNull);
    });

    test('tolerates an explicit null', () {
      final json = ChatFixtures.json();
      json['cadence_anchor_at'] = null;

      final chat = Chat.fromJson(json);

      expect(chat.cadenceAnchorAt, isNull);
    });
  });

  group('Chat cadenceAnchorAt — merge/copy patterns', () {
    Chat chatWithAnchor() {
      final json = ChatFixtures.json();
      json['cadence_anchor_at'] = '2026-07-02T19:00:00.000Z';
      return Chat.fromJson(json);
    }

    test('copyWith preserves the anchor when omitted', () {
      final chat = chatWithAnchor();
      final copy = chat.copyWith(name: 'Renamed');
      expect(copy.cadenceAnchorAt, chat.cadenceAnchorAt);
    });

    test('copyWith can explicitly clear the anchor', () {
      final chat = chatWithAnchor();
      final copy = chat.copyWith(cadenceAnchorAt: () => null);
      expect(copy.cadenceAnchorAt, isNull);
    });

    test('mergeRealtimePayload keeps the anchor for unrelated updates', () {
      final chat = chatWithAnchor();
      final merged = chat.mergeRealtimePayload({'host_paused': true});
      expect(merged.cadenceAnchorAt, chat.cadenceAnchorAt);
      expect(merged.hostPaused, isTrue);
    });

    test('anchor participates in equality (props)', () {
      final withAnchor = chatWithAnchor();
      final without =
          withAnchor.copyWith(cadenceAnchorAt: () => null);
      expect(withAnchor == without, isFalse);
    });
  });
}
