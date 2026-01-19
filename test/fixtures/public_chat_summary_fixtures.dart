import 'package:onemind_app/models/public_chat_summary.dart';

/// Test fixtures for PublicChatSummary.
class PublicChatSummaryFixtures {
  /// Creates a basic PublicChatSummary JSON.
  static Map<String, dynamic> json({
    int id = 1,
    String name = 'Test Public Chat',
    String? description = 'A test public chat',
    String initialMessage = 'What should we discuss?',
    int participantCount = 5,
    DateTime? createdAt,
    DateTime? lastActivityAt,
    String? nameTranslated,
    String? descriptionTranslated,
    String? initialMessageTranslated,
    String? translationLanguage,
  }) {
    return {
      'id': id,
      'name': name,
      'description': description,
      'initial_message': initialMessage,
      'participant_count': participantCount,
      'created_at': (createdAt ?? DateTime.utc(2024, 1, 1)).toIso8601String(),
      'last_activity_at': lastActivityAt?.toIso8601String(),
      if (nameTranslated != null) 'name_translated': nameTranslated,
      if (descriptionTranslated != null) 'description_translated': descriptionTranslated,
      if (initialMessageTranslated != null) 'initial_message_translated': initialMessageTranslated,
      if (translationLanguage != null) 'translation_language': translationLanguage,
    };
  }

  /// Creates a basic PublicChatSummary model.
  static PublicChatSummary model({
    int id = 1,
    String name = 'Test Public Chat',
    String? description = 'A test public chat',
    String initialMessage = 'What should we discuss?',
    int participantCount = 5,
    DateTime? createdAt,
    DateTime? lastActivityAt,
    String? nameTranslated,
    String? descriptionTranslated,
    String? initialMessageTranslated,
    String? translationLanguage,
  }) {
    return PublicChatSummary(
      id: id,
      name: name,
      description: description,
      initialMessage: initialMessage,
      participantCount: participantCount,
      createdAt: createdAt ?? DateTime.utc(2024, 1, 1),
      lastActivityAt: lastActivityAt,
      nameTranslated: nameTranslated,
      descriptionTranslated: descriptionTranslated,
      initialMessageTranslated: initialMessageTranslated,
      translationLanguage: translationLanguage,
    );
  }

  /// Creates a list of PublicChatSummary models.
  static List<PublicChatSummary> list({int count = 3}) {
    return List.generate(
      count,
      (i) => model(
        id: i + 1,
        name: 'Public Chat ${i + 1}',
        description: 'Description for chat ${i + 1}',
        participantCount: (i + 1) * 2,
      ),
    );
  }

  /// Creates a PublicChatSummary with high participant count.
  static PublicChatSummary popular() {
    return model(
      id: 99,
      name: 'Popular Chat',
      description: 'A very active public chat',
      participantCount: 100,
      lastActivityAt: DateTime.now(),
    );
  }

  /// Creates a PublicChatSummary with no description.
  static PublicChatSummary noDescription() {
    return model(
      id: 50,
      name: 'Simple Chat',
      description: null,
      participantCount: 3,
    );
  }

  /// Creates a PublicChatSummary with Spanish translations.
  static PublicChatSummary withSpanishTranslation({
    int id = 1,
    String name = 'Test Chat',
    String? description = 'Test Description',
    String initialMessage = 'What should we discuss?',
  }) {
    return model(
      id: id,
      name: name,
      description: description,
      initialMessage: initialMessage,
      participantCount: 5,
      nameTranslated: 'Chat de Prueba',
      descriptionTranslated: description != null ? 'Descripcion de Prueba' : null,
      initialMessageTranslated: 'Que deberiamos discutir?',
      translationLanguage: 'es',
    );
  }

  /// Creates a PublicChatSummary with custom translations.
  static PublicChatSummary withTranslation({
    int id = 1,
    String name = 'Original Name',
    String? description = 'Original Description',
    String initialMessage = 'Original Message',
    required String nameTranslated,
    String? descriptionTranslated,
    required String initialMessageTranslated,
    required String translationLanguage,
  }) {
    return model(
      id: id,
      name: name,
      description: description,
      initialMessage: initialMessage,
      participantCount: 5,
      nameTranslated: nameTranslated,
      descriptionTranslated: descriptionTranslated,
      initialMessageTranslated: initialMessageTranslated,
      translationLanguage: translationLanguage,
    );
  }

  /// Creates a PublicChatSummary JSON with Spanish translations.
  static Map<String, dynamic> jsonWithSpanishTranslation({
    int id = 1,
    String name = 'Test Chat',
    String? description = 'Test Description',
    String initialMessage = 'What should we discuss?',
  }) {
    return json(
      id: id,
      name: name,
      description: description,
      initialMessage: initialMessage,
      participantCount: 5,
      nameTranslated: 'Chat de Prueba',
      descriptionTranslated: description != null ? 'Descripcion de Prueba' : null,
      initialMessageTranslated: 'Que deberiamos discutir?',
      translationLanguage: 'es',
    );
  }
}
