import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'wizard_common.dart';

/// Wizard step for choosing how a winning idea gets locked into the chat:
/// Instant (1 round) vs Convergence (2 rounds in a row).
class WizardStepConvergence extends StatelessWidget {
  final ConsensusSettings consensusSettings;
  final void Function(ConsensusSettings) onConsensusSettingsChanged;
  final VoidCallback onContinue;

  /// 'grid' (0-100 placement) or 'matches' (pairwise).
  final String ratingMode;
  final void Function(String) onRatingModeChanged;

  /// 'winner_only' (single-elimination bracket) or 'full_rank' (Swiss passes).
  /// Only meaningful when ratingMode == 'matches'.
  final String matchObjective;
  final void Function(String) onMatchObjectiveChanged;

  const WizardStepConvergence({
    super.key,
    required this.consensusSettings,
    required this.onConsensusSettingsChanged,
    required this.onContinue,
    required this.ratingMode,
    required this.onRatingModeChanged,
    required this.matchObjective,
    required this.onMatchObjectiveChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isInstant = consensusSettings.confirmationRoundsRequired == 1;
    final isGrid = ratingMode == 'grid';

    return WizardStepLayout(
      icon: Icons.center_focus_strong_outlined,
      title: l10n.consensus,
      subtitle: l10n.convergenceStepSubtitle,
      onContinue: onContinue,
      children: [
        WizardSelectCard(
          icon: Icons.bolt_outlined,
          title: l10n.instantMode,
          description: l10n.firstWinnerConsensus,
          selected: isInstant,
          onTap: () => onConsensusSettingsChanged(
            consensusSettings.copyWith(confirmationRoundsRequired: 1),
          ),
        ),
        const SizedBox(height: 16),
        WizardSelectCard(
          icon: Icons.done_all,
          title: l10n.consensus,
          description: l10n.mustWinConsecutive(2),
          selected: !isInstant,
          onTap: () => onConsensusSettingsChanged(
            consensusSettings.copyWith(confirmationRoundsRequired: 2),
          ),
        ),
        const SizedBox(height: 24),
        WizardSectionLabel(l10n.wizardVotingStyleLabel),
        const SizedBox(height: 12),
        WizardSelectCard(
          icon: Icons.compare_arrows,
          title: l10n.wizardVotingMatchesTitle,
          description: l10n.wizardVotingMatchesDesc,
          selected: !isGrid,
          onTap: () => onRatingModeChanged('matches'),
        ),
        const SizedBox(height: 16),
        WizardSelectCard(
          icon: Icons.grid_view_outlined,
          title: l10n.wizardVotingGridTitle,
          description: l10n.wizardVotingGridDesc,
          selected: isGrid,
          onTap: () => onRatingModeChanged('grid'),
        ),
        if (!isGrid) ...[
          const SizedBox(height: 24),
          WizardSectionLabel(l10n.wizardMatchObjectiveLabel),
          const SizedBox(height: 12),
          WizardSelectCard(
            icon: Icons.emoji_events_outlined,
            title: l10n.wizardMatchWinnerTitle,
            description: l10n.wizardMatchWinnerDesc,
            selected: matchObjective != 'full_rank',
            onTap: () => onMatchObjectiveChanged('winner_only'),
          ),
          const SizedBox(height: 16),
          WizardSelectCard(
            icon: Icons.format_list_numbered,
            title: l10n.wizardMatchFullRankTitle,
            description: l10n.wizardMatchFullRankDesc,
            selected: matchObjective == 'full_rank',
            onTap: () => onMatchObjectiveChanged('full_rank'),
          ),
        ],
      ],
    );
  }
}
