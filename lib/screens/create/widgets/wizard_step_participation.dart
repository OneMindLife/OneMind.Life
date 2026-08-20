import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'wizard_common.dart';

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

    return WizardStepLayout(
      icon: Icons.group_outlined,
      title: l10n.wizardParticipationTitle,
      subtitle: l10n.wizardParticipationSubtitle,
      onContinue: onContinue,
      children: [
        WizardToggleCard(
          icon: Icons.edit_note,
          title: l10n.wizardAllowSkipProposingTitle,
          description: skipSettings.allowSkipProposing
              ? l10n.wizardAllowSkipProposingOnDesc
              : l10n.wizardAllowSkipProposingOffDesc,
          value: skipSettings.allowSkipProposing,
          onChanged: (value) {
            onSkipSettingsChanged(
              skipSettings.copyWith(allowSkipProposing: value),
            );
          },
        ),
        const SizedBox(height: 16),
        WizardToggleCard(
          icon: Icons.how_to_vote_outlined,
          title: l10n.wizardAllowSkipRatingTitle,
          description: skipSettings.allowSkipRating
              ? l10n.wizardAllowSkipRatingOnDesc
              : l10n.wizardAllowSkipRatingOffDesc,
          value: skipSettings.allowSkipRating,
          onChanged: (value) {
            onSkipSettingsChanged(
              skipSettings.copyWith(allowSkipRating: value),
            );
          },
        ),
      ],
    );
  }
}
