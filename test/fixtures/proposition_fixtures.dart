import 'package:onemind_app/models/proposition.dart';

/// Test fixtures for Proposition model
class PropositionFixtures {
  /// Valid JSON matching Supabase response
  static Map<String, dynamic> json({
    int id = 1,
    int roundId = 1,
    int? participantId,
    String content = 'Test proposition',
    double? finalRating,
    int? rank,
    DateTime? createdAt,
    int? carriedFromId,
    String? contentTranslated,
    String? languageCode,
  }) {
    return {
      'id': id,
      'round_id': roundId,
      'participant_id': participantId,
      'content': content,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      if (carriedFromId != null) 'carried_from_id': carriedFromId,
      if (contentTranslated != null) 'content_translated': contentTranslated,
      if (languageCode != null) 'language_code': languageCode,
      if (finalRating != null || rank != null)
        'proposition_movda_ratings': {
          'rating': finalRating,
          'rank': rank,
        },
    };
  }

  /// Valid Proposition model instance
  static Proposition model({
    int id = 1,
    int roundId = 1,
    int? participantId,
    String content = 'Test proposition',
    double? finalRating,
    int? rank,
    int? carriedFromId,
  }) {
    return Proposition.fromJson(json(
      id: id,
      roundId: roundId,
      participantId: participantId,
      content: content,
      finalRating: finalRating,
      rank: rank,
      carriedFromId: carriedFromId,
    ));
  }

  /// Carried forward proposition (from previous round's winner)
  static Proposition carriedForward({
    int id = 1,
    int roundId = 2,
    int carriedFromId = 100,
    String content = 'Carried forward proposition',
  }) {
    return Proposition.fromJson(json(
      id: id,
      roundId: roundId,
      content: content,
      carriedFromId: carriedFromId,
    ));
  }

  /// Proposition with translation
  static Proposition translated({
    int id = 1,
    int roundId = 1,
    String content = 'Original content in English',
    String contentTranslated = 'Contenido traducido en español',
    String languageCode = 'es',
    int? participantId,
  }) {
    return Proposition.fromJson(json(
      id: id,
      roundId: roundId,
      content: content,
      contentTranslated: contentTranslated,
      languageCode: languageCode,
      participantId: participantId,
    ));
  }

  /// List of propositions with translations
  static List<Proposition> withTranslations({
    int roundId = 1,
    String languageCode = 'es',
  }) {
    return [
      Proposition.fromJson(json(
        id: 1,
        roundId: roundId,
        content: 'Message 1',
        contentTranslated: 'Mensaje 1',
        languageCode: languageCode,
      )),
      Proposition.fromJson(json(
        id: 2,
        roundId: roundId,
        content: 'Message 2',
        contentTranslated: 'Mensaje 2',
        languageCode: languageCode,
      )),
      Proposition.fromJson(json(
        id: 3,
        roundId: roundId,
        content: 'Message 3',
        contentTranslated: 'Mensaje 3',
        languageCode: languageCode,
      )),
    ];
  }

  /// Proposition with rating
  static Proposition rated({
    int id = 1,
    int roundId = 1,
    String content = 'Rated proposition',
    double rating = 75.0,
    int rank = 1,
  }) {
    return Proposition.fromJson(json(
      id: id,
      roundId: roundId,
      content: content,
      finalRating: rating,
      rank: rank,
    ));
  }

  /// Winning proposition (rank 1)
  static Proposition winner({
    int id = 1,
    int roundId = 1,
    String content = 'Winning idea',
    double rating = 90.0,
  }) {
    return rated(
      id: id,
      roundId: roundId,
      content: content,
      rating: rating,
      rank: 1,
    );
  }

  /// User's own proposition
  static Proposition mine({
    int id = 1,
    int roundId = 1,
    int participantId = 1,
    String content = 'My proposition',
  }) {
    return Proposition.fromJson(json(
      id: id,
      roundId: roundId,
      participantId: participantId,
      content: content,
    ));
  }

  /// List of propositions
  static List<Proposition> list({int count = 3, int roundId = 1}) {
    return List.generate(
      count,
      (i) => model(
        id: i + 1,
        roundId: roundId,
        content: 'Proposition ${i + 1}',
      ),
    );
  }

  /// List of rated propositions (sorted by rank)
  static List<Proposition> withRatings({int roundId = 1}) {
    return [
      Proposition.fromJson(json(
        id: 1,
        roundId: roundId,
        content: 'Best idea - the winner',
        finalRating: 85.5,
        rank: 1,
      )),
      Proposition.fromJson(json(
        id: 2,
        roundId: roundId,
        content: 'Second place idea',
        finalRating: 72.0,
        rank: 2,
      )),
      Proposition.fromJson(json(
        id: 3,
        roundId: roundId,
        content: 'Third place idea',
        finalRating: 58.3,
        rank: 3,
      )),
    ];
  }

  /// Diverse content for testing
  static List<Proposition> diverse({int roundId = 1}) {
    return [
      model(
        id: 1,
        roundId: roundId,
        content: 'Short idea',
      ),
      model(
        id: 2,
        roundId: roundId,
        content:
            'A much longer proposition that contains multiple sentences. '
            'This tests how the UI handles longer content. '
            'It might even wrap to multiple lines.',
      ),
      model(
        id: 3,
        roundId: roundId,
        content: 'Idea with special chars: @#\$%^&*()',
      ),
      model(
        id: 4,
        roundId: roundId,
        content: 'Unicode: 🎉 🚀 ✨ 中文 العربية',
      ),
    ];
  }
}
