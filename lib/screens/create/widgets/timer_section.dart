import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.timers),
        const SizedBox(height: 16),
        // Toggle for same duration
        SwitchListTile(
          title: Text(l10n.useSameDuration),
          subtitle: Text(l10n.useSameDurationDesc),
          value: settings.useSameDuration,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            if (value) {
              // When enabling, sync rating to proposing values
              onChanged(settings.copyWith(
                useSameDuration: true,
                ratingPreset: settings.proposingPreset,
                ratingDuration: settings.proposingDuration,
              ));
            } else {
              onChanged(settings.copyWith(useSameDuration: false));
            }
          },
        ),
        const SizedBox(height: 16),
        if (settings.useSameDuration) ...[
          // Single timer for both phases
          TimerPresets(
            label: l10n.phaseDuration,
            selected: settings.proposingPreset,
            customDuration: settings.proposingPreset == 'custom'
                ? settings.proposingDuration
                : null,
            onChanged: (preset, duration) {
              // Update both proposing and rating together
              onChanged(settings.copyWith(
                proposingPreset: preset,
                proposingDuration: duration,
                ratingPreset: preset,
                ratingDuration: duration,
              ));
            },
          ),
        ] else ...[
          // Separate timers for each phase
          TimerPresets(
            label: l10n.proposing,
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
            label: l10n.rating,
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
      ],
    );
  }
}
