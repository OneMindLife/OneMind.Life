import 'package:flutter/material.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Auto-advance section for early phase advancement
class AutoAdvanceSection extends StatelessWidget {
  final AutoAdvanceSettings settings;
  final void Function(AutoAdvanceSettings) onChanged;

  const AutoAdvanceSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Auto-Advance At'),
        Text(
          'Skip timer early when thresholds are reached',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Enable auto-advance (proposing)'),
          value: settings.enableProposing,
          onChanged: (v) => onChanged(settings.copyWith(enableProposing: v)),
        ),
        if (settings.enableProposing) ...[
          LabeledSlider(
            label:
                'When ${settings.proposingThresholdPercent}% of participants submit',
            value: settings.proposingThresholdPercent.toDouble(),
            onChanged: (v) =>
                onChanged(settings.copyWith(proposingThresholdPercent: v.round())),
          ),
          NumberInput(
            label: 'Minimum propositions required',
            value: settings.proposingThresholdCount,
            min: 3, // Must match proposing_minimum
            onChanged: (v) =>
                onChanged(settings.copyWith(proposingThresholdCount: v)),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Enable auto-advance (rating)'),
          value: settings.enableRating,
          onChanged: (v) => onChanged(settings.copyWith(enableRating: v)),
        ),
        if (settings.enableRating) ...[
          NumberInput(
            label: 'Minimum avg raters per proposition',
            value: settings.ratingThresholdCount,
            min: 2, // Must match rating_minimum
            onChanged: (v) =>
                onChanged(settings.copyWith(ratingThresholdCount: v)),
          ),
        ],
      ],
    );
  }
}
