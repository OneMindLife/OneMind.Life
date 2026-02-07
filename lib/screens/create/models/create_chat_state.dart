import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Settings for phase timers
class TimerSettings extends Equatable {
  final bool useSameDuration; // When true, proposing and rating use same duration
  final String proposingPreset;
  final String ratingPreset;
  final int proposingDuration;
  final int ratingDuration;

  const TimerSettings({
    required this.useSameDuration,
    required this.proposingPreset,
    required this.ratingPreset,
    required this.proposingDuration,
    required this.ratingDuration,
  });

  factory TimerSettings.defaults() => const TimerSettings(
        useSameDuration: true, // Default to same duration for both phases
        proposingPreset: '1day',
        ratingPreset: '1day',
        proposingDuration: 86400,
        ratingDuration: 86400,
      );

  TimerSettings copyWith({
    bool? useSameDuration,
    String? proposingPreset,
    String? ratingPreset,
    int? proposingDuration,
    int? ratingDuration,
  }) {
    return TimerSettings(
      useSameDuration: useSameDuration ?? this.useSameDuration,
      proposingPreset: proposingPreset ?? this.proposingPreset,
      ratingPreset: ratingPreset ?? this.ratingPreset,
      proposingDuration: proposingDuration ?? this.proposingDuration,
      ratingDuration: ratingDuration ?? this.ratingDuration,
    );
  }

  @override
  List<Object?> get props => [
        useSameDuration,
        proposingPreset,
        ratingPreset,
        proposingDuration,
        ratingDuration,
      ];
}

/// Minimum participation requirements to advance phases
class MinimumSettings extends Equatable {
  final int proposingMinimum;
  final int ratingMinimum;

  const MinimumSettings({
    required this.proposingMinimum,
    required this.ratingMinimum,
  });

  /// Default minimum propositions is 3 (not 2) because users cannot rate their
  /// own propositions. With 3 total, each user sees at least 2 to rank.
  factory MinimumSettings.defaults() => const MinimumSettings(
        proposingMinimum: 3,
        ratingMinimum: 2,
      );

  MinimumSettings copyWith({
    int? proposingMinimum,
    int? ratingMinimum,
  }) {
    return MinimumSettings(
      proposingMinimum: proposingMinimum ?? this.proposingMinimum,
      ratingMinimum: ratingMinimum ?? this.ratingMinimum,
    );
  }

  @override
  List<Object?> get props => [proposingMinimum, ratingMinimum];
}

/// Auto-advance threshold settings
class AutoAdvanceSettings extends Equatable {
  final bool enableProposing;
  final int proposingThresholdPercent;
  final int proposingThresholdCount;
  final bool enableRating;
  final int ratingThresholdPercent;
  final int ratingThresholdCount;

  const AutoAdvanceSettings({
    required this.enableProposing,
    required this.proposingThresholdPercent,
    required this.proposingThresholdCount,
    required this.enableRating,
    required this.ratingThresholdPercent,
    required this.ratingThresholdCount,
  });

  /// Smart defaults: end phases early when participation is complete.
  /// - Proposing: ends when 100% of participants have acted (submitted OR skipped)
  /// - Rating: ends when 100% of eligible raters have rated (capped to participants-1
  ///   since users can't rate their own propositions)
  factory AutoAdvanceSettings.defaults() => const AutoAdvanceSettings(
        enableProposing: true,
        proposingThresholdPercent: 100, // End when all participants have acted
        proposingThresholdCount: 3, // Minimum propositions (same as proposing_minimum)
        enableRating: true,
        ratingThresholdPercent: 100, // End when all eligible raters have rated
        ratingThresholdCount: 2, // Minimum ratings per proposition
      );

  AutoAdvanceSettings copyWith({
    bool? enableProposing,
    int? proposingThresholdPercent,
    int? proposingThresholdCount,
    bool? enableRating,
    int? ratingThresholdPercent,
    int? ratingThresholdCount,
  }) {
    return AutoAdvanceSettings(
      enableProposing: enableProposing ?? this.enableProposing,
      proposingThresholdPercent:
          proposingThresholdPercent ?? this.proposingThresholdPercent,
      proposingThresholdCount:
          proposingThresholdCount ?? this.proposingThresholdCount,
      enableRating: enableRating ?? this.enableRating,
      ratingThresholdPercent:
          ratingThresholdPercent ?? this.ratingThresholdPercent,
      ratingThresholdCount: ratingThresholdCount ?? this.ratingThresholdCount,
    );
  }

