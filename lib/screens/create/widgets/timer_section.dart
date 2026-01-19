import 'package:flutter/material.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Timer section for proposing and rating durations
class TimerSection extends StatelessWidget {
  final TimerSettings settings;
  final void Function(TimerSettings) onChanged;

  const TimerSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Timers'),
        const SizedBox(height: 16),
        TimerPresets(
          label: 'Proposing',
          selected: settings.proposingPreset,
          customDuration: settings.proposingPreset == 'custom'
              ? settings.proposingDuration
              : null,
          onChanged: (preset, duration) {
            onChanged(settings.copyWith(
              proposingPreset: preset,
              proposingDuration: duration,
            ));
          },
        ),
        const SizedBox(height: 16),
        TimerPresets(
          label: 'Rating',
          selected: settings.ratingPreset,
          customDuration: settings.ratingPreset == 'custom'
              ? settings.ratingDuration
              : null,
          onChanged: (preset, duration) {
            onChanged(settings.copyWith(
              ratingPreset: preset,
              ratingDuration: duration,
            ));
          },
        ),
      ],
    );
  }
}
