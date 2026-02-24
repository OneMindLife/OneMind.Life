import 'package:onemind_app/models/models.dart';
import 'chat_fixtures.dart';

/// Test fixtures for ChatDashboardInfo model
class ChatDashboardInfoFixtures {
  /// Dashboard info with no active round (idle)
  static ChatDashboardInfo idle({
    int id = 1,
    String name = 'Idle Chat',
    int participantCount = 3,
  }) {
    return ChatDashboardInfo(
      chat: ChatFixtures.model(id: id, name: name),
      participantCount: participantCount,
    );
  }

  /// Dashboard info in proposing phase with timer
  static ChatDashboardInfo proposingTimed({
    int id = 2,
    String name = 'Proposing Chat',
    int participantCount = 5,
    Duration timerRemaining = const Duration(minutes: 3, seconds: 42),
  }) {
    return ChatDashboardInfo(
      chat: ChatFixtures.model(id: id, name: name),
      participantCount: participantCount,
      currentRoundPhase: RoundPhase.proposing,
      currentRoundNumber: 1,
      phaseEndsAt: DateTime.now().add(timerRemaining),
      phaseStartedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      currentCycleId: 100,
    );
  }

  /// Dashboard info in rating phase with timer
  static ChatDashboardInfo ratingTimed({
    int id = 3,
    String name = 'Rating Chat',
    int participantCount = 4,
    Duration timerRemaining = const Duration(minutes: 10),
  }) {
    return ChatDashboardInfo(
      chat: ChatFixtures.model(id: id, name: name),
      participantCount: participantCount,
      currentRoundPhase: RoundPhase.rating,
      currentRoundNumber: 2,
      phaseEndsAt: DateTime.now().add(timerRemaining),
      phaseStartedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      currentCycleId: 101,
    );
  }

  /// Dashboard info in proposing phase without timer (manual mode)
  static ChatDashboardInfo proposingManual({
    int id = 4,
    String name = 'Manual Proposing Chat',
    int participantCount = 3,
  }) {
    return ChatDashboardInfo(
      chat: ChatFixtures.model(id: id, name: name),
      participantCount: participantCount,
      currentRoundPhase: RoundPhase.proposing,
      currentRoundNumber: 1,
      phaseStartedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      currentCycleId: 102,
    );
  }

  /// Dashboard info for a paused chat
  static ChatDashboardInfo paused({
    int id = 5,
    String name = 'Paused Chat',
    int participantCount = 6,
  }) {
    return ChatDashboardInfo(
      chat: ChatFixtures.model(id: id, name: name, hostPaused: true),
      participantCount: participantCount,
      currentRoundPhase: RoundPhase.proposing,
      currentRoundNumber: 1,
      phaseStartedAt: DateTime.now().subtract(const Duration(hours: 1)),
      currentCycleId: 103,
    );
  }

  /// Dashboard info in waiting phase
  static ChatDashboardInfo waiting({
    int id = 6,
    String name = 'Waiting Chat',
    int participantCount = 2,
  }) {
    return ChatDashboardInfo(
      chat: ChatFixtures.model(id: id, name: name),
      participantCount: participantCount,
      currentRoundPhase: RoundPhase.waiting,
      currentRoundNumber: 1,
      phaseStartedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      currentCycleId: 104,
    );
  }

  /// JSON matching the dashboard RPC response
  static Map<String, dynamic> json({
    int id = 1,
    String name = 'Test Dashboard Chat',
    int participantCount = 3,
    String? currentRoundPhase,
    int? currentRoundCustomId,
    DateTime? currentRoundPhaseEndsAt,
    DateTime? currentRoundPhaseStartedAt,
    int? currentCycleId,
  }) {
    return {
      ...ChatFixtures.json(id: id, name: name),
      'participant_count': participantCount,
      'current_round_phase': currentRoundPhase,
      'current_round_custom_id': currentRoundCustomId,
      'current_round_phase_ends_at':
          currentRoundPhaseEndsAt?.toIso8601String(),
      'current_round_phase_started_at':
          currentRoundPhaseStartedAt?.toIso8601String(),
      'current_cycle_id': currentCycleId,
    };
  }

  /// Wrap a list of Chats into idle dashboard infos
  static List<ChatDashboardInfo> fromChats(List<Chat> chats) {
    return chats
        .map((c) => ChatDashboardInfo(
              chat: c,
              participantCount: 1,
            ))
        .toList();
  }
}
