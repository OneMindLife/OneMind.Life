import 'package:equatable/equatable.dart';
import 'chat.dart';
import 'round.dart';

/// Lightweight wrapper around [Chat] with dashboard-specific fields
/// for the home screen at-a-glance view.
class ChatDashboardInfo extends Equatable {
  final Chat chat;
  final int participantCount;
  final RoundPhase? currentRoundPhase;
  final int? currentRoundNumber;
  final DateTime? phaseEndsAt;
  final DateTime? phaseStartedAt;
  final int? currentCycleId;
  final String? viewingLanguageCode;

  const ChatDashboardInfo({
    required this.chat,
    required this.participantCount,
    this.currentRoundPhase,
    this.currentRoundNumber,
    this.phaseEndsAt,
    this.phaseStartedAt,
    this.currentCycleId,
    this.viewingLanguageCode,
  });

  bool get hasActiveTimer => phaseEndsAt != null && currentRoundPhase != null;

  bool get isPaused => chat.schedulePaused || chat.hostPaused;

  bool get hasActiveRound => currentRoundPhase != null;

  Duration? get timeRemaining {
    if (phaseEndsAt == null) return null;
    final remaining = phaseEndsAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory ChatDashboardInfo.fromJson(Map<String, dynamic> json) {
    return ChatDashboardInfo(
      chat: Chat.fromJson(json),
      participantCount: (json['participant_count'] as num?)?.toInt() ?? 0,
      currentRoundPhase: _parsePhase(json['current_round_phase'] as String?),
      currentRoundNumber: json['current_round_custom_id'] as int?,
      phaseEndsAt: json['current_round_phase_ends_at'] != null
          ? DateTime.parse(json['current_round_phase_ends_at'] as String)
          : null,
      phaseStartedAt: json['current_round_phase_started_at'] != null
          ? DateTime.parse(json['current_round_phase_started_at'] as String)
          : null,
      currentCycleId: (json['current_cycle_id'] as num?)?.toInt(),
      viewingLanguageCode: json['viewing_language_code'] as String?,
    );
  }

  static RoundPhase? _parsePhase(String? phase) {
    switch (phase) {
      case 'proposing':
        return RoundPhase.proposing;
      case 'rating':
        return RoundPhase.rating;
      case 'waiting':
        return RoundPhase.waiting;
      default:
        return null;
    }
  }

  @override
  List<Object?> get props => [
        chat,
        participantCount,
        currentRoundPhase,
        currentRoundNumber,
        phaseEndsAt,
        phaseStartedAt,
        currentCycleId,
        viewingLanguageCode,
      ];
}
