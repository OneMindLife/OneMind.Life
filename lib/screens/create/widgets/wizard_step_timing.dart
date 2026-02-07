import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Step 2 of the create chat wizard: Timing (final step)
/// Focuses on proposing and rating phase durations, then creates the chat.
/// Also conditionally shows host name input if not already set.
class WizardStepTiming extends StatelessWidget {
  final TimerSettings timerSettings;
  final void Function(TimerSettings) onTimerSettingsChanged;
  final TextEditingController hostNameController;
  final bool needsHostName;
  final GlobalKey<FormState> formKey;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final bool isLoading;

  const WizardStepTiming({
    super.key,
    required this.timerSettings,
    required this.onTimerSettingsChanged,
    required this.hostNameController,
    required this.needsHostName,
    required this.formKey,
    required this.onBack,
    required this.onCreate,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
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
                        // When enabling, sync rating to proposing values
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
                    // Single timer for both phases
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
                          // Update both proposing and rating together
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
                    // Proposing duration
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

                    // Rating duration
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

                  // Host name section (only if not already set)
                  if (needsHostName) ...[
                    const SizedBox(height: 24),
                    Divider(color: theme.colorScheme.outline.withAlpha(77)),
                    const SizedBox(height: 16),
                    Text(
                      l10n.wizardOneLastThing,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: hostNameController,
                      decoration: InputDecoration(
                        labelText: l10n.displayName,
                        hintText: l10n.enterYourName,
                        border: const OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.pleaseEnterYourName;
                        }
                        return null;
                      },
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
              // Back button
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : onBack,
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
              // Create button
              Expanded(
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          if (!needsHostName ||
                              (formKey.currentState?.validate() ?? false)) {
                            onCreate();
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(l10n.createChat),
                            const SizedBox(width: 8),
                            const Icon(Icons.rocket_launch, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}
