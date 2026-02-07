import 'package:equatable/equatable.dart';

/// Represents a user who has skipped submitting a proposition for a round.
class RoundSkip extends Equatable {
  final int id;
  final int roundId;
  final int participantId;
  final DateTime createdAt;

  const RoundSkip({
    required this.id,
    required this.roundId,
    required this.participantId,
    required this.createdAt,
  });

  factory RoundSkip.fromJson(Map<String, dynamic> json) {
    return RoundSkip(
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
