import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';

/// Wizard step for configuring skip behavior during proposing and rating phases.
class WizardStepParticipation extends StatelessWidget {
  final SkipSettings skipSettings;
  final void Function(SkipSettings) onSkipSettingsChanged;
  final VoidCallback onContinue;

  const WizardStepParticipation({
    super.key,
    required this.skipSettings,
    required this.onSkipSettingsChanged,
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
                  Icon(
                    Icons.group_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Participation',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose whether participants can skip phases',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Allow skip proposing toggle
                  _SkipToggleCard(
                    icon: Icons.edit_note,
                    title: 'Allow skip proposing',
                    description: skipSettings.allowSkipProposing
                        ? 'Participants can skip submitting an idea'
                        : 'Everyone must submit an idea',
                    value: skipSettings.allowSkipProposing,
                    onChanged: (value) {
                      onSkipSettingsChanged(
                        skipSettings.copyWith(allowSkipProposing: value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Allow skip rating toggle
                  _SkipToggleCard(
                    icon: Icons.how_to_vote_outlined,
                    title: 'Allow skip rating',
                    description: skipSettings.allowSkipRating
                        ? 'Participants can skip rating ideas'
                        : 'Everyone must rate ideas',
                    value: skipSettings.allowSkipRating,
                    onChanged: (value) {
                      onSkipSettingsChanged(
                        skipSettings.copyWith(allowSkipRating: value),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Navigation button
          SizedBox(
            width: double.infinity,
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
    );
  }
}

class _SkipToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SkipToggleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withAlpha(77),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
