import 'package:flutter/material.dart';
import '../models/create_chat_state.dart';

/// Validation helpers for create chat form
class CreateChatValidation {
  /// Validates adaptive duration settings against timer values
  static String? validateAdaptiveDuration({
    required int proposingDuration,
    required int ratingDuration,
    required int minDuration,
    required int maxDuration,
  }) {
    if (proposingDuration < minDuration) {
      return 'Proposing timer (${_formatDuration(proposingDuration)}) is below adaptive minimum (${_formatDuration(minDuration)})';
    }
    if (proposingDuration > maxDuration) {
      return 'Proposing timer (${_formatDuration(proposingDuration)}) exceeds adaptive maximum (${_formatDuration(maxDuration)})';
    }
    if (ratingDuration < minDuration) {
      return 'Rating timer (${_formatDuration(ratingDuration)}) is below adaptive minimum (${_formatDuration(minDuration)})';
    }
    if (ratingDuration > maxDuration) {
      return 'Rating timer (${_formatDuration(ratingDuration)}) exceeds adaptive maximum (${_formatDuration(maxDuration)})';
    }
    return null;
  }

  /// Validates schedule settings
  static String? validateSchedule({
    required ScheduleType type,
    required DateTime scheduledStartAt,
  }) {
    if (type == ScheduleType.once) {
      if (scheduledStartAt.isBefore(DateTime.now())) {
        return 'Scheduled start time must be in the future';
      }
    }
    return null;
  }

  /// Checks if timer exceeds schedule window
  static bool timerExceedsWindow({
    required int proposingDuration,
    required int ratingDuration,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
  }) {
    final windowMinutes = (endTime.hour * 60 + endTime.minute) -
        (startTime.hour * 60 + startTime.minute);
    final proposingMinutes = proposingDuration ~/ 60;
    final ratingMinutes = ratingDuration ~/ 60;

    return proposingMinutes > windowMinutes || ratingMinutes > windowMinutes;
  }

  /// Calculate schedule window minutes
  static int calculateWindowMinutes({
    required TimeOfDay startTime,
    required TimeOfDay endTime,
  }) {
    return (endTime.hour * 60 + endTime.minute) -
        (startTime.hour * 60 + startTime.minute);
  }

  /// Format duration in human-readable form
  static String formatDuration(int seconds) => _formatDuration(seconds);

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    if (seconds < 3600) return '${seconds ~/ 60} min';
    if (seconds < 86400) {
      final hours = seconds ~/ 3600;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    final days = seconds ~/ 86400;
    return days == 1 ? '1 day' : '$days days';
  }
}
