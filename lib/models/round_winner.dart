import 'package:equatable/equatable.dart';

/// Represents a winner of a round.
/// Multiple RoundWinner entries for the same round indicate a tie.
class RoundWinner extends Equatable {
  final int id;
  final int roundId;
  final int propositionId;
  final int rank; // 1 = first place (tied winners all have rank 1)
  final double? globalScore; // MOVDA score at time of win
  final DateTime createdAt;

  // Joined data from proposition
  final String? content;

  // Translation fields
  final String? contentTranslated;
  final String? translationLanguage;

  // Audio URL from joined rounds.audio_url (official chats only)
  final String? audioUrl;

  // Video URL from joined rounds.video_url (official chats, manually uploaded)
  final String? videoUrl;

  const RoundWinner({
    required this.id,
    required this.roundId,
    required this.propositionId,
    required this.rank,
    this.globalScore,
    required this.createdAt,
    this.content,
    this.contentTranslated,
    this.translationLanguage,
    this.audioUrl,
    this.videoUrl,
  });

  /// Get the display content (translated if available, otherwise original)
  String? get displayContent => contentTranslated ?? content;

  factory RoundWinner.fromJson(Map<String, dynamic> json) {
    // Handle nested propositions join
    final propositions = json['propositions'];
    String? content;
    if (propositions != null) {
      if (propositions is Map) {
        content = propositions['content'] as String?;
      } else if (propositions is List && propositions.isNotEmpty) {
        content = propositions[0]['content'] as String?;
      }
    }

    // Handle nested rounds join for audio_url and video_url
    String? audioUrl;
    String? videoUrl;
    final rounds = json['rounds'];
    if (rounds != null) {
      Map? roundMap;
      if (rounds is Map) {
        roundMap = rounds;
      } else if (rounds is List && rounds.isNotEmpty && rounds[0] is Map) {
        roundMap = rounds[0] as Map;
      }
      if (roundMap != null) {
        audioUrl = roundMap['audio_url'] as String?;
        videoUrl = roundMap['video_url'] as String?;
      }
    }
    audioUrl ??= json['audio_url'] as String?;
    videoUrl ??= json['video_url'] as String?;

    return RoundWinner(
      id: json['id'] as int,
      roundId: json['round_id'] as int,
      propositionId: json['proposition_id'] as int,
      rank: json['rank'] as int? ?? 1,
      globalScore: (json['global_score'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      content: content,
      contentTranslated: json['content_translated'] as String?,
      translationLanguage: json['translation_language'] as String?,
      audioUrl: audioUrl,
      videoUrl: videoUrl,
    );
  }

  /// Create a copy with translations applied
  RoundWinner copyWith({
    String? contentTranslated,
    String? translationLanguage,
    String? audioUrl,
    String? videoUrl,
  }) {
    return RoundWinner(
      id: id,
      roundId: roundId,
      propositionId: propositionId,
      rank: rank,
      globalScore: globalScore,
      createdAt: createdAt,
      content: content,
      contentTranslated: contentTranslated ?? this.contentTranslated,
      translationLanguage: translationLanguage ?? this.translationLanguage,
      audioUrl: audioUrl ?? this.audioUrl,
      videoUrl: videoUrl ?? this.videoUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'round_id': roundId,
      'proposition_id': propositionId,
      'rank': rank,
      'global_score': globalScore,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        roundId,
        propositionId,
        rank,
        globalScore,
        createdAt,
        content,
        contentTranslated,
        translationLanguage,
        audioUrl,
        videoUrl,
      ];

  @override
  String toString() {
    return 'RoundWinner(id: $id, roundId: $roundId, propositionId: $propositionId, '
        'rank: $rank, score: ${globalScore?.toStringAsFixed(1)})';
  }
}
