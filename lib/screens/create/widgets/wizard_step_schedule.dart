import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../utils/timezone_utils.dart';
import '../models/create_chat_state.dart' as state;

/// Schedule mode for the wizard: always active, one-time, or recurring.
enum _ScheduleMode { always, once, recurring }

/// Step 5 of the create chat wizard: Schedule.
/// Lets the user choose when the chat is active.
class WizardStepSchedule extends StatelessWidget {
  final bool enableSchedule;
  final state.ScheduleSettings scheduleSettings;
  final void Function(bool) onEnableScheduleChanged;
  final void Function(state.ScheduleSettings) onScheduleSettingsChanged;
  final VoidCallback onContinue;

  const WizardStepSchedule({
    super.key,
    required this.enableSchedule,
    required this.scheduleSettings,
    required this.onEnableScheduleChanged,
    required this.onScheduleSettingsChanged,
    required this.onContinue,
  });

  _ScheduleMode get _mode {
    if (!enableSchedule) return _ScheduleMode.always;
    if (scheduleSettings.type == state.ScheduleType.once) {
      return _ScheduleMode.once;
    }
    return _ScheduleMode.recurring;
  }

  void _onModeChanged(_ScheduleMode mode) {
    switch (mode) {
      case _ScheduleMode.always:
        onEnableScheduleChanged(false);
      case _ScheduleMode.once:
        onEnableScheduleChanged(true);
        onScheduleSettingsChanged(
          scheduleSettings.copyWith(type: state.ScheduleType.once),
        );
      case _ScheduleMode.recurring:
        onEnableScheduleChanged(true);
        onScheduleSettingsChanged(
          scheduleSettings.copyWith(
            type: state.ScheduleType.recurring,
            windows: scheduleSettings.windows.isEmpty
                ? [state.ScheduleWindow.defaults()]
                : null,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.wizardScheduleTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Mode cards
                  _ScheduleModeCard(
                    icon: Icons.all_inclusive,
                    title: l10n.wizardScheduleAlwaysTitle,
                    description: l10n.wizardScheduleAlwaysDesc,
                    isSelected: _mode == _ScheduleMode.always,
                    onTap: () => _onModeChanged(_ScheduleMode.always),
                  ),
                  const SizedBox(height: 16),
                  _ScheduleModeCard(
                    icon: Icons.event,
                    title: l10n.wizardScheduleOnceTitle,
                    description: l10n.wizardScheduleOnceDesc,
                    isSelected: _mode == _ScheduleMode.once,
                    onTap: () => _onModeChanged(_ScheduleMode.once),
                  ),
                  const SizedBox(height: 16),
                  _ScheduleModeCard(
                    icon: Icons.repeat,
                    title: l10n.wizardScheduleRecurringTitle,
                    description: l10n.wizardScheduleRecurringDesc,
                    isSelected: _mode == _ScheduleMode.recurring,
                    onTap: () => _onModeChanged(_ScheduleMode.recurring),
                  ),

                  // Conditional settings
                  if (_mode == _ScheduleMode.once) ...[
                    const SizedBox(height: 24),
                    _OneTimeSettings(
                      scheduledStartAt: scheduleSettings.scheduledStartAt,
                      scheduledEndAt: scheduleSettings.scheduledEndAt,
                      timezone: scheduleSettings.timezone,
                      onStartChanged: (dt) => onScheduleSettingsChanged(
                        scheduleSettings.copyWith(scheduledStartAt: dt),
                      ),
                      onEndChanged: (dt) => onScheduleSettingsChanged(
                        dt != null
                            ? scheduleSettings.copyWith(scheduledEndAt: dt)
                            : scheduleSettings.copyWith(clearEndAt: true),
                      ),
                      onTimezoneChanged: (tz) => onScheduleSettingsChanged(
                        scheduleSettings.copyWith(timezone: tz),
                      ),
                    ),
                  ],

                  if (_mode == _ScheduleMode.recurring) ...[
                    const SizedBox(height: 24),
                    _RecurringSettings(
                      windows: scheduleSettings.windows,
                      timezone: scheduleSettings.timezone,
                      onWindowsChanged: (w) => onScheduleSettingsChanged(
                        scheduleSettings.copyWith(windows: w),
                      ),
                      onTimezoneChanged: (tz) => onScheduleSettingsChanged(
                        scheduleSettings.copyWith(timezone: tz),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Navigation
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onContinue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.continue_),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode selection card (same pattern as _VisibilityCard)
// ---------------------------------------------------------------------------

class _ScheduleModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScheduleModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: isSelected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One-time schedule settings
// ---------------------------------------------------------------------------

class _OneTimeSettings extends StatelessWidget {
  final DateTime scheduledStartAt;
  final DateTime? scheduledEndAt;
  final String timezone;
  final void Function(DateTime) onStartChanged;
  final void Function(DateTime?) onEndChanged;
  final void Function(String) onTimezoneChanged;

  const _OneTimeSettings({
    required this.scheduledStartAt,
    required this.scheduledEndAt,
    required this.timezone,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onTimezoneChanged,
  });

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDate(DateTime dt) => '${dt.month}/${dt.day}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timezone
            Text(l10n.timezoneLabel,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _TimezoneAutocomplete(
              selectedTimezone: timezone,
              onTimezoneChanged: onTimezoneChanged,
            ),
            const SizedBox(height: 16),

            // Start Date & Time
            Text(l10n.startDateTime,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _DateTimePicker(
              dateTime: scheduledStartAt,
              firstDate: DateTime.now(),
              onChanged: onStartChanged,
              formatTime: _formatTimeOfDay,
              formatDate: _formatDate,
            ),
            const SizedBox(height: 16),

            // Optional End Date & Time
            if (scheduledEndAt != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.scheduleEndTimeLabel,
                      style: theme.textTheme.titleSmall),
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(l10n.scheduleClearEndTime),
                    onPressed: () => onEndChanged(null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DateTimePicker(
                dateTime: scheduledEndAt!,
                firstDate: scheduledStartAt,
                onChanged: (dt) => onEndChanged(dt),
                formatTime: _formatTimeOfDay,
                formatDate: _formatDate,
              ),
            ] else ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.scheduleSetEndTime),
                onPressed: () {
                  // Default end = 1 hour after start
                  onEndChanged(
                      scheduledStartAt.add(const Duration(hours: 1)));
                },
              ),
              const SizedBox(height: 4),
              Text(
                l10n.scheduleEndTimeHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable date + time picker row.
class _DateTimePicker extends StatelessWidget {
  final DateTime dateTime;
  final DateTime firstDate;
  final void Function(DateTime) onChanged;
  final String Function(TimeOfDay) formatTime;
  final String Function(DateTime) formatDate;

  const _DateTimePicker({
    required this.dateTime,
    required this.firstDate,
    required this.onChanged,
    required this.formatTime,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(formatDate(dateTime)),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: dateTime,
                firstDate: firstDate,
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                onChanged(DateTime(
                  date.year,
                  date.month,
                  date.day,
                  dateTime.hour,
                  dateTime.minute,
                ));
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.access_time),
            label: Text(formatTime(TimeOfDay.fromDateTime(dateTime))),
            onPressed: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(dateTime),
              );
              if (time != null) {
                onChanged(DateTime(
                  dateTime.year,
                  dateTime.month,
                  dateTime.day,
                  time.hour,
                  time.minute,
                ));
              }
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recurring schedule settings
// ---------------------------------------------------------------------------

class _RecurringSettings extends StatelessWidget {
  final List<state.ScheduleWindow> windows;
  final String timezone;
  final void Function(List<state.ScheduleWindow>) onWindowsChanged;
  final void Function(String) onTimezoneChanged;

  const _RecurringSettings({
    required this.windows,
    required this.timezone,
    required this.onWindowsChanged,
    required this.onTimezoneChanged,
  });

  void _addWindow() {
    onWindowsChanged([...windows, state.ScheduleWindow.defaults()]);
  }

  void _removeWindow(int index) {
    if (windows.length > 1) {
      final updated = List<state.ScheduleWindow>.from(windows)
        ..removeAt(index);
      onWindowsChanged(updated);
    }
  }

  void _updateWindow(int index, state.ScheduleWindow w) {
    final updated = List<state.ScheduleWindow>.from(windows);
    updated[index] = w;
    onWindowsChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timezone
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.timezoneLabel,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                _TimezoneAutocomplete(
                  selectedTimezone: timezone,
                  onTimezoneChanged: onTimezoneChanged,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Windows header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.scheduleWindowsTitle,
                style: theme.textTheme.titleSmall),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addWindowButton),
              onPressed: _addWindow,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.scheduleWindowsDesc,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),

        // Window list
        ...List.generate(windows.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _WindowCard(
              window: windows[i],
              index: i,
              canDelete: windows.length > 1,
              onChanged: (w) => _updateWindow(i, w),
              onDelete: () => _removeWindow(i),
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Single schedule window card
// ---------------------------------------------------------------------------

class _WindowCard extends StatelessWidget {
  final state.ScheduleWindow window;
  final int index;
  final bool canDelete;
  final void Function(state.ScheduleWindow) onChanged;
  final VoidCallback onDelete;

  static const _allDays = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  ];

  const _WindowCard({
    required this.window,
    required this.index,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Map<String, String> _dayLabels(AppLocalizations l10n) => {
        'sunday': l10n.daySun,
        'monday': l10n.dayMon,
        'tuesday': l10n.dayTue,
        'wednesday': l10n.dayWed,
        'thursday': l10n.dayThu,
        'friday': l10n.dayFri,
        'saturday': l10n.daySat,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final labels = _dayLabels(l10n);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.windowNumber(index + 1),
                    style: theme.textTheme.labelLarge),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.removeWindow,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Start day + time
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: window.startDay,
                    decoration: InputDecoration(
                      labelText: l10n.startDay,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: _allDays
                        .map((d) => DropdownMenuItem(
                            value: d, child: Text(labels[d] ?? d)))
                        .toList(),
                    onChanged: (v) =>
                        onChanged(window.copyWith(startDay: v ?? 'monday')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: window.startTime,
                      );
                      if (t != null) onChanged(window.copyWith(startTime: t));
                    },
                    child: Text(_formatTimeOfDay(window.startTime)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Icon(Icons.arrow_downward,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),

            // End day + time
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: window.endDay,
                    decoration: InputDecoration(
                      labelText: l10n.endDay,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: _allDays
                        .map((d) => DropdownMenuItem(
                            value: d, child: Text(labels[d] ?? d)))
                        .toList(),
                    onChanged: (v) =>
                        onChanged(window.copyWith(endDay: v ?? 'monday')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: window.endTime,
                      );
                      if (t != null) onChanged(window.copyWith(endTime: t));
                    },
                    child: Text(_formatTimeOfDay(window.endTime)),
                  ),
                ),
              ],
            ),

            // Summary
            const SizedBox(height: 8),
            Text(
              window.displayText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timezone autocomplete (reused from schedule_settings.dart)
// ---------------------------------------------------------------------------

class _TimezoneAutocomplete extends StatelessWidget {
  final String selectedTimezone;
  final void Function(String) onTimezoneChanged;

  const _TimezoneAutocomplete({
    required this.selectedTimezone,
    required this.onTimezoneChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Autocomplete<String>(
      initialValue: TextEditingValue(
        text: getTimezoneDisplayName(selectedTimezone),
      ),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.toLowerCase();
        if (query.isEmpty) return allTimezones.take(20);
        return allTimezones.where((tz) {
          final displayName = getTimezoneDisplayName(tz).toLowerCase();
          return displayName.contains(query) || tz.toLowerCase().contains(query);
        });
      },
      displayStringForOption: getTimezoneDisplayName,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: l10n.searchTimezone,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => controller.clear(),
            ),
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxHeight: 300, maxWidth: 350),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(getTimezoneDisplayName(option)),
                    subtitle: Text(
                      option,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: onTimezoneChanged,
    );
  }
}
