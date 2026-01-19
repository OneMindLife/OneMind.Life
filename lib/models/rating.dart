import 'package:equatable/equatable.dart';

class Rating extends Equatable {
  final int id;
  final int propositionId;
  final int? participantId;
  final String? sessionToken;
  final int rating; // 0-100
  final DateTime createdAt;

  const Rating({
    required this.id,
    required this.propositionId,
    this.participantId,
    this.sessionToken,
    required this.rating,
    required this.createdAt,
  });

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      id: json['id'] as int,
      propositionId: json['proposition_id'] as int,
      participantId: json['participant_id'] as int?,
      sessionToken: json['session_token'] as String?,
      rating: json['rating'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'proposition_id': propositionId,
      'participant_id': participantId,
      'session_token': sessionToken,
      'rating': rating,
    };
  }

  @override
  List<Object?> get props => [
        id,
        propositionId,
        participantId,
        sessionToken,
        rating,
        createdAt,
      ];
}
