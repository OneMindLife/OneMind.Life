import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/public_chat_summary.dart';

void main() {
  group('PublicChatSummary Translation', () {
    group('fromJson', () {
      test('parses translation fields when present', () {
        final json = {
          'id': 1,
          'name': 'Original Name',
          'description': 'Original Description',
          'initial_message': 'Original Message',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00.000Z',
          'name_translated': 'Nombre Traducido',
          'description_translated': 'Descripcion Traducida',
          'initial_message_translated': 'Mensaje Traducido',
          'translation_language': 'es',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.nameTranslated, 'Nombre Traducido');
        expect(summary.descriptionTranslated, 'Descripcion Traducida');
        expect(summary.initialMessageTranslated, 'Mensaje Traducido');
        expect(summary.translationLanguage, 'es');
      });

      test('handles missing translation fields', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'description': 'Test Description',
          'initial_message': 'Test Message',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00.000Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.nameTranslated, isNull);
        expect(summary.descriptionTranslated, isNull);
        expect(summary.initialMessageTranslated, isNull);
        expect(summary.translationLanguage, isNull);
      });

      test('handles null translation fields in JSON', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'description': 'Test Description',
          'initial_message': 'Test Message',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00.000Z',
          'name_translated': null,
          'description_translated': null,
          'initial_message_translated': null,
          'translation_language': null,
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.nameTranslated, isNull);
        expect(summary.descriptionTranslated, isNull);
        expect(summary.initialMessageTranslated, isNull);
        expect(summary.translationLanguage, isNull);
      });

      test('parses original language when no translation available', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'description': null,
          'initial_message': 'Test Message',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00.000Z',
          'name_translated': 'Test Chat', // Same as original (fallback)
          'description_translated': null,
          'initial_message_translated': 'Test Message',
          'translation_language': 'original',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.translationLanguage, 'original');
      });
    });

    group('display* getters', () {
      test('displayName returns translated name when available', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Original Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          nameTranslated: 'Translated Name',
        );

        expect(summary.displayName, 'Translated Name');
      });

      test('displayName falls back to original name when no translation', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Original Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
        );

        expect(summary.displayName, 'Original Name');
      });

      test('displayDescription returns translated description when available', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          description: 'Original Description',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          descriptionTranslated: 'Translated Description',
        );

        expect(summary.displayDescription, 'Translated Description');
      });

      test('displayDescription falls back to original when no translation', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          description: 'Original Description',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
        );

        expect(summary.displayDescription, 'Original Description');
      });

      test('displayDescription returns null when both are null', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
        );

        expect(summary.displayDescription, isNull);
      });

      test('displayInitialMessage returns translated message when available', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Original Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          initialMessageTranslated: 'Translated Message',
        );

        expect(summary.displayInitialMessage, 'Translated Message');
      });

      test('displayInitialMessage falls back to original when no translation', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Original Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
        );

        expect(summary.displayInitialMessage, 'Original Message');
      });
    });

    group('hasTranslation', () {
      test('returns true when translation language is set', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          translationLanguage: 'es',
        );

        expect(summary.hasTranslation, isTrue);
      });

      test('returns false when translation language is null', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
        );

        expect(summary.hasTranslation, isFalse);
      });

      test('returns false when translation language is "original"', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          translationLanguage: 'original',
        );

        expect(summary.hasTranslation, isFalse);
      });

      test('returns true for English translation', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          translationLanguage: 'en',
        );

        expect(summary.hasTranslation, isTrue);
      });
    });

    group('equality', () {
      test('two summaries with same translation fields are equal', () {
        final summary1 = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          nameTranslated: 'Nombre',
          translationLanguage: 'es',
        );

        final summary2 = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          nameTranslated: 'Nombre',
          translationLanguage: 'es',
        );

        expect(summary1, equals(summary2));
      });

      test('two summaries with different translation fields are not equal', () {
        final summary1 = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          nameTranslated: 'Nombre',
        );

        final summary2 = PublicChatSummary(
          id: 1,
          name: 'Name',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime(2024, 1, 1),
          nameTranslated: 'Different Name',
        );

        expect(summary1, isNot(equals(summary2)));
      });
    });
  });
}
