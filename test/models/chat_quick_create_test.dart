import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/chat.dart';

import '../fixtures/chat_fixtures.dart';

void main() {
  group('Chat quick-create fields', () {
    group('fromJson', () {
      test('parses max_cycles, ended_at, is_preview', () {
        final endedAt = DateTime.parse('2026-05-29T12:34:56.000Z');
        final json = ChatFixtures.json();
        json['max_cycles'] = 1;
        json['ended_at'] = endedAt.toIso8601String();
        json['is_preview'] = true;

        final chat = Chat.fromJson(json);

        expect(chat.maxCycles, 1);
        expect(chat.endedAt, endedAt);
        expect(chat.isPreview, isTrue);
      });

      test('defaults when keys absent: maxCycles null, endedAt null, '
          'isPreview false', () {
        final json = ChatFixtures.json();
        // ChatFixtures.json() doesn't include these keys at all.
        expect(json.containsKey('max_cycles'), isFalse);
        expect(json.containsKey('ended_at'), isFalse);
        expect(json.containsKey('is_preview'), isFalse);

        final chat = Chat.fromJson(json);

        expect(chat.maxCycles, isNull);
        expect(chat.endedAt, isNull);
        expect(chat.isPreview, isFalse);
      });

      test('parses ended_at from an ISO string', () {
        final json = ChatFixtures.json();
        json['ended_at'] = '2026-01-15T08:00:00.000Z';

        final chat = Chat.fromJson(json);

        expect(chat.endedAt, DateTime.parse('2026-01-15T08:00:00.000Z'));
      });
    });

    group('toJson', () {
      test('round-trips max_cycles, ended_at (ISO), is_preview', () {
        final endedAt = DateTime.parse('2026-05-29T12:34:56.000Z');
        final chat = ChatFixtures.model().copyWith(
          maxCycles: 1,
          endedAt: endedAt,
          isPreview: true,
        );

        final json = chat.toJson();

        expect(json['max_cycles'], 1);
        expect(json['ended_at'], endedAt.toIso8601String());
        expect(json['is_preview'], isTrue);
      });

      test('serializes ended_at as null when not set', () {
        final chat = ChatFixtures.model();

        final json = chat.toJson();

        expect(json['ended_at'], isNull);
        expect(json['max_cycles'], isNull);
        expect(json['is_preview'], isFalse);
      });
    });

    group('copyWith', () {
      test('updates maxCycles, endedAt, isPreview', () {
        final base = ChatFixtures.model();
        expect(base.maxCycles, isNull);
        expect(base.endedAt, isNull);
        expect(base.isPreview, isFalse);

        final endedAt = DateTime.parse('2026-05-29T12:34:56.000Z');
        final updated = base.copyWith(
          maxCycles: 1,
          endedAt: endedAt,
          isPreview: true,
        );

        expect(updated.maxCycles, 1);
        expect(updated.endedAt, endedAt);
        expect(updated.isPreview, isTrue);
      });
    });

    group('Equatable', () {
      test('two chats differing only in isPreview are unequal', () {
        final base = ChatFixtures.model();
        final preview = base.copyWith(isPreview: true);

        expect(base.isPreview, isFalse);
        expect(preview.isPreview, isTrue);
        expect(base == preview, isFalse);
      });

      test('isPreview is part of props', () {
        final base = ChatFixtures.model();
        expect(base.props.contains(base.isPreview), isTrue);
      });
    });
  });
}
