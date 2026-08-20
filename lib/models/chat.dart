import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../core/errors/app_exception.dart';

enum AccessMethod { public, code, inviteOnly, personalCode }

/// Facilitation mode: how proposing starts (independent of schedule).
/// - manual: Host clicks a button to start proposing
/// - auto: Starts automatically when participant threshold is reached
enum StartMode { manual, auto }

enum ScheduleType { once, recurring }

/// Represents a single schedule window for recurring schedules.
/// Each window has explicit start_day/time and end_day/time to support:
/// - Same-day windows (e.g., Monday 9am-5pm)
/// - Midnight-spanning windows (e.g., Thursday 11pm to Friday 1am)
/// - Multi-day windows (e.g., Saturday 10am to Sunday 6pm)
class ScheduleWindow extends Equatable {
  final String startDay; // e.g., 'monday'
  final String startTime; // e.g., '09:00'
  final String endDay; // e.g., 'monday'
  final String endTime; // e.g., '17:00'

  const ScheduleWindow({
    required this.startDay,
    required this.startTime,
    required this.endDay,
    required this.endTime,
  });

  factory ScheduleWindow.fromJson(Map<String, dynamic> json) {
    return ScheduleWindow(
      startDay: json['start_day'] as String,
      startTime: json['start_time'] as String,
      endDay: json['end_day'] as String,
      endTime: json['end_time'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start_day': startDay,
      'start_time': startTime,
      'end_day': endDay,
      'end_time': endTime,
    };
  }

  /// Returns the start time as TimeOfDay
  TimeOfDay get startTimeOfDay {
    final parts = startTime.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  /// Returns the end time as TimeOfDay
  TimeOfDay get endTimeOfDay {
    final parts = endTime.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  /// Creates a ScheduleWindow from TimeOfDay values
  factory ScheduleWindow.fromTimeOfDay({
    required String startDay,
    required TimeOfDay startTime,
    required String endDay,
    required TimeOfDay endTime,
  }) {
    String formatTime(TimeOfDay time) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    return ScheduleWindow(
      startDay: startDay,
      startTime: formatTime(startTime),
      endDay: endDay,
      endTime: formatTime(endTime),
    );
  }

  @override
  List<Object?> get props => [startDay, startTime, endDay, endTime];
}

class Chat extends Equatable {
  final int id;
  final String name;
  final String? initialMessage;
  final String? initialMessageAudioUrl;
  final String? initialMessageVideoUrl;
  final String? backgroundAudioUrl;
  final String? description;
  final String? inviteCode;
  final AccessMethod accessMethod;
  final bool requireAuth;
  final bool requireApproval;
  final String? creatorId;
  final String? creatorSessionToken;
  final String? hostDisplayName;
  final bool isActive;
  final bool isOfficial;
  final DateTime? expiresAt;
  final DateTime? lastActivityAt;
  final StartMode startMode;
  final StartMode ratingStartMode; // Controls how rating phase starts after proposing
  final int? autoStartParticipantCount;
  final int proposingDurationSeconds;
  final int ratingDurationSeconds;
  final int proposingMinimum;
  final int ratingMinimum;
  final int? proposingThresholdPercent;
  final int? proposingThresholdCount;
  final int? ratingThresholdPercent;
  final int? ratingThresholdCount;
  final bool enableAiParticipant;
  final int? aiPropositionsCount;
  final int confirmationRoundsRequired;
  final bool showPreviousResults;
  final int propositionsPerUser;
  /// Rating UX: 'grid' (0-100 placement, default) or 'matches' (pairwise).
  final String ratingMode;
  /// When ratingMode == 'matches': 'winner_only' (bracket) or 'full_rank' (Swiss).
  final String matchObjective;

  /// Cap on completed cycles. null = continuous (run forever); 1 = stop after first
  /// result (quick-create flow). See chats.max_cycles.
  final int? maxCycles;

  /// When set, the chat is finished — no further rounds/cycles. See chats.ended_at.
  final DateTime? endedAt;

  /// True for the ephemeral solo preview chat in the quick-create flow (share UI hidden).
  final bool isPreview;

  /// C15 tree mode: every proposition can root its own follow-up subround.
  final bool branchingEnabled;

  /// Whether AI agent participants are enabled (they propose/rate). Used by the
  /// quick-create "get ideas from the group" path to detect a group (agented) chat.
  final bool enableAgents;
  final DateTime createdAt;

  // Adaptive duration settings (uses early advance thresholds)
  final bool adaptiveDurationEnabled;
  final int adaptiveAdjustmentPercent;
  final int minPhaseDurationSeconds;
  final int maxPhaseDurationSeconds;

  /// Cadence anchor: the user-chosen end of the chat's FIRST phase. The
  /// backend derives the repeating wall-clock grid from its time-of-day in
  /// [scheduleTimezone]. null = no cadence (plain duration chaining).
  final DateTime? cadenceAnchorAt;

  // Schedule settings (independent of startMode - controls when chat room is open)
  final ScheduleType? scheduleType;
  final String scheduleTimezone;
  final DateTime? scheduledStartAt; // For one-time schedule
  final DateTime? scheduledEndAt; // For one-time schedule (optional end)
  final List<ScheduleWindow> scheduleWindows; // For recurring schedules
  final bool visibleOutsideSchedule;
  final bool schedulePaused;
  final bool hostPaused;

  // Per-chat skip settings
  final bool allowSkipProposing;
  final bool allowSkipRating;

  // Per-chat translation settings (set at creation, not editable after)
  final bool translationsEnabled;
  final List<String> translationLanguages;

  // Translation fields (populated when fetching with language code)
  final String? nameTranslated;
  final String? descriptionTranslated;
  final String? initialMessageTranslated;
  final String? translationLanguage;

  const Chat({
    required this.id,
    required this.name,
    this.initialMessage,
    this.initialMessageAudioUrl,
    this.initialMessageVideoUrl,
    this.backgroundAudioUrl,
    this.description,
    this.inviteCode,
    required this.accessMethod,
    required this.requireAuth,
    required this.requireApproval,
    this.creatorId,
    this.creatorSessionToken,
    this.hostDisplayName,
    required this.isActive,
    required this.isOfficial,
    this.expiresAt,
    this.lastActivityAt,
    required this.startMode,
    this.ratingStartMode = StartMode.auto,
    this.autoStartParticipantCount,
    required this.proposingDurationSeconds,
    required this.ratingDurationSeconds,
    required this.proposingMinimum,
    required this.ratingMinimum,
    this.proposingThresholdPercent,
    this.proposingThresholdCount,
    this.ratingThresholdPercent,
    this.ratingThresholdCount,
    required this.enableAiParticipant,
    this.aiPropositionsCount,
    required this.confirmationRoundsRequired,
    required this.showPreviousResults,
    required this.propositionsPerUser,
    this.ratingMode = 'grid',
    this.matchObjective = 'winner_only',
    this.maxCycles,
    this.endedAt,
    this.isPreview = false,
    this.branchingEnabled = false,
    this.enableAgents = false,
    required this.createdAt,
    this.adaptiveDurationEnabled = false,
    this.adaptiveAdjustmentPercent = 10,
    this.minPhaseDurationSeconds = 60,
    this.maxPhaseDurationSeconds = 86400,
    this.cadenceAnchorAt,
    this.scheduleType,
    this.scheduleTimezone = 'UTC',
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.scheduleWindows = const [],
    this.visibleOutsideSchedule = true,
    this.schedulePaused = false,
    this.hostPaused = false,
    this.allowSkipProposing = true,
    this.allowSkipRating = true,
    this.translationsEnabled = false,
    this.translationLanguages = const ['en', 'es', 'pt', 'fr', 'de'],
    this.nameTranslated,
    this.descriptionTranslated,
    this.initialMessageTranslated,
    this.translationLanguage,
  });

  /// Returns a copy with the given fields replaced.
  ///
  /// Used by the chat-detail notifier to merge a Realtime UPDATE payload
  /// into the current Chat without re-fetching from the database — this
  /// avoids 18-query bootstrap work when only operational fields like
  /// `host_paused` or `last_activity_at` changed. Translation fields are
  /// passed through unchanged so language settings survive a merge.
  ///
  /// Nullable fields use a `Function?` wrapper so callers can distinguish
  /// "leave it alone" (omit the param) from "explicitly clear it" (pass
  /// `() => null`). For example: `copyWith(scheduledEndAt: () => null)`
  /// nulls the field, while `copyWith()` keeps it.
  Chat copyWith({
    int? id,
    String? name,
    String? Function()? initialMessage,
    String? Function()? initialMessageAudioUrl,
    String? Function()? initialMessageVideoUrl,
    String? Function()? backgroundAudioUrl,
    String? Function()? description,
    String? Function()? inviteCode,
    AccessMethod? accessMethod,
    bool? requireAuth,
    bool? requireApproval,
    String? Function()? creatorId,
    String? Function()? creatorSessionToken,
    String? Function()? hostDisplayName,
    bool? isActive,
    bool? isOfficial,
    DateTime? Function()? expiresAt,
    DateTime? Function()? lastActivityAt,
    StartMode? startMode,
    StartMode? ratingStartMode,
    int? Function()? autoStartParticipantCount,
    int? proposingDurationSeconds,
    int? ratingDurationSeconds,
    int? proposingMinimum,
    int? ratingMinimum,
    int? Function()? proposingThresholdPercent,
    int? Function()? proposingThresholdCount,
    int? Function()? ratingThresholdPercent,
    int? Function()? ratingThresholdCount,
    bool? enableAiParticipant,
    int? Function()? aiPropositionsCount,
    int? confirmationRoundsRequired,
    bool? showPreviousResults,
    int? propositionsPerUser,
    String? ratingMode,
    String? matchObjective,
    int? maxCycles,
    DateTime? endedAt,
    bool? isPreview,
    bool? branchingEnabled,
    bool? enableAgents,
    DateTime? createdAt,
    bool? adaptiveDurationEnabled,
    int? adaptiveAdjustmentPercent,
    int? minPhaseDurationSeconds,
    int? maxPhaseDurationSeconds,
    DateTime? Function()? cadenceAnchorAt,
    ScheduleType? Function()? scheduleType,
    String? scheduleTimezone,
    DateTime? Function()? scheduledStartAt,
    DateTime? Function()? scheduledEndAt,
    List<ScheduleWindow>? scheduleWindows,
    bool? visibleOutsideSchedule,
    bool? schedulePaused,
    bool? hostPaused,
    bool? allowSkipProposing,
    bool? allowSkipRating,
    bool? translationsEnabled,
    List<String>? translationLanguages,
    String? Function()? nameTranslated,
    String? Function()? descriptionTranslated,
    String? Function()? initialMessageTranslated,
    String? Function()? translationLanguage,
  }) {
    return Chat(
      id: id ?? this.id,
      name: name ?? this.name,
      initialMessage:
          initialMessage != null ? initialMessage() : this.initialMessage,
      initialMessageAudioUrl: initialMessageAudioUrl != null
          ? initialMessageAudioUrl()
          : this.initialMessageAudioUrl,
      initialMessageVideoUrl: initialMessageVideoUrl != null
          ? initialMessageVideoUrl()
          : this.initialMessageVideoUrl,
      backgroundAudioUrl: backgroundAudioUrl != null
          ? backgroundAudioUrl()
          : this.backgroundAudioUrl,
      description: description != null ? description() : this.description,
      inviteCode: inviteCode != null ? inviteCode() : this.inviteCode,
      accessMethod: accessMethod ?? this.accessMethod,
      requireAuth: requireAuth ?? this.requireAuth,
      requireApproval: requireApproval ?? this.requireApproval,
      creatorId: creatorId != null ? creatorId() : this.creatorId,
      creatorSessionToken: creatorSessionToken != null
          ? creatorSessionToken()
          : this.creatorSessionToken,
      hostDisplayName:
          hostDisplayName != null ? hostDisplayName() : this.hostDisplayName,
      isActive: isActive ?? this.isActive,
      isOfficial: isOfficial ?? this.isOfficial,
      expiresAt: expiresAt != null ? expiresAt() : this.expiresAt,
      lastActivityAt:
          lastActivityAt != null ? lastActivityAt() : this.lastActivityAt,
      startMode: startMode ?? this.startMode,
      ratingStartMode: ratingStartMode ?? this.ratingStartMode,
      autoStartParticipantCount: autoStartParticipantCount != null
          ? autoStartParticipantCount()
          : this.autoStartParticipantCount,
      proposingDurationSeconds:
          proposingDurationSeconds ?? this.proposingDurationSeconds,
      ratingDurationSeconds:
          ratingDurationSeconds ?? this.ratingDurationSeconds,
      proposingMinimum: proposingMinimum ?? this.proposingMinimum,
      ratingMinimum: ratingMinimum ?? this.ratingMinimum,
      proposingThresholdPercent: proposingThresholdPercent != null
          ? proposingThresholdPercent()
          : this.proposingThresholdPercent,
      proposingThresholdCount: proposingThresholdCount != null
          ? proposingThresholdCount()
          : this.proposingThresholdCount,
      ratingThresholdPercent: ratingThresholdPercent != null
          ? ratingThresholdPercent()
          : this.ratingThresholdPercent,
      ratingThresholdCount: ratingThresholdCount != null
          ? ratingThresholdCount()
          : this.ratingThresholdCount,
      enableAiParticipant: enableAiParticipant ?? this.enableAiParticipant,
      aiPropositionsCount: aiPropositionsCount != null
          ? aiPropositionsCount()
          : this.aiPropositionsCount,
      confirmationRoundsRequired:
          confirmationRoundsRequired ?? this.confirmationRoundsRequired,
      showPreviousResults: showPreviousResults ?? this.showPreviousResults,
      propositionsPerUser: propositionsPerUser ?? this.propositionsPerUser,
      ratingMode: ratingMode ?? this.ratingMode,
      matchObjective: matchObjective ?? this.matchObjective,
      maxCycles: maxCycles ?? this.maxCycles,
      endedAt: endedAt ?? this.endedAt,
      isPreview: isPreview ?? this.isPreview,
      branchingEnabled: branchingEnabled ?? this.branchingEnabled,
      enableAgents: enableAgents ?? this.enableAgents,
      createdAt: createdAt ?? this.createdAt,
      adaptiveDurationEnabled:
          adaptiveDurationEnabled ?? this.adaptiveDurationEnabled,
      adaptiveAdjustmentPercent:
          adaptiveAdjustmentPercent ?? this.adaptiveAdjustmentPercent,
      minPhaseDurationSeconds:
          minPhaseDurationSeconds ?? this.minPhaseDurationSeconds,
      maxPhaseDurationSeconds:
          maxPhaseDurationSeconds ?? this.maxPhaseDurationSeconds,
      cadenceAnchorAt:
          cadenceAnchorAt != null ? cadenceAnchorAt() : this.cadenceAnchorAt,
      scheduleType: scheduleType != null ? scheduleType() : this.scheduleType,
      scheduleTimezone: scheduleTimezone ?? this.scheduleTimezone,
      scheduledStartAt:
          scheduledStartAt != null ? scheduledStartAt() : this.scheduledStartAt,
      scheduledEndAt:
          scheduledEndAt != null ? scheduledEndAt() : this.scheduledEndAt,
      scheduleWindows: scheduleWindows ?? this.scheduleWindows,
      visibleOutsideSchedule:
          visibleOutsideSchedule ?? this.visibleOutsideSchedule,
      schedulePaused: schedulePaused ?? this.schedulePaused,
      hostPaused: hostPaused ?? this.hostPaused,
      allowSkipProposing: allowSkipProposing ?? this.allowSkipProposing,
      allowSkipRating: allowSkipRating ?? this.allowSkipRating,
      translationsEnabled: translationsEnabled ?? this.translationsEnabled,
      translationLanguages: translationLanguages ?? this.translationLanguages,
      nameTranslated:
          nameTranslated != null ? nameTranslated() : this.nameTranslated,
      descriptionTranslated: descriptionTranslated != null
          ? descriptionTranslated()
          : this.descriptionTranslated,
      initialMessageTranslated: initialMessageTranslated != null
          ? initialMessageTranslated()
          : this.initialMessageTranslated,
      translationLanguage: translationLanguage != null
          ? translationLanguage()
          : this.translationLanguage,
    );
  }

  /// Merges a Realtime payload (`payload.newRecord`) into this Chat,
  /// preserving translation fields. Realtime payloads come from the
  /// `chats` table — not the `get_chat_translated` RPC — so the
  /// translated_* columns are never present and must be retained
  /// from the prior state. Falls back to a fresh `fromJson` if any
  /// non-nullable column is missing from the payload (defensive: a
  /// stripped Realtime publication would otherwise crash).
  Chat mergeRealtimePayload(Map<String, dynamic> newRecord) {
    final merged = <String, dynamic>{
      ...toRealtimeMap(),
      ...newRecord,
      'name_translated': nameTranslated,
      'description_translated': descriptionTranslated,
      'initial_message_translated': initialMessageTranslated,
      'translation_language': translationLanguage,
    };
    return Chat.fromJson(merged);
  }

  /// Snapshot of all DB-backed columns, used as the base for merging a
  /// Realtime payload (which only contains the changed columns under
  /// PostgresChangeEvent.update). Translation fields aren't stored on
  /// the chats table so they're omitted here — `mergeRealtimePayload`
  /// re-injects them from the existing Chat after merge.
  Map<String, dynamic> toRealtimeMap() {
    return {
      'id': id,
      'name': name,
      'initial_message': initialMessage,
      'initial_message_audio_url': initialMessageAudioUrl,
      'initial_message_video_url': initialMessageVideoUrl,
      'background_audio_url': backgroundAudioUrl,
      'description': description,
      'invite_code': inviteCode,
      'access_method': _accessMethodToJson(accessMethod),
      'require_auth': requireAuth,
      'require_approval': requireApproval,
      'creator_id': creatorId,
      'creator_session_token': creatorSessionToken,
      'host_display_name': hostDisplayName,
      'is_active': isActive,
      'is_official': isOfficial,
      'expires_at': expiresAt?.toIso8601String(),
      'last_activity_at': lastActivityAt?.toIso8601String(),
      'start_mode': _startModeToJson(startMode),
      'rating_start_mode': _startModeToJson(ratingStartMode),
      'auto_start_participant_count': autoStartParticipantCount,
      'proposing_duration_seconds': proposingDurationSeconds,
      'rating_duration_seconds': ratingDurationSeconds,
      'proposing_minimum': proposingMinimum,
      'rating_minimum': ratingMinimum,
      'proposing_threshold_percent': proposingThresholdPercent,
      'proposing_threshold_count': proposingThresholdCount,
      'rating_threshold_percent': ratingThresholdPercent,
      'rating_threshold_count': ratingThresholdCount,
      'enable_ai_participant': enableAiParticipant,
      'ai_propositions_count': aiPropositionsCount,
      'confirmation_rounds_required': confirmationRoundsRequired,
      'show_previous_results': showPreviousResults,
      'propositions_per_user': propositionsPerUser,
      'rating_mode': ratingMode,
      'match_objective': matchObjective,
      'max_cycles': maxCycles,
      'ended_at': endedAt?.toIso8601String(),
      'is_preview': isPreview,
      'branching_enabled': branchingEnabled,
      'enable_agents': enableAgents,
      'created_at': createdAt.toIso8601String(),
      'adaptive_duration_enabled': adaptiveDurationEnabled,
      'adaptive_adjustment_percent': adaptiveAdjustmentPercent,
      'min_phase_duration_seconds': minPhaseDurationSeconds,
      'max_phase_duration_seconds': maxPhaseDurationSeconds,
      'cadence_anchor_at': cadenceAnchorAt?.toIso8601String(),
      'schedule_type': _scheduleTypeToJson(scheduleType),
      'schedule_timezone': scheduleTimezone,
      'scheduled_start_at': scheduledStartAt?.toIso8601String(),
      'scheduled_end_at': scheduledEndAt?.toIso8601String(),
      'schedule_windows':
          scheduleWindows.map((w) => w.toJson()).toList(growable: false),
      'visible_outside_schedule': visibleOutsideSchedule,
      'schedule_paused': schedulePaused,
      'host_paused': hostPaused,
      'allow_skip_proposing': allowSkipProposing,
      'allow_skip_rating': allowSkipRating,
      'translations_enabled': translationsEnabled,
      'translation_languages': translationLanguages,
    };
  }

  static String _accessMethodToJson(AccessMethod m) {
    switch (m) {
      case AccessMethod.public:
        return 'public';
      case AccessMethod.code:
        return 'code';
      case AccessMethod.inviteOnly:
        return 'invite_only';
      case AccessMethod.personalCode:
        return 'personal_code';
    }
  }

  static String _startModeToJson(StartMode m) {
    switch (m) {
      case StartMode.auto:
        return 'auto';
      case StartMode.manual:
        return 'manual';
    }
  }

  static String? _scheduleTypeToJson(ScheduleType? t) {
    switch (t) {
      case ScheduleType.once:
        return 'once';
      case ScheduleType.recurring:
        return 'recurring';
      case null:
        return null;
    }
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as int,
      name: json['name'] as String,
      initialMessage: json['initial_message'] as String?,
      initialMessageAudioUrl: json['initial_message_audio_url'] as String?,
      initialMessageVideoUrl: json['initial_message_video_url'] as String?,
      backgroundAudioUrl: json['background_audio_url'] as String?,
      description: json['description'] as String?,
      inviteCode: json['invite_code'] as String?,
      accessMethod: _parseAccessMethod(json['access_method'] as String?),
      requireAuth: json['require_auth'] as bool? ?? false,
      requireApproval: json['require_approval'] as bool? ?? false,
      creatorId: json['creator_id'] as String?,
      creatorSessionToken: json['creator_session_token'] as String?,
      hostDisplayName: json['host_display_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isOfficial: json['is_official'] as bool? ?? false,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'] as String)
          : null,
      startMode: _parseStartMode(json['start_mode'] as String?),
      ratingStartMode: _parseStartMode(json['rating_start_mode'] as String?, defaultMode: StartMode.auto),
      autoStartParticipantCount: json['auto_start_participant_count'] as int?,
      proposingDurationSeconds:
          json['proposing_duration_seconds'] as int? ?? 86400,
      ratingDurationSeconds: json['rating_duration_seconds'] as int? ?? 86400,
      proposingMinimum: json['proposing_minimum'] as int? ?? 2,
      ratingMinimum: json['rating_minimum'] as int? ?? 2,
      proposingThresholdPercent: json['proposing_threshold_percent'] as int?,
      proposingThresholdCount: json['proposing_threshold_count'] as int?,
      ratingThresholdPercent: json['rating_threshold_percent'] as int?,
      ratingThresholdCount: json['rating_threshold_count'] as int?,
      enableAiParticipant: json['enable_ai_participant'] as bool? ?? false,
      aiPropositionsCount: json['ai_propositions_count'] as int?,
      confirmationRoundsRequired: json['confirmation_rounds_required'] as int? ?? 2,
      showPreviousResults: json['show_previous_results'] as bool? ?? false,
      propositionsPerUser: json['propositions_per_user'] as int? ?? 1,
      ratingMode: json['rating_mode'] as String? ?? 'grid',
      matchObjective: json['match_objective'] as String? ?? 'winner_only',
      maxCycles: json['max_cycles'] as int?,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      isPreview: json['is_preview'] as bool? ?? false,
      branchingEnabled: json['branching_enabled'] as bool? ?? false,
      enableAgents: json['enable_agents'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      adaptiveDurationEnabled: json['adaptive_duration_enabled'] as bool? ?? false,
      adaptiveAdjustmentPercent: json['adaptive_adjustment_percent'] as int? ?? 10,
      minPhaseDurationSeconds: json['min_phase_duration_seconds'] as int? ?? 60,
      maxPhaseDurationSeconds: json['max_phase_duration_seconds'] as int? ?? 86400,
      // Tolerates absent or null (older RPC shapes without the column).
      cadenceAnchorAt: json['cadence_anchor_at'] != null
          ? DateTime.parse(json['cadence_anchor_at'] as String)
          : null,
      scheduleType: _parseScheduleType(json['schedule_type'] as String?),
      scheduleTimezone: json['schedule_timezone'] as String? ?? 'UTC',
      scheduledStartAt: json['scheduled_start_at'] != null
          ? DateTime.parse(json['scheduled_start_at'] as String)
          : null,
      scheduledEndAt: json['scheduled_end_at'] != null
          ? DateTime.parse(json['scheduled_end_at'] as String)
          : null,
      scheduleWindows: (json['schedule_windows'] as List<dynamic>?)
              ?.map((e) => ScheduleWindow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      visibleOutsideSchedule: json['visible_outside_schedule'] as bool? ?? true,
      schedulePaused: json['schedule_paused'] as bool? ?? false,
      hostPaused: json['host_paused'] as bool? ?? false,
      allowSkipProposing: json['allow_skip_proposing'] as bool? ?? true,
      allowSkipRating: json['allow_skip_rating'] as bool? ?? true,
      translationsEnabled: json['translations_enabled'] as bool? ?? false,
      translationLanguages: (json['translation_languages'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['en', 'es', 'pt', 'fr', 'de'],
      nameTranslated: json['name_translated'] as String?,
      descriptionTranslated: json['description_translated'] as String?,
      initialMessageTranslated: json['initial_message_translated'] as String?,
      translationLanguage: json['translation_language'] as String?,
    );
  }

  static AccessMethod _parseAccessMethod(String? method) {
    switch (method) {
      case 'public':
        return AccessMethod.public;
      case 'code':
        return AccessMethod.code;
      case 'invite_only':
        return AccessMethod.inviteOnly;
      case 'personal_code':
        return AccessMethod.personalCode;
      case null:
        return AccessMethod.public; // Default for null
      default:
        throw AppException.validation(
          message: 'Unknown access method: $method',
          field: 'access_method',
        );
    }
  }

  static StartMode _parseStartMode(String? mode, {StartMode defaultMode = StartMode.manual}) {
    switch (mode) {
      case 'auto':
        return StartMode.auto;
      case 'scheduled':
        // Backwards compatibility: 'scheduled' was removed as a start_mode value.
        // Schedule is now independent of facilitation mode.
        return StartMode.manual;
      case 'manual':
        return StartMode.manual;
      case null:
        return defaultMode; // Use provided default for null
      default:
        throw AppException.validation(
          message: 'Unknown start mode: $mode',
          field: 'start_mode',
        );
    }
  }

  static ScheduleType? _parseScheduleType(String? type) {
    switch (type) {
      case 'once':
        return ScheduleType.once;
      case 'recurring':
        return ScheduleType.recurring;
      case null:
        return null; // Null is valid
      default:
        throw AppException.validation(
          message: 'Unknown schedule type: $type',
          field: 'schedule_type',
        );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'initial_message': initialMessage,
      'initial_message_audio_url': initialMessageAudioUrl,
      'initial_message_video_url': initialMessageVideoUrl,
      'background_audio_url': backgroundAudioUrl,
      'description': description,
      'access_method': _accessMethodToString(accessMethod),
      'require_auth': requireAuth,
      'require_approval': requireApproval,
      'creator_id': creatorId,
      'creator_session_token': creatorSessionToken,
      'host_display_name': hostDisplayName,
      'start_mode': _startModeToString(startMode),
      'rating_start_mode': _startModeToString(ratingStartMode),
      'auto_start_participant_count': autoStartParticipantCount,
      'proposing_duration_seconds': proposingDurationSeconds,
      'rating_duration_seconds': ratingDurationSeconds,
      'proposing_minimum': proposingMinimum,
      'rating_minimum': ratingMinimum,
      'proposing_threshold_percent': proposingThresholdPercent,
      'proposing_threshold_count': proposingThresholdCount,
      'rating_threshold_percent': ratingThresholdPercent,
      'rating_threshold_count': ratingThresholdCount,
      'enable_ai_participant': enableAiParticipant,
      'ai_propositions_count': aiPropositionsCount,
      'confirmation_rounds_required': confirmationRoundsRequired,
      'show_previous_results': showPreviousResults,
      'propositions_per_user': propositionsPerUser,
      'rating_mode': ratingMode,
      'match_objective': matchObjective,
      'max_cycles': maxCycles,
      'ended_at': endedAt?.toIso8601String(),
      'is_preview': isPreview,
      'branching_enabled': branchingEnabled,
      'enable_agents': enableAgents,
      'adaptive_duration_enabled': adaptiveDurationEnabled,
      'adaptive_adjustment_percent': adaptiveAdjustmentPercent,
      'min_phase_duration_seconds': minPhaseDurationSeconds,
      'max_phase_duration_seconds': maxPhaseDurationSeconds,
      'cadence_anchor_at': cadenceAnchorAt?.toIso8601String(),
      'schedule_type': scheduleType?.name,
      'schedule_timezone': scheduleTimezone,
      'scheduled_start_at': scheduledStartAt?.toIso8601String(),
      'scheduled_end_at': scheduledEndAt?.toIso8601String(),
      'schedule_windows': scheduleWindows.isNotEmpty
          ? scheduleWindows.map((w) => w.toJson()).toList()
          : null,
      'visible_outside_schedule': visibleOutsideSchedule,
      'translations_enabled': translationsEnabled,
      'translation_languages': translationLanguages,
    };
  }

  static String _accessMethodToString(AccessMethod method) {
    switch (method) {
      case AccessMethod.public:
        return 'public';
      case AccessMethod.code:
        return 'code';
      case AccessMethod.inviteOnly:
        return 'invite_only';
      case AccessMethod.personalCode:
        return 'personal_code';
    }
  }

  static String _startModeToString(StartMode mode) {
    switch (mode) {
      case StartMode.auto:
        return 'auto';
      case StartMode.manual:
        return 'manual';
    }
  }

  /// Whether this chat has a schedule configured.
  /// Schedule is independent of facilitation mode (startMode).
  bool get hasSchedule => scheduleType != null;

  /// Whether this chat is paused (by either schedule or host).
  bool get isPaused => schedulePaused || hostPaused;

  /// Display name with translation fallback (translated → original).
  String get displayName => nameTranslated ?? name;

  /// Display description with translation fallback (translated → original).
  String? get displayDescription => descriptionTranslated ?? description;

  /// Display initial message with translation fallback (translated → original → empty).
  String get displayInitialMessage => initialMessageTranslated ?? initialMessage ?? '';

  @override
  List<Object?> get props => [
        id,
        name,
        initialMessage,
        initialMessageAudioUrl,
        initialMessageVideoUrl,
        backgroundAudioUrl,
        description,
        inviteCode,
        accessMethod,
        requireAuth,
        requireApproval,
        creatorId,
        creatorSessionToken,
        hostDisplayName,
        isActive,
        isOfficial,
        expiresAt,
        lastActivityAt,
        startMode,
        ratingStartMode,
        autoStartParticipantCount,
        proposingDurationSeconds,
        ratingDurationSeconds,
        proposingMinimum,
        ratingMinimum,
        proposingThresholdPercent,
        proposingThresholdCount,
        ratingThresholdPercent,
        ratingThresholdCount,
        enableAiParticipant,
        aiPropositionsCount,
        confirmationRoundsRequired,
        showPreviousResults,
        propositionsPerUser,
        ratingMode,
        matchObjective,
        maxCycles,
        endedAt,
        isPreview,
        branchingEnabled,
        enableAgents,
        createdAt,
        adaptiveDurationEnabled,
        adaptiveAdjustmentPercent,
        minPhaseDurationSeconds,
        maxPhaseDurationSeconds,
        cadenceAnchorAt,
        scheduleType,
        scheduleTimezone,
        scheduledStartAt,
        scheduledEndAt,
        scheduleWindows,
        visibleOutsideSchedule,
        schedulePaused,
        hostPaused,
        allowSkipProposing,
        allowSkipRating,
        translationsEnabled,
        translationLanguages,
        nameTranslated,
        descriptionTranslated,
        initialMessageTranslated,
        translationLanguage,
      ];

  /// Calculates the next window start time for recurring schedules.
  /// Returns null if no windows are configured or if calculation fails.
  DateTime? getNextWindowStart() {
    if (scheduleWindows.isEmpty) return null;

    final now = DateTime.now();
    // Note: For a more robust implementation, use timezone package to handle
    // conversions between scheduleTimezone and local time
    final currentDayOfWeek = now.weekday; // 1=Monday, 7=Sunday
    final currentTime = TimeOfDay(hour: now.hour, minute: now.minute);

    DateTime? earliestNext;

    for (final window in scheduleWindows) {
      final windowStartDay = _dayNameToWeekday(window.startDay);
      if (windowStartDay == null) continue;

      final windowStartTime = window.startTimeOfDay;

      // Calculate days until the window start day
      int daysUntil = windowStartDay - currentDayOfWeek;
      if (daysUntil < 0) daysUntil += 7;

      // If it's the same day, check if the time has passed
      if (daysUntil == 0) {
        final windowStartMinutes = windowStartTime.hour * 60 + windowStartTime.minute;
        final currentMinutes = currentTime.hour * 60 + currentTime.minute;
        if (currentMinutes >= windowStartMinutes) {
          // This window has already started today, check next week
          daysUntil = 7;
        }
      }

      final nextStart = DateTime(
        now.year,
        now.month,
        now.day + daysUntil,
        windowStartTime.hour,
        windowStartTime.minute,
      );

      if (earliestNext == null || nextStart.isBefore(earliestNext)) {
        earliestNext = nextStart;
      }
    }

    return earliestNext;
  }

  static int? _dayNameToWeekday(String dayName) {
    const days = {
      'monday': 1,
      'tuesday': 2,
      'wednesday': 3,
      'thursday': 4,
      'friday': 5,
      'saturday': 6,
      'sunday': 7,
    };
    return days[dayName.toLowerCase()];
  }
}
