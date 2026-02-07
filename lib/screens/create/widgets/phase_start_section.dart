import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../models/create_chat_state.dart' as state;
import 'form_inputs.dart';
// NOTE: schedule_settings.dart import removed - schedule UI hidden for MVP.
// import 'schedule_settings.dart';

/// Phase start section - configures when the chat starts.
///
/// Note: Manual mode has been removed because the host can't see submitted
/// propositions, so they have no way to know when to advance phases.
/// All chats now use automatic timers.
class PhaseStartSection extends StatelessWidget {
  /// Kept for API compatibility - always auto now.
  @Deprecated('Start mode is always auto. Manual mode removed.')
  final StartMode startMode;
  @Deprecated('Rating start mode is always auto. Kept for API compatibility.')
  final StartMode ratingStartMode;
  final int autoStartCount;
  final bool enableSchedule;
  final state.ScheduleSettings scheduleSettings;
  @Deprecated('Start mode is always auto. Manual mode removed.')
  final void Function(StartMode) onStartModeChanged;
  @Deprecated('Rating start mode is always auto. Kept for API compatibility.')
  final void Function(StartMode)? onRatingStartModeChanged;
  final void Function(int) onAutoStartCountChanged;
  final void Function(bool) onEnableScheduleChanged;
  final void Function(state.ScheduleSettings) onScheduleSettingsChanged;

  const PhaseStartSection({
    super.key,
    this.startMode = StartMode.auto, // Always auto now
    this.ratingStartMode = StartMode.auto,
    required this.autoStartCount,
    required this.enableSchedule,
    required this.scheduleSettings,
    this.onStartModeChanged = _noOp, // No-op since always auto
    this.onRatingStartModeChanged,
    required this.onAutoStartCountChanged,
    required this.onEnableScheduleChanged,
    required this.onScheduleSettingsChanged,
  });

  static void _noOp(StartMode _) {}

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.autoStartParticipants),
        const SizedBox(height: 4),
        Text(
          l10n.modeAutoDesc,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        // NOTE: Manual/Auto toggle removed - always auto now.
        // Host can't see propositions, so manual advancement doesn't work.
        NumberInput(
          label: l10n.autoStartParticipants,
          value: autoStartCount,
          onChanged: onAutoStartCountChanged,
          min: 3, // Minimum 3: need 3+ propositions and 2+ others' to rank
        ),
        // Note: Rating start mode UI removed - always auto.
        // The host can't view propositions before rating starts,
        // so manual review doesn't add value.
        // NOTE: Schedule section hidden - not needed for MVP.
        // Infrastructure kept for potential future use.
        // if (enableSchedule) ...[
        //   const SizedBox(height: 24),
        //   Row(
        //     children: [
        //       Expanded(
        //         child: Column(
        //           crossAxisAlignment: CrossAxisAlignment.start,
        //           children: [
        //             Text(
        //               l10n.enableSchedule,
        //               style: Theme.of(context).textTheme.titleSmall,
        //             ),
        //             Text(
        //               l10n.restrictChatRoom,
        //               style: Theme.of(context).textTheme.bodySmall?.copyWith(
        //                     color: Theme.of(context).colorScheme.onSurfaceVariant,
        //                   ),
        //             ),
        //           ],
        //         ),
        //       ),
        //       Switch(
        //         value: enableSchedule,
        //         onChanged: onEnableScheduleChanged,
        //       ),
        //     ],
        //   ),
        //   if (enableSchedule) ...[
        //     const SizedBox(height: 16),
        //     ScheduleSettingsCard(
        //       scheduleType: _toWidgetScheduleType(scheduleSettings.type),
        //       scheduledStartAt: scheduleSettings.scheduledStartAt,
        //       windows: scheduleSettings.windows,
        //       scheduleTimezone: scheduleSettings.timezone,
        //       visibleOutsideSchedule: scheduleSettings.visibleOutsideSchedule,
        //       onScheduleTypeChanged: (v) => onScheduleSettingsChanged(
        //         scheduleSettings.copyWith(type: _fromWidgetScheduleType(v)),
        //       ),
        //       onScheduledStartAtChanged: (v) => onScheduleSettingsChanged(
        //         scheduleSettings.copyWith(scheduledStartAt: v),
        //       ),
        //       onWindowsChanged: (v) => onScheduleSettingsChanged(
        //         scheduleSettings.copyWith(windows: v),
        //       ),
        //       onScheduleTimezoneChanged: (v) => onScheduleSettingsChanged(
        //         scheduleSettings.copyWith(timezone: v),
        //       ),
        //       onVisibleOutsideScheduleChanged: (v) => onScheduleSettingsChanged(
        //         scheduleSettings.copyWith(visibleOutsideSchedule: v),
        //       ),
        //     ),
        //   ],
        // ],
      ],
    );
  }

  // NOTE: _buildModeDescription removed - manual mode no longer exists.

  // NOTE: Schedule type conversion methods commented out - schedule UI hidden for MVP.
  // ScheduleType _toWidgetScheduleType(state.ScheduleType type) {
  //   return type == state.ScheduleType.once
  //       ? ScheduleType.once
  //       : ScheduleType.recurring;
  // }
  //
  // state.ScheduleType _fromWidgetScheduleType(ScheduleType type) {
  //   return type == ScheduleType.once
  //       ? state.ScheduleType.once
  //       : state.ScheduleType.recurring;
  // }
}
