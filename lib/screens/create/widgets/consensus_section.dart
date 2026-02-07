import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Consensus settings section
class ConsensusSection extends StatelessWidget {
  final ConsensusSettings settings;
  final void Function(ConsensusSettings) onChanged;

  const ConsensusSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.consensusSettings),
        // Confirmation rounds hidden - default to 2
        // NumberInput(
        //   label: l10n.confirmationRounds,
        //   value: settings.confirmationRoundsRequired,
        //   onChanged: (v) =>
        //       onChanged(settings.copyWith(confirmationRoundsRequired: v)),
        //   min: 1,
        //   max: 2,
        // ),
        // Padding(
        //   padding: const EdgeInsets.only(left: 16, top: 4),
        //   child: Text(
        //     settings.confirmationRoundsRequired == 1
        //         ? l10n.firstWinnerConsensus
        //         : l10n.mustWinConsecutive(settings.confirmationRoundsRequired),
        //     style: Theme.of(context).textTheme.bodySmall,
        //   ),
        // ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: Text(l10n.showFullResults),
          subtitle: Text(settings.showPreviousResults
              ? l10n.seeAllPropositions
              : l10n.seeWinningOnly),
          value: settings.showPreviousResults,
          onChanged: (v) =>
              onChanged(settings.copyWith(showPreviousResults: v)),
        ),
      ],
    );
  }
}
