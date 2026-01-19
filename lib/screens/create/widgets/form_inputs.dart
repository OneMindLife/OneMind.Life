import 'package:flutter/material.dart';

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
    final options = isMin
        ? [
            // Minimum 60s due to cron job granularity (runs every minute)
            (60, '1 min'),
            (120, '2 min'),
            (300, '5 min'),
            (600, '10 min'),
            (1800, '30 min'),
            (3600, '1 hour'),
          ]
        : [
            (3600, '1 hour'),
            (7200, '2 hours'),
            (14400, '4 hours'),
            (28800, '8 hours'),
            (43200, '12 hours'),
            (86400, '1 day'),
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

  String _formatPreset(String preset) {
    switch (preset) {
      case '5min':
        return '5 min';
      case '30min':
        return '30 min';
      case '1hour':
        return '1 hour';
      case '1day':
        return '1 day';
      case 'custom':
        return 'Custom';
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
    final isCustomSelected = widget.selected == 'custom';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: TimerPresets.presets.keys.map((preset) {
            final isSelected = widget.selected == preset;
            return ChoiceChip(
              label: Text(_formatPreset(preset)),
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
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _onCustomDurationChanged(),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '(max 24h)',
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
