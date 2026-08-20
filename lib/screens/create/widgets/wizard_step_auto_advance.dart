import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart' as state;
import 'wizard_common.dart';

/// Wizard step: enable/disable early (auto) advance, per phase.
///
/// When ON, that phase ends early once everyone has participated. When OFF
/// (the default), the phase runs for its full configured time — which is
/// required for a fixed cadence (e.g. 12h phases that must land on set
/// times); auto-advance would otherwise flip the phase the moment the last
/// person acted and break the rhythm.
class WizardStepAutoAdvance extends StatelessWidget {
  final state.AutoAdvanceSettings autoAdvanceSettings;
  final void Function(state.AutoAdvanceSettings) onAutoAdvanceSettingsChanged;
  final VoidCallback onContinue;

  const WizardStepAutoAdvance({
    super.key,
    required this.autoAdvanceSettings,
    required this.onAutoAdvanceSettingsChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WizardStepLayout(
      icon: Icons.fast_forward,
      title: l10n.wizardAutoAdvanceTitle,
      subtitle: l10n.wizardAutoAdvanceDesc,
      onContinue: onContinue,
      children: [
        WizardToggleCard(
          icon: Icons.edit_note,
          title: l10n.wizardAutoAdvanceProposingTitle,
          description: autoAdvanceSettings.enableProposing
              ? l10n.wizardAutoAdvanceProposingOnDesc
              : l10n.wizardAutoAdvanceProposingOffDesc,
          value: autoAdvanceSettings.enableProposing,
          onChanged: (v) => onAutoAdvanceSettingsChanged(
            autoAdvanceSettings.copyWith(enableProposing: v),
          ),
        ),
        const SizedBox(height: 16),
        WizardToggleCard(
          icon: Icons.how_to_vote_outlined,
          title: l10n.wizardAutoAdvanceRatingTitle,
          description: autoAdvanceSettings.enableRating
              ? l10n.wizardAutoAdvanceRatingOnDesc
              : l10n.wizardAutoAdvanceRatingOffDesc,
          value: autoAdvanceSettings.enableRating,
          onChanged: (v) => onAutoAdvanceSettingsChanged(
            autoAdvanceSettings.copyWith(enableRating: v),
          ),
        ),
      ],
    );
  }
}
