import 'package:flutter/material.dart';
import '../../../models/models.dart';
import '../../../utils/timezone_utils.dart';
import '../models/create_chat_state.dart' as state;

/// A widget for configuring chat schedule settings.
class ScheduleSettingsCard extends StatelessWidget {
  final ScheduleType scheduleType;
  final DateTime scheduledStartAt;
  final List<state.ScheduleWindow> windows;
  final String scheduleTimezone;
  final bool visibleOutsideSchedule;
  final void Function(ScheduleType) onScheduleTypeChanged;
  final void Function(DateTime) onScheduledStartAtChanged;
  final void Function(List<state.ScheduleWindow>) onWindowsChanged;
  final void Function(String) onScheduleTimezoneChanged;
  final void Function(bool) onVisibleOutsideScheduleChanged;

  const ScheduleSettingsCard({
    super.key,
    required this.scheduleType,
    required this.scheduledStartAt,
    required this.windows,
    required this.scheduleTimezone,
    required this.visibleOutsideSchedule,
    required this.onScheduleTypeChanged,
    required this.onScheduledStartAtChanged,
    required this.onWindowsChanged,
    required this.onScheduleTimezoneChanged,
    required this.onVisibleOutsideScheduleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Schedule Type
            Text('Schedule Type',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ScheduleType>(
              segments: const [
                ButtonSegment(
                  value: ScheduleType.once,
                  label: Text('One-time'),
                ),
                ButtonSegment(
                  value: ScheduleType.recurring,
                  label: Text('Recurring'),
                ),
              ],
              selected: {scheduleType},
              onSelectionChanged: (v) => onScheduleTypeChanged(v.first),
            ),
            const SizedBox(height: 16),

            if (scheduleType == ScheduleType.once)
              _OneTimeSchedule(
                scheduledStartAt: scheduledStartAt,
                scheduleTimezone: scheduleTimezone,
                onChanged: onScheduledStartAtChanged,
                onScheduleTimezoneChanged: onScheduleTimezoneChanged,
              )
            else
              _RecurringSchedule(
                windows: windows,
                scheduleTimezone: scheduleTimezone,
                onWindowsChanged: onWindowsChanged,
                onScheduleTimezoneChanged: onScheduleTimezoneChanged,
              ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Visibility outside schedule
            SwitchListTile(
              title: const Text('Hide when outside schedule'),
              subtitle: Text(visibleOutsideSchedule
                  ? 'Chat visible but paused outside schedule'
                  : 'Chat hidden until next scheduled window'),
              value: !visibleOutsideSchedule,
              onChanged: (v) => onVisibleOutsideScheduleChanged(!v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _OneTimeSchedule extends StatelessWidget {
  final DateTime scheduledStartAt;
  final String scheduleTimezone;
  final void Function(DateTime) onChanged;
  final void Function(String) onScheduleTimezoneChanged;

  const _OneTimeSchedule({
    required this.scheduledStartAt,
    required this.scheduleTimezone,
    required this.onChanged,
    required this.onScheduleTimezoneChanged,
  });

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timezone
        Text('Timezone', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _TimezoneAutocomplete(
          selectedTimezone: scheduleTimezone,
          onTimezoneChanged: onScheduleTimezoneChanged,
        ),
        const SizedBox(height: 16),

        // Date & Time
        Text('Start Date & Time',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  '${scheduledStartAt.month}/${scheduledStartAt.day}/${scheduledStartAt.year}',
                ),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: scheduledStartAt,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    onChanged(DateTime(
                      date.year,
                      date.month,
                      date.day,
                      scheduledStartAt.hour,
                      scheduledStartAt.minute,
                    ));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(
                  _formatTimeOfDay(TimeOfDay.fromDateTime(scheduledStartAt)),
                ),
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(scheduledStartAt),
                  );
                  if (time != null) {
                    onChanged(DateTime(
                      scheduledStartAt.year,
                      scheduledStartAt.month,
                      scheduledStartAt.day,
                      time.hour,
                      time.minute,
                    ));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecurringSchedule extends StatelessWidget {
  final List<state.ScheduleWindow> windows;
  final String scheduleTimezone;
  final void Function(List<state.ScheduleWindow>) onWindowsChanged;
  final void Function(String) onScheduleTimezoneChanged;

  const _RecurringSchedule({
    required this.windows,
    required this.scheduleTimezone,
    required this.onWindowsChanged,
    required this.onScheduleTimezoneChanged,
  });

  void _addWindow(BuildContext context) {
    onWindowsChanged([
      ...windows,
      state.ScheduleWindow.defaults(),
    ]);
  }

  void _removeWindow(int index) {
    if (windows.length > 1) {
      final newWindows = List<state.ScheduleWindow>.from(windows);
      newWindows.removeAt(index);
      onWindowsChanged(newWindows);
    }
  }

  void _updateWindow(int index, state.ScheduleWindow newWindow) {
    final newWindows = List<state.ScheduleWindow>.from(windows);
    newWindows[index] = newWindow;
    onWindowsChanged(newWindows);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timezone
        Text('Timezone', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _TimezoneAutocomplete(
          selectedTimezone: scheduleTimezone,
          onTimezoneChanged: onScheduleTimezoneChanged,
        ),
        const SizedBox(height: 16),

        // Schedule Windows
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Schedule Windows',
                style: Theme.of(context).textTheme.titleSmall),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Window'),
              onPressed: () => _addWindow(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Define when the chat is active. Supports overnight windows (e.g., 11pm → 1am next day).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),

        // Window List
        ...List.generate(windows.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ScheduleWindowCard(
              window: windows[index],
              index: index,
              canDelete: windows.length > 1,
              onChanged: (newWindow) => _updateWindow(index, newWindow),
              onDelete: () => _removeWindow(index),
            ),
          );
        }),
      ],
    );
  }
}

class _ScheduleWindowCard extends StatelessWidget {
  final state.ScheduleWindow window;
  final int index;
  final bool canDelete;
  final void Function(state.ScheduleWindow) onChanged;
  final VoidCallback onDelete;

  static const allDays = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday'
  ];
  static const dayLabels = {
    'sunday': 'Sun',
    'monday': 'Mon',
    'tuesday': 'Tue',
    'wednesday': 'Wed',
    'thursday': 'Thu',
    'friday': 'Fri',
    'saturday': 'Sat',
  };

  const _ScheduleWindowCard({
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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with delete button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Window ${index + 1}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove window',
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Start Day & Time
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: window.startDay,
                    decoration: const InputDecoration(
                      labelText: 'Start Day',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: allDays.map((day) {
                      return DropdownMenuItem(
                        value: day,
                        child: Text(dayLabels[day] ?? day),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        onChanged(window.copyWith(startDay: v ?? 'monday')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: window.startTime,
                      );
                      if (time != null) {
                        onChanged(window.copyWith(startTime: time));
                      }
                    },
                    child: Text(_formatTimeOfDay(window.startTime)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Arrow indicator
            Center(
              child: Icon(
                Icons.arrow_downward,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),

            // End Day & Time
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: window.endDay,
                    decoration: const InputDecoration(
                      labelText: 'End Day',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: allDays.map((day) {
                      return DropdownMenuItem(
                        value: day,
                        child: Text(dayLabels[day] ?? day),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        onChanged(window.copyWith(endDay: v ?? 'monday')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: window.endTime,
                      );
                      if (time != null) {
                        onChanged(window.copyWith(endTime: time));
                      }
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Autocomplete widget for timezone selection with search.
class _TimezoneAutocomplete extends StatefulWidget {
  final String selectedTimezone;
  final void Function(String) onTimezoneChanged;

  const _TimezoneAutocomplete({
    required this.selectedTimezone,
    required this.onTimezoneChanged,
  });

  @override
  State<_TimezoneAutocomplete> createState() => _TimezoneAutocompleteState();
}

class _TimezoneAutocompleteState extends State<_TimezoneAutocomplete> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: getTimezoneDisplayName(widget.selectedTimezone),
    );
  }

  @override
  void didUpdateWidget(_TimezoneAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTimezone != widget.selectedTimezone) {
      _controller.text = getTimezoneDisplayName(widget.selectedTimezone);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(
        text: getTimezoneDisplayName(widget.selectedTimezone),
      ),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.toLowerCase();
        if (query.isEmpty) {
          // Show first 20 common timezones when empty
          return allTimezones.take(20);
        }
        return allTimezones.where((tz) {
          final displayName = getTimezoneDisplayName(tz).toLowerCase();
          final tzLower = tz.toLowerCase();
          return displayName.contains(query) || tzLower.contains(query);
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
            hintText: 'Search timezone...',
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                controller.clear();
              },
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
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 350),
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      onSelected: (selection) {
        widget.onTimezoneChanged(selection);
      },
    );
  }
}
