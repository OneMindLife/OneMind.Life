import 'package:flutter/material.dart';
import '../../../models/models.dart';
import '../models/create_chat_state.dart' as state;
import 'form_inputs.dart';
import 'schedule_settings.dart';

/// Phase start section for start mode and schedule configuration.
///
/// Facilitation mode (manual/auto) controls how proposing starts.
/// Schedule (optional) controls when the chat room is open - independent of facilitation.
class PhaseStartSection extends StatelessWidget {
  final StartMode startMode;
  final StartMode ratingStartMode;
  final int autoStartCount;
  final bool enableSchedule;
  final state.ScheduleSettings scheduleSettings;
  final void Function(StartMode) onStartModeChanged;
  final void Function(StartMode) onRatingStartModeChanged;
  final void Function(int) onAutoStartCountChanged;
  final void Function(bool) onEnableScheduleChanged;
  final void Function(state.ScheduleSettings) onScheduleSettingsChanged;

  const PhaseStartSection({
    super.key,
    required this.startMode,
    required this.ratingStartMode,
    required this.autoStartCount,
    required this.enableSchedule,
    required this.scheduleSettings,
    required this.onStartModeChanged,
    required this.onRatingStartModeChanged,
    required this.onAutoStartCountChanged,
    required this.onEnableScheduleChanged,
    required this.onScheduleSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Facilitation Mode'),
        const SizedBox(height: 4),
        Text(
          'Controls how the chat begins and whether timers manage phase transitions.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<StartMode>(
          segments: const [
            ButtonSegment(value: StartMode.manual, label: Text('Manual')),
            ButtonSegment(value: StartMode.auto, label: Text('Auto')),
          ],
          selected: {startMode},
          onSelectionChanged: (v) => onStartModeChanged(v.first),
        ),
        const SizedBox(height: 8),
        _buildModeDescription(context),
        if (startMode == StartMode.auto) ...[
          const SizedBox(height: 16),
          NumberInput(
            label: 'Auto-start at X participants',
            value: autoStartCount,
            onChanged: onAutoStartCountChanged,
            min: 3, // Minimum 3: need 3+ propositions and 2+ others' to rank
          ),
        ],
        // Rating start mode section - only shown for manual facilitation
        // When facilitation is auto, rating also starts automatically
        if (startMode == StartMode.manual) ...[
          const SizedBox(height: 24),
          const SectionHeader('Rating Start Mode'),
          const SizedBox(height: 4),
          Text(
            'Controls how the rating phase begins after proposing ends.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<StartMode>(
            segments: const [
              ButtonSegment(value: StartMode.auto, label: Text('Auto')),
              ButtonSegment(value: StartMode.manual, label: Text('Manual')),
            ],
            selected: {ratingStartMode},
            onSelectionChanged: (v) => onRatingStartModeChanged(v.first),
          ),
          const SizedBox(height: 8),
          _buildRatingModeDescription(context),
        ],
        const SizedBox(height: 24),
        // Schedule section (independent of facilitation mode)
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enable Schedule',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Restrict when the chat room is open',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enableSchedule,
              onChanged: onEnableScheduleChanged,
            ),
          ],
        ),
        if (enableSchedule) ...[
          const SizedBox(height: 16),
          ScheduleSettingsCard(
            scheduleType: _toWidgetScheduleType(scheduleSettings.type),
            scheduledStartAt: scheduleSettings.scheduledStartAt,
            windows: scheduleSettings.windows,
            scheduleTimezone: scheduleSettings.timezone,
            visibleOutsideSchedule: scheduleSettings.visibleOutsideSchedule,
            onScheduleTypeChanged: (v) => onScheduleSettingsChanged(
              scheduleSettings.copyWith(type: _fromWidgetScheduleType(v)),
            ),
            onScheduledStartAtChanged: (v) => onScheduleSettingsChanged(
              scheduleSettings.copyWith(scheduledStartAt: v),
            ),
            onWindowsChanged: (v) => onScheduleSettingsChanged(
              scheduleSettings.copyWith(windows: v),
            ),
            onScheduleTimezoneChanged: (v) => onScheduleSettingsChanged(
              scheduleSettings.copyWith(timezone: v),
            ),
            onVisibleOutsideScheduleChanged: (v) => onScheduleSettingsChanged(
              scheduleSettings.copyWith(visibleOutsideSchedule: v),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeDescription(BuildContext context) {
    final String description;

    switch (startMode) {
      case StartMode.manual:
        description = 'You control everything. No timers. Click to start and advance each phase.';
      case StartMode.auto:
        description = 'Starts when enough people join. Timers advance phases automatically.';
    }

    return Text(
      description,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildRatingModeDescription(BuildContext context) {
    final String description;

    switch (ratingStartMode) {
      case StartMode.auto:
        description = 'Rating starts immediately after proposing ends or threshold is met.';
      case StartMode.manual:
        description = 'After proposing ends, you choose when to start rating (e.g., the next day).';
    }

    return Text(
      description,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  // Convert between the two ScheduleType enums
  ScheduleType _toWidgetScheduleType(state.ScheduleType type) {
    return type == state.ScheduleType.once
        ? ScheduleType.once
        : ScheduleType.recurring;
  }

  state.ScheduleType _fromWidgetScheduleType(ScheduleType type) {
    return type == ScheduleType.once
        ? state.ScheduleType.once
        : state.ScheduleType.recurring;
  }
}