  @override
  List<Object?> get props => [
        enableProposing,
        proposingThresholdPercent,
        proposingThresholdCount,
        enableRating,
        ratingThresholdPercent,
        ratingThresholdCount,
      ];
}

/// Adaptive duration settings
/// Uses existing early advance thresholds to determine participation levels.
class AdaptiveDurationSettings extends Equatable {
  final bool enabled;
  final int adjustmentPercent;
  final int minDurationSeconds;
  final int maxDurationSeconds;

  const AdaptiveDurationSettings({
    required this.enabled,
    required this.adjustmentPercent,
    required this.minDurationSeconds,
    required this.maxDurationSeconds,
  });

  factory AdaptiveDurationSettings.defaults() => const AdaptiveDurationSettings(
        enabled: false,
        adjustmentPercent: 10,
        minDurationSeconds: 60,
        maxDurationSeconds: 86400,
      );

  AdaptiveDurationSettings copyWith({
    bool? enabled,
    int? adjustmentPercent,
    int? minDurationSeconds,
    int? maxDurationSeconds,
  }) {
    return AdaptiveDurationSettings(
      enabled: enabled ?? this.enabled,
      adjustmentPercent: adjustmentPercent ?? this.adjustmentPercent,
      minDurationSeconds: minDurationSeconds ?? this.minDurationSeconds,
      maxDurationSeconds: maxDurationSeconds ?? this.maxDurationSeconds,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        adjustmentPercent,
        minDurationSeconds,
        maxDurationSeconds,
      ];
}

/// AI participant settings
/// AI is always enabled by default and generates 1 proposition per round.
/// The UI section is hidden - this is controlled at the database level.
class AISettings extends Equatable {
  final bool enabled;
  final int propositionCount;

  const AISettings({
    required this.enabled,
    required this.propositionCount,
  });

  factory AISettings.defaults() => const AISettings(
        enabled: true,  // AI always enabled by default
        propositionCount: 1,  // One thoughtful proposition per round
      );

  AISettings copyWith({
    bool? enabled,
    int? propositionCount,
  }) {
    return AISettings(
      enabled: enabled ?? this.enabled,
      propositionCount: propositionCount ?? this.propositionCount,
    );
  }

  @override
  List<Object?> get props => [enabled, propositionCount];
}

/// Consensus and results settings
class ConsensusSettings extends Equatable {
  final int confirmationRoundsRequired;
  final bool showPreviousResults;
  final int propositionsPerUser;

  const ConsensusSettings({
    required this.confirmationRoundsRequired,
    required this.showPreviousResults,
    required this.propositionsPerUser,
  });

  factory ConsensusSettings.defaults() => const ConsensusSettings(
        confirmationRoundsRequired: 2,
        showPreviousResults: true,
        propositionsPerUser: 1,
      );

  ConsensusSettings copyWith({
    int? confirmationRoundsRequired,
    bool? showPreviousResults,
    int? propositionsPerUser,
  }) {
    return ConsensusSettings(
      confirmationRoundsRequired:
          confirmationRoundsRequired ?? this.confirmationRoundsRequired,
      showPreviousResults: showPreviousResults ?? this.showPreviousResults,
      propositionsPerUser: propositionsPerUser ?? this.propositionsPerUser,
    );
  }

  @override
  List<Object?> get props => [
        confirmationRoundsRequired,
        showPreviousResults,
        propositionsPerUser,
      ];
}

/// A single schedule window for recurring schedules.
/// Supports same-day, midnight-spanning, and multi-day windows.
class ScheduleWindow extends Equatable {
  final String startDay; // e.g., 'monday'
  final TimeOfDay startTime;
  final String endDay; // e.g., 'monday'
  final TimeOfDay endTime;

  const ScheduleWindow({
    required this.startDay,
    required this.startTime,
    required this.endDay,
    required this.endTime,
  });

  factory ScheduleWindow.defaults() => const ScheduleWindow(
        startDay: 'monday',
        startTime: TimeOfDay(hour: 9, minute: 0),
        endDay: 'monday',
        endTime: TimeOfDay(hour: 17, minute: 0),
      );

  ScheduleWindow copyWith({
    String? startDay,
    TimeOfDay? startTime,
    String? endDay,
    TimeOfDay? endTime,
  }) {
    return ScheduleWindow(
      startDay: startDay ?? this.startDay,
      startTime: startTime ?? this.startTime,
      endDay: endDay ?? this.endDay,
      endTime: endTime ?? this.endTime,
    );
  }

  /// Returns true if this is a same-day window
  bool get isSameDay => startDay == endDay;

