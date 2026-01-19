import 'package:equatable/equatable.dart';

class Proposition extends Equatable {
  final int id;
  final int roundId;
  final int? participantId;
  final String content;
  final DateTime createdAt;
  final int? carriedFromId;

  // Joined data
  final double? finalRating;
  final int? rank;

  // Translation fields
  final String? contentTranslated;
  final String? translationLanguage;

  const Proposition({
    required this.id,
    required this.roundId,
    this.participantId,
    required this.content,
    required this.createdAt,
    this.carriedFromId,
    this.finalRating,
    this.rank,
    this.contentTranslated,
    this.translationLanguage,
  });

  /// Whether this proposition was carried forward from a previous round
  bool get isCarriedForward => carriedFromId != null;

  /// Get the display content (translated if available, otherwise original)
  String get displayContent => contentTranslated ?? content;

  factory Proposition.fromJson(Map<String, dynamic> json) {
    // Parse global scores from joined proposition_global_scores table (0-100 percentile)
    // Falls back to proposition_movda_ratings for backwards compatibility
    final globalScores = json['proposition_global_scores'];
    final movdaRatings = json['proposition_movda_ratings'];
    double? finalRating;
    int? rank;

    // Prefer global_score (0-100 percentile) over raw MOVDA rating
    if (globalScores != null) {
      if (globalScores is List && globalScores.isNotEmpty) {
        finalRating = (globalScores[0]['global_score'] as num?)?.toDouble();
      } else if (globalScores is Map) {
        finalRating = (globalScores['global_score'] as num?)?.toDouble();
      }
    } else if (movdaRatings != null) {
      // Fallback to MOVDA ratings for backwards compatibility
      if (movdaRatings is List && movdaRatings.isNotEmpty) {
        finalRating = (movdaRatings[0]['rating'] as num?)?.toDouble();
        rank = movdaRatings[0]['rank'] as int?;
      } else if (movdaRatings is Map) {
        finalRating = (movdaRatings['rating'] as num?)?.toDouble();
        rank = movdaRatings['rank'] as int?;
      }
    }

    return Proposition(
      id: json['id'] as int,
      roundId: json['round_id'] as int,
      participantId: json['participant_id'] as int?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      carriedFromId: json['carried_from_id'] as int?,
      finalRating: finalRating,
      rank: rank,
      contentTranslated: json['content_translated'] as String?,
      translationLanguage: json['language_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'round_id': roundId,
      'participant_id': participantId,
      'content': content,
      if (carriedFromId != null) 'carried_from_id': carriedFromId,
    };
  }

  @override
  List<Object?> get props => [
        id,
        roundId,
        participantId,
        content,
        createdAt,
        carriedFromId,
        finalRating,
        rank,
        contentTranslated,
        translationLanguage,
      ];
}
