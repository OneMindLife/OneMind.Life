import 'package:onemind_app/models/cycle.dart';

/// Test fixtures for Cycle model
class CycleFixtures {
  /// Valid JSON matching Supabase response
  static Map<String, dynamic> json({
    int id = 1,
    int chatId = 1,
    int? winningPropositionId,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return {
      'id': id,
      'chat_id': chatId,
      'winning_proposition_id': winningPropositionId,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  /// Valid Cycle model instance
  static Cycle model({
    int id = 1,
    int chatId = 1,
    int? winningPropositionId,
  }) {
    return Cycle.fromJson(json(
      id: id,
      chatId: chatId,
      winningPropositionId: winningPropositionId,
    ));
  }

  /// Active cycle (no winner yet)
  static Cycle active({int id = 1, int chatId = 1}) {
    return Cycle.fromJson(json(
      id: id,
      chatId: chatId,
    ));
  }

  /// Completed cycle with winner
  static Cycle completed({
    int id = 1,
    int chatId = 1,
    int winningPropositionId = 1,
  }) {
    return Cycle.fromJson(json(
      id: id,
      chatId: chatId,
      winningPropositionId: winningPropositionId,
      completedAt: DateTime.now(),
    ));
  }

  /// List of cycles for a chat
  static List<Cycle> list({int count = 3, int chatId = 1}) {
    return List.generate(count, (i) {
      final isLast = i == count - 1;
      if (isLast) {
        // Last cycle is active
        return active(id: i + 1, chatId: chatId);
      }
      return completed(
        id: i + 1,
        chatId: chatId,
        winningPropositionId: i + 1,
      );
    });
  }

  /// History of completed cycles (for consensus display)
  static List<Cycle> history({int count = 5, int chatId = 1}) {
    return List.generate(
      count,
      (i) => completed(
        id: i + 1,
        chatId: chatId,
        winningPropositionId: (i + 1) * 10, // Different winning props
      ),
    );
  }
}