  /// Formats the time for display
  String get formattedStartTime =>
      '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';

  String get formattedEndTime =>
      '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

  /// Capitalize first letter of day name
  String get displayStartDay =>
      startDay[0].toUpperCase() + startDay.substring(1);
  String get displayEndDay => endDay[0].toUpperCase() + endDay.substring(1);

  /// Returns a human-readable description of this window
  String get displayText {
    if (isSameDay) {
      return '$displayStartDay $formattedStartTime - $formattedEndTime';
    }
    return '$displayStartDay $formattedStartTime → $displayEndDay $formattedEndTime';
  }

  @override
  List<Object?> get props => [startDay, startTime, endDay, endTime];
}

/// Schedule settings for scheduled chats
class ScheduleSettings extends Equatable {
  final ScheduleType type;
  final DateTime scheduledStartAt; // For one-time schedule
  final List<ScheduleWindow> windows; // For recurring schedules
  final String timezone;
  final bool visibleOutsideSchedule;

  const ScheduleSettings({
    required this.type,
    required this.scheduledStartAt,
    required this.windows,
    required this.timezone,
    required this.visibleOutsideSchedule,
  });

  factory ScheduleSettings.defaults({String timezone = 'America/New_York'}) =>
      ScheduleSettings(
        type: ScheduleType.once,
        scheduledStartAt: DateTime.now().add(const Duration(hours: 1)),
        windows: const [], // Empty by default - user adds windows if they switch to recurring
        timezone: timezone,
        visibleOutsideSchedule: true,
      );

  /// Creates test-friendly defaults with windows calculated from current time.
  /// Window 1: starts in [offsetMinutes] minutes, lasts [windowDuration] minutes
  /// Window 2: starts [gapMinutes] after window 1 ends, lasts [windowDuration] minutes
  factory ScheduleSettings.testDefaults({
    String timezone = 'America/New_York',
    int offsetMinutes = 3,
    int windowDuration = 8,
    int gapMinutes = 5,
  }) {
    final now = DateTime.now();
    final dayName = _dayNameFromWeekday(now.weekday);

    // Window 1: starts in offsetMinutes
    final window1Start = TimeOfDay(
      hour: (now.hour + (now.minute + offsetMinutes) ~/ 60) % 24,
      minute: (now.minute + offsetMinutes) % 60,
    );
    final window1EndMinutes = now.minute + offsetMinutes + windowDuration;
    final window1End = TimeOfDay(
      hour: (now.hour + window1EndMinutes ~/ 60) % 24,
      minute: window1EndMinutes % 60,
    );

    // Window 2: starts gapMinutes after window 1 ends
    final window2StartMinutes = now.minute + offsetMinutes + windowDuration + gapMinutes;
    final window2Start = TimeOfDay(
      hour: (now.hour + window2StartMinutes ~/ 60) % 24,
      minute: window2StartMinutes % 60,
    );
    final window2EndMinutes = window2StartMinutes + windowDuration;
    final window2End = TimeOfDay(
      hour: (now.hour + window2EndMinutes ~/ 60) % 24,
      minute: window2EndMinutes % 60,
    );

    return ScheduleSettings(
      type: ScheduleType.recurring,
      scheduledStartAt: now.add(const Duration(hours: 1)),
      windows: [
        ScheduleWindow(
          startDay: dayName,
          startTime: window1Start,
          endDay: dayName,
          endTime: window1End,
        ),
        ScheduleWindow(
          startDay: dayName,
          startTime: window2Start,
          endDay: dayName,
          endTime: window2End,
        ),
      ],
      timezone: timezone,
      visibleOutsideSchedule: true,
    );
  }

  static String _dayNameFromWeekday(int weekday) {
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    return days[weekday - 1]; // weekday is 1-7 (Mon-Sun)
  }

  ScheduleSettings copyWith({
    ScheduleType? type,
    DateTime? scheduledStartAt,
    List<ScheduleWindow>? windows,
    String? timezone,
    bool? visibleOutsideSchedule,
  }) {
    return ScheduleSettings(
      type: type ?? this.type,
      scheduledStartAt: scheduledStartAt ?? this.scheduledStartAt,
      windows: windows ?? this.windows,
      timezone: timezone ?? this.timezone,
      visibleOutsideSchedule:
          visibleOutsideSchedule ?? this.visibleOutsideSchedule,
    );
  }

  @override
  List<Object?> get props => [
        type,
        scheduledStartAt,
        windows,
        timezone,
        visibleOutsideSchedule,
      ];
}

/// Schedule type enum
enum ScheduleType { once, recurring }
