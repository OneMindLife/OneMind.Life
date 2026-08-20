import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';
import 'wizard_common.dart';

/// Timing step of the create chat wizard: proposing and rating phase
/// durations. For Always-Active chats, the cadence anchor ("First deadline")
/// follows on its own dedicated step — see [WizardStepFirstDeadline] — so the
/// anchor question always knows the duration chosen here.
class WizardStepTiming extends StatelessWidget {
  final TimerSettings timerSettings;
  final void Function(TimerSettings) onTimerSettingsChanged;
  final VoidCallback onContinue;

  const WizardStepTiming({
    super.key,
    required this.timerSettings,
    required this.onTimerSettingsChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return WizardStepLayout(
      icon: Icons.timer_outlined,
      title: l10n.wizardStep2Title,
      onContinue: onContinue,
      children: [
        // Proposing duration — always shown first
        SettingTile(
          question: l10n.wizardTimingProposingQuestion,
          description: l10n.wizardTimingCurrently(formatDurationDescription(
              timerSettings.proposingPreset,
              timerSettings.proposingDuration,
              l10n)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TimerPresets(
              label: '',
              selected: timerSettings.proposingPreset,
              customDuration: timerSettings.proposingPreset == 'custom'
                  ? timerSettings.proposingDuration
                  : null,
              onChanged: (preset, duration) {
                if (timerSettings.useSameDuration) {
                  onTimerSettingsChanged(timerSettings.copyWith(
                    proposingPreset: preset,
                    proposingDuration: duration,
                    ratingPreset: preset,
                    ratingDuration: duration,
                  ));
                } else {
                  onTimerSettingsChanged(timerSettings.copyWith(
                    proposingPreset: preset,
                    proposingDuration: duration,
                  ));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Same duration toggle
        SettingTile(
          question: l10n.wizardTimingSameDurationQuestion,
          description: timerSettings.useSameDuration
              ? l10n.wizardTimingSameDurationYes
              : l10n.wizardTimingSameDurationNo,
          trailing: Switch(
            value: timerSettings.useSameDuration,
            onChanged: (value) {
              if (value) {
                onTimerSettingsChanged(timerSettings.copyWith(
                  useSameDuration: true,
                  ratingPreset: timerSettings.proposingPreset,
                  ratingDuration: timerSettings.proposingDuration,
                ));
              } else {
                onTimerSettingsChanged(
                    timerSettings.copyWith(useSameDuration: false));
              }
            },
          ),
        ),

        // Rating duration — only shown when different from proposing
        if (!timerSettings.useSameDuration) ...[
          const SizedBox(height: 8),
          SettingTile(
            question: l10n.wizardTimingRatingQuestion,
            description: l10n.wizardTimingCurrently(formatDurationDescription(
                timerSettings.ratingPreset,
                timerSettings.ratingDuration,
                l10n)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TimerPresets(
                label: '',
                selected: timerSettings.ratingPreset,
                customDuration: timerSettings.ratingPreset == 'custom'
                    ? timerSettings.ratingDuration
                    : null,
                onChanged: (preset, duration) {
                  onTimerSettingsChanged(timerSettings.copyWith(
                    ratingPreset: preset,
                    ratingDuration: duration,
                  ));
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
