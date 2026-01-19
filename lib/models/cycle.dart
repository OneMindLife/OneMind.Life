import 'package:equatable/equatable.dart';

class Cycle extends Equatable {
  final int id;
  final int chatId;
  final int? winningPropositionId;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Cycle({
    required this.id,
    required this.chatId,
    this.winningPropositionId,
    required this.createdAt,
    this.completedAt,
  });

  bool get isComplete => winningPropositionId != null;

  factory Cycle.fromJson(Map<String, dynamic> json) {
    return Cycle(
      id: json['id'] as int,
      chatId: json['chat_id'] as int,
      winningPropositionId: json['winning_proposition_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        chatId,
        winningPropositionId,
        createdAt,
        completedAt,
      ];
}
