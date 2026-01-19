import 'package:flutter/material.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Adaptive duration section
class AdaptiveDurationSection extends StatelessWidget {
  final AdaptiveDurationSettings settings;
  final void Function(AdaptiveDurationSettings) onChanged;

  const AdaptiveDurationSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Adaptive Duration'),
        Text(
          'Auto-adjust phase duration based on participation',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Enable adaptive duration'),
          subtitle: Text(settings.enabled
              ? 'Duration adjusts based on participation'
              : 'Fixed phase durations'),
          value: settings.enabled,
          onChanged: (v) => onChanged(settings.copyWith(enabled: v)),
        ),
        if (settings.enabled) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              'Uses early advance thresholds to determine participation',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          LabeledSlider(
            label: 'Adjustment: ${settings.adjustmentPercent}%',
            value: settings.adjustmentPercent.toDouble(),
            onChanged: (v) =>
                onChanged(settings.copyWith(adjustmentPercent: v.round())),
            min: 1,
            max: 50,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DurationDropdown(
                  label: 'Minimum duration',
                  value: settings.minDurationSeconds,
                  onChanged: (v) =>
                      onChanged(settings.copyWith(minDurationSeconds: v)),
                  isMin: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DurationDropdown(
                  label: 'Maximum duration',
                  value: settings.maxDurationSeconds,
                  onChanged: (v) =>
                      onChanged(settings.copyWith(maxDurationSeconds: v)),
                  isMin: false,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
