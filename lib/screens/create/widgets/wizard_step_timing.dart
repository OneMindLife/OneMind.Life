import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Step 2 of the create chat wizard: Timing (middle step)
/// Focuses on proposing and rating phase durations.
class WizardStepTiming extends StatelessWidget {
  final TimerSettings timerSettings;
  final void Function(TimerSettings) onTimerSettingsChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const WizardStepTiming({
    super.key,
    required this.timerSettings,
    required this.onTimerSettingsChanged,
    required this.onBack,
    required this.onContinue,
  });

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
                  // Large icon as visual anchor
                  Icon(
                    Icons.timer_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    l10n.wizardStep2Title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    l10n.wizardStep2Subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Toggle for same duration
                  SwitchListTile(
                    title: Text(l10n.useSameDuration),
                    subtitle: Text(l10n.useSameDurationDesc),
                    value: timerSettings.useSameDuration,
                    contentPadding: EdgeInsets.zero,
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
                  const SizedBox(height: 16),

                  if (timerSettings.useSameDuration) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outline.withAlpha(77),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TimerPresets(
                        label: l10n.phaseDuration,
                        selected: timerSettings.proposingPreset,
                        customDuration: timerSettings.proposingPreset == 'custom'
                            ? timerSettings.proposingDuration
                            : null,
                        onChanged: (preset, duration) {
                          onTimerSettingsChanged(timerSettings.copyWith(
                            proposingPreset: preset,
                            proposingDuration: duration,
                            ratingPreset: preset,
                            ratingDuration: duration,
                          ));
                        },
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outline.withAlpha(77),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TimerPresets(
                        label: l10n.wizardProposingLabel,
                        selected: timerSettings.proposingPreset,
                        customDuration: timerSettings.proposingPreset == 'custom'
                            ? timerSettings.proposingDuration
                            : null,
                        onChanged: (preset, duration) {
                          onTimerSettingsChanged(timerSettings.copyWith(
                            proposingPreset: preset,
                            proposingDuration: duration,
                          ));
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outline.withAlpha(77),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TimerPresets(
                        label: l10n.wizardRatingLabel,
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
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Navigation buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.arrow_back, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.back),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
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
        ],
      ),
    );
  }
}
