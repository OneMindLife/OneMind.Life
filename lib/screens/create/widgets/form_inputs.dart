import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';

/// A number input with increment/decrement buttons.
class NumberInput extends StatelessWidget {
  final String label;
  final int value;
  final void Function(int) onChanged;
  final int min;
  final int max;

  const NumberInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty) Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove, size: 20),
          iconSize: 20,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add, size: 20),
          iconSize: 20,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// A slider with a label.
class LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final void Function(double) onChanged;
  final double min;
  final double max;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    final divisions = ((max - min) / 5).round().clamp(1, 50);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A dropdown for selecting duration values.
class DurationDropdown extends StatelessWidget {
  final String label;
  final int value;
  final void Function(int) onChanged;
  final bool isMin;

  const DurationDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isMin,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = isMin
        ? [
            // Minimum 60s due to cron job granularity (runs every minute)
            (60, l10n.duration1min),
            (120, l10n.duration2min),
            (300, l10n.preset5min),
            (600, l10n.duration10min),
            (1800, l10n.preset30min),
            (3600, l10n.preset1hour),
          ]
        : [
            (3600, l10n.preset1hour),
            (7200, l10n.duration2hours),
            (14400, l10n.duration4hours),
            (28800, l10n.duration8hours),
            (43200, l10n.duration12hours),
            (86400, l10n.preset1day),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          initialValue: options.any((o) => o.$1 == value) ? value : options.first.$1,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: options
              .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
              .toList(),
          onChanged: (v) => onChanged(v ?? options.first.$1),
        ),
      ],
    );
  }
}

/// A section header text widget.
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

/// A reusable question-answer tile for wizard settings.
///
/// Renders a bold question, optional description, and either an inline
/// [trailing] control (switch, stepper) or a block-level [child] (text field)
/// shown below the question.
class SettingTile extends StatelessWidget {
  final String question;
  final String? description;
  final Widget? trailing;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  const SettingTile({
    super.key,
    required this.question,
    this.description,
    this.trailing,
    this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  question,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(
              description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (child != null) ...[
            const SizedBox(height: 8),
            child!,
          ],
        ],
      ),
    );
  }
}

/// Returns a human-readable label for a timer preset key.
String formatPresetLabel(String preset, AppLocalizations l10n) {
  switch (preset) {
    case '5min':
      return l10n.preset5min;
    case '30min':
      return l10n.preset30min;
    case '1hour':
      return l10n.preset1hour;
    case '1day':
      return l10n.preset1day;
    case 'custom':
      return l10n.presetCustom;
    default:
      return preset;
  }
}

/// Returns a description string for a duration, including custom formatting.
String formatDurationDescription(
    String preset, int durationSeconds, AppLocalizations l10n) {
  if (preset == 'custom') {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }
  return formatPresetLabel(preset, l10n);
}

/// Timer preset chips for selecting duration.
class TimerPresets extends StatefulWidget {
  final String label;
  final String selected;
  final int? customDuration; // Current custom duration in seconds (for restoring state)
  final void Function(String preset, int duration) onChanged;

  static const Map<String, int> presets = {
    '5min': 300,
    '30min': 1800,
    '1hour': 3600,
    '1day': 86400,
    'custom': 0, // Placeholder, actual value comes from inputs
  };

  const TimerPresets({
    super.key,
    required this.label,
    required this.selected,
    this.customDuration,
    required this.onChanged,
  });

  @override
  State<TimerPresets> createState() => _TimerPresetsState();
}

class _TimerPresetsState extends State<TimerPresets> {
  late TextEditingController _hoursController;
  late TextEditingController _minutesController;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    // Initialize from customDuration if available
    final duration = widget.customDuration ?? 300; // Default 5 min
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    _hoursController = TextEditingController(text: hours.toString());
    _minutesController = TextEditingController(text: minutes.toString());
  }

  @override
  void didUpdateWidget(TimerPresets oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers if custom duration changed externally
    if (widget.customDuration != oldWidget.customDuration &&
        widget.customDuration != null) {
      final hours = widget.customDuration! ~/ 3600;
      final minutes = (widget.customDuration! % 3600) ~/ 60;
      if (_hoursController.text != hours.toString()) {
        _hoursController.text = hours.toString();
      }
      if (_minutesController.text != minutes.toString()) {
        _minutesController.text = minutes.toString();
      }
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  String _formatPreset(String preset, AppLocalizations l10n) {
    switch (preset) {
      case '5min':
        return l10n.preset5min;
      case '30min':
        return l10n.preset30min;
      case '1hour':
        return l10n.preset1hour;
      case '1day':
        return l10n.preset1day;
      case 'custom':
        return l10n.presetCustom;
      default:
        return preset;
    }
  }

  void _onCustomDurationChanged() {
    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;

    // Clamp values
    final clampedHours = hours.clamp(0, 24);
    final clampedMinutes = minutes.clamp(0, 59);

    // Calculate total seconds (max 24 hours = 86400 seconds)
    var totalSeconds = (clampedHours * 3600) + (clampedMinutes * 60);

    // Enforce min 1 minute, max 24 hours
    totalSeconds = totalSeconds.clamp(60, 86400);

    widget.onChanged('custom', totalSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isCustomSelected = widget.selected == 'custom';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(widget.label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          children: TimerPresets.presets.keys.map((preset) {
            final isSelected = widget.selected == preset;
            return ChoiceChip(
              label: Text(_formatPreset(preset, l10n)),
              selected: isSelected,
              onSelected: (_) {
                if (preset == 'custom') {
                  // When selecting custom, use current input values
                  _onCustomDurationChanged();
                } else {
                  widget.onChanged(preset, TimerPresets.presets[preset]!);
                }
              },
            );
          }).toList(),
        ),
        // Show hour/minute inputs when custom is selected
        if (isCustomSelected) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _hoursController,
                  decoration: InputDecoration(
                    labelText: l10n.hours,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onCustomDurationChanged(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _minutesController,
                  decoration: InputDecoration(
                    labelText: l10n.minutes,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onCustomDurationChanged(),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.max24h,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
