import 'package:equatable/equatable.dart';

/// Represents a user who has skipped rating for a round.
class RatingSkip extends Equatable {
  final int id;
  final int roundId;
  final int participantId;
  final DateTime createdAt;

  const RatingSkip({
    required this.id,
    required this.roundId,
    required this.participantId,
    required this.createdAt,
  });

  factory RatingSkip.fromJson(Map<String, dynamic> json) {
    return RatingSkip(
      id: json['id'] as int,
      roundId: json['round_id'] as int,
      participantId: json['participant_id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'round_id': roundId,
      'participant_id': participantId,
    };
  }

  @override
  List<Object?> get props => [id, roundId, participantId, createdAt];
}
