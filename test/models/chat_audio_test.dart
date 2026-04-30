import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/chat.dart';
import '../fixtures/chat_fixtures.dart';

void main() {
  group('Chat.initialMessageAudioUrl', () {
    test('parses initial_message_audio_url from JSON', () {
      final json = ChatFixtures.json(
        id: 1,
        name: 'OneMind',
        initialMessage: 'What should OneMind become?',
      );
      json['initial_message_audio_url'] = 'https://example.com/initial.mp3';

      final chat = Chat.fromJson(json);
      expect(chat.initialMessageAudioUrl, 'https://example.com/initial.mp3');
    });

    test('initial_message_audio_url is null when not provided', () {
      final json = ChatFixtures.json(
        id: 1,
        name: 'OneMind',
        initialMessage: 'What should OneMind become?',
      );

      final chat = Chat.fromJson(json);
      expect(chat.initialMessageAudioUrl, isNull);
    });

    test('toJson includes initial_message_audio_url', () {
      final json = ChatFixtures.json(
        id: 1,
        name: 'OneMind',
      );
      json['initial_message_audio_url'] = 'https://example.com/i.mp3';

      final chat = Chat.fromJson(json);
      final roundTrip = chat.toJson();
      expect(roundTrip['initial_message_audio_url'], 'https://example.com/i.mp3');
    });

    test('initial_message_audio_url is part of equality', () {
      final json1 = ChatFixtures.json(id: 1, name: 'Test');
      json1['initial_message_audio_url'] = 'a.mp3';
      final json2 = ChatFixtures.json(id: 1, name: 'Test');
      json2['initial_message_audio_url'] = 'b.mp3';

      final chat1 = Chat.fromJson(json1);
      final chat2 = Chat.fromJson(json2);
      expect(chat1, isNot(equals(chat2)));
    });
  });
}
