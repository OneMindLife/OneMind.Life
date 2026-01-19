import 'package:equatable/equatable.dart';

/// Summary of a public chat for discovery/browsing.
/// This is a lightweight version of Chat with participant count.
/// Supports optional translated fields for internationalization.
class PublicChatSummary extends Equatable {
  final int id;
  final String name;
  final String? description;
  final String initialMessage;
  final int participantCount;
  final DateTime createdAt;
  final DateTime? lastActivityAt;

  /// Translated name (if available in user's language)
  final String? nameTranslated;

  /// Translated description (if available in user's language)
  final String? descriptionTranslated;

  /// Translated initial message (if available in user's language)
  final String? initialMessageTranslated;

  /// The language code of the translation, or 'original' if no translation
  final String? translationLanguage;

  const PublicChatSummary({
    required this.id,
    required this.name,
    this.description,
    required this.initialMessage,
    required this.participantCount,
    required this.createdAt,
    this.lastActivityAt,
    this.nameTranslated,
    this.descriptionTranslated,
    this.initialMessageTranslated,
    this.translationLanguage,
  });

  factory PublicChatSummary.fromJson(Map<String, dynamic> json) {
    return PublicChatSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      initialMessage: json['initial_message'] as String,
      participantCount: (json['participant_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'] as String)
          : null,
      nameTranslated: json['name_translated'] as String?,
      descriptionTranslated: json['description_translated'] as String?,
      initialMessageTranslated: json['initial_message_translated'] as String?,
      translationLanguage: json['translation_language'] as String?,
    );
  }

  /// Returns the translated name if available, otherwise the original name.
  String get displayName => nameTranslated ?? name;

  /// Returns the translated description if available, otherwise the original.
  String? get displayDescription => descriptionTranslated ?? description;

  /// Returns the translated initial message if available, otherwise the original.
  String get displayInitialMessage => initialMessageTranslated ?? initialMessage;

  /// Returns true if this chat has translations available.
  bool get hasTranslation =>
      translationLanguage != null && translationLanguage != 'original';

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        initialMessage,
        participantCount,
        createdAt,
        lastActivityAt,
        nameTranslated,
        descriptionTranslated,
        initialMessageTranslated,
        translationLanguage,
      ];
}
