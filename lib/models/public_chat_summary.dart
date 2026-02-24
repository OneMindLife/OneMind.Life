import 'package:equatable/equatable.dart';
import 'round.dart';

/// Summary of a public chat for discovery/browsing.
/// This is a lightweight version of Chat with participant count.
/// Supports optional translated fields for internationalization.
/// Includes dashboard data (phase/timer) for at-a-glance status.
class PublicChatSummary extends Equatable {
  final int id;
  final String name;
  final String? description;
  final String? initialMessage;
  final int participantCount;
  final DateTime createdAt;
  final DateTime? lastActivityAt;

  /// Translated name (if available in user's language)
  final String? nameTranslated;

  /// Translated description (if available in user's language)
  final String? descriptionTranslated;

  /// Translated initial message (if available in user's language)
  final String? initialMessageTranslated;

  /// The language code of the translation, or 'original' if no translation
  final String? translationLanguage;

  /// The languages configured for this chat
  final List<String> translationLanguages;

  /// Current round phase: 'proposing', 'rating', 'waiting', or null (idle)
  final String? currentRoundPhase;

  /// Round number within the current cycle
  final int? currentRoundNumber;

  /// Timer target for the current phase (null = no timer / manual mode)
  final DateTime? phaseEndsAt;

  /// When the current phase started
  final DateTime? phaseStartedAt;

  /// Whether the schedule is paused
  final bool schedulePaused;

  /// Whether the host has manually paused
  final bool hostPaused;

  const PublicChatSummary({
    required this.id,
    required this.name,
    this.description,
    this.initialMessage,
    required this.participantCount,
    required this.createdAt,
    this.lastActivityAt,
    this.nameTranslated,
    this.descriptionTranslated,
    this.initialMessageTranslated,
    this.translationLanguage,
    this.translationLanguages = const ['en'],
    this.currentRoundPhase,
    this.currentRoundNumber,
    this.phaseEndsAt,
    this.phaseStartedAt,
    this.schedulePaused = false,
    this.hostPaused = false,
  });

  factory PublicChatSummary.fromJson(Map<String, dynamic> json) {
    return PublicChatSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      initialMessage: json['initial_message'] as String?,
      participantCount: (json['participant_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'] as String)
          : null,
      nameTranslated: json['name_translated'] as String?,
      descriptionTranslated: json['description_translated'] as String?,
      initialMessageTranslated: json['initial_message_translated'] as String?,
      translationLanguage: json['translation_language'] as String?,
      translationLanguages: (json['translation_languages'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['en'],
      currentRoundPhase: json['current_round_phase'] as String?,
      currentRoundNumber: json['current_round_custom_id'] as int?,
      phaseEndsAt: json['current_round_phase_ends_at'] != null
          ? DateTime.parse(json['current_round_phase_ends_at'] as String)
          : null,
      phaseStartedAt: json['current_round_phase_started_at'] != null
          ? DateTime.parse(json['current_round_phase_started_at'] as String)
          : null,
      schedulePaused: json['schedule_paused'] as bool? ?? false,
      hostPaused: json['host_paused'] as bool? ?? false,
    );
  }

  /// Returns the translated name if available, otherwise the original name.
  String get displayName => nameTranslated ?? name;

  /// Returns the translated description if available, otherwise the original.
  String? get displayDescription => descriptionTranslated ?? description;

  /// Returns the translated initial message if available, otherwise the original, or empty.
  String get displayInitialMessage => initialMessageTranslated ?? initialMessage ?? '';

  /// Returns true if this chat has translations available.
  bool get hasTranslation =>
      translationLanguage != null && translationLanguage != 'original';

  /// Whether there's an active timer running.
  bool get hasActiveTimer => phaseEndsAt != null && currentRoundPhase != null;

  /// Whether the chat is paused (schedule or host).
  bool get isPaused => schedulePaused || hostPaused;

  /// Whether there's an active round.
  bool get hasActiveRound => currentRoundPhase != null;

  /// Remaining time until phase ends, or null if no timer.
  Duration? get timeRemaining {
    if (phaseEndsAt == null) return null;
    final remaining = phaseEndsAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Current phase as a [RoundPhase] enum value.
  RoundPhase? get currentPhase => _parsePhase(currentRoundPhase);

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
        id,
        name,
        description,
        initialMessage,
        participantCount,
        createdAt,
        lastActivityAt,
        nameTranslated,
        descriptionTranslated,
        initialMessageTranslated,
        translationLanguage,
        translationLanguages,
        currentRoundPhase,
        currentRoundNumber,
        phaseEndsAt,
        phaseStartedAt,
        schedulePaused,
        hostPaused,
      ];
}
