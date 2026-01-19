import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../core/errors/app_exception.dart';

enum AccessMethod { public, code, inviteOnly }

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
  final String initialMessage;
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
  final DateTime createdAt;

  // Adaptive duration settings (uses early advance thresholds)
  final bool adaptiveDurationEnabled;
  final int adaptiveAdjustmentPercent;
  final int minPhaseDurationSeconds;
  final int maxPhaseDurationSeconds;

  // Schedule settings (independent of startMode - controls when chat room is open)
  final ScheduleType? scheduleType;
  final String scheduleTimezone;
  final DateTime? scheduledStartAt; // For one-time schedule
  final List<ScheduleWindow> scheduleWindows; // For recurring schedules
  final bool visibleOutsideSchedule;
  final bool schedulePaused;
  final bool hostPaused;

  // Translation fields (populated when fetching with language code)
  final String? nameTranslated;
  final String? descriptionTranslated;
  final String? initialMessageTranslated;
  final String? translationLanguage;

  const Chat({
    required this.id,
    required this.name,
    required this.initialMessage,
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
    required this.createdAt,
    this.adaptiveDurationEnabled = false,
    this.adaptiveAdjustmentPercent = 10,
    this.minPhaseDurationSeconds = 60,
    this.maxPhaseDurationSeconds = 86400,
    this.scheduleType,
    this.scheduleTimezone = 'UTC',
    this.scheduledStartAt,
    this.scheduleWindows = const [],
    this.visibleOutsideSchedule = true,
    this.schedulePaused = false,
    this.hostPaused = false,
    this.nameTranslated,
    this.descriptionTranslated,
    this.initialMessageTranslated,
    this.translationLanguage,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as int,
      name: json['name'] as String,
      initialMessage: json['initial_message'] as String,
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
      createdAt: DateTime.parse(json['created_at'] as String),
      adaptiveDurationEnabled: json['adaptive_duration_enabled'] as bool? ?? false,
      adaptiveAdjustmentPercent: json['adaptive_adjustment_percent'] as int? ?? 10,
      minPhaseDurationSeconds: json['min_phase_duration_seconds'] as int? ?? 60,
      maxPhaseDurationSeconds: json['max_phase_duration_seconds'] as int? ?? 86400,
      scheduleType: _parseScheduleType(json['schedule_type'] as String?),
      scheduleTimezone: json['schedule_timezone'] as String? ?? 'UTC',
      scheduledStartAt: json['scheduled_start_at'] != null
          ? DateTime.parse(json['scheduled_start_at'] as String)
          : null,
      scheduleWindows: (json['schedule_windows'] as List<dynamic>?)
              ?.map((e) => ScheduleWindow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      visibleOutsideSchedule: json['visible_outside_schedule'] as bool? ?? true,
      schedulePaused: json['schedule_paused'] as bool? ?? false,
      hostPaused: json['host_paused'] as bool? ?? false,
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
      'adaptive_duration_enabled': adaptiveDurationEnabled,
      'adaptive_adjustment_percent': adaptiveAdjustmentPercent,
      'min_phase_duration_seconds': minPhaseDurationSeconds,
      'max_phase_duration_seconds': maxPhaseDurationSeconds,
      'schedule_type': scheduleType?.name,
      'schedule_timezone': scheduleTimezone,
      'scheduled_start_at': scheduledStartAt?.toIso8601String(),
      'schedule_windows': scheduleWindows.isNotEmpty
          ? scheduleWindows.map((w) => w.toJson()).toList()
          : null,
      'visible_outside_schedule': visibleOutsideSchedule,
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

  /// Display initial message with translation fallback (translated → original).
  String get displayInitialMessage => initialMessageTranslated ?? initialMessage;

  @override
  List<Object?> get props => [
        id,
        name,
        initialMessage,
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
        createdAt,
        adaptiveDurationEnabled,
        adaptiveAdjustmentPercent,
        minPhaseDurationSeconds,
        maxPhaseDurationSeconds,
        scheduleType,
        scheduleTimezone,
        scheduledStartAt,
        scheduleWindows,
        visibleOutsideSchedule,
        schedulePaused,
        hostPaused,
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
