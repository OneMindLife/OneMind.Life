import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'form_inputs.dart';

/// Proposition limits section
class PropositionLimitsSection extends StatelessWidget {
  final int propositionsPerUser;
  final void Function(int) onChanged;

  const PropositionLimitsSection({
    super.key,
    required this.propositionsPerUser,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.propositionLimits),
        const SizedBox(height: 16),
        NumberInput(
          label: l10n.propositionsPerUser,
          value: propositionsPerUser,
          onChanged: onChanged,
          min: 1,
          max: 20,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 4),
          child: Text(
            propositionsPerUser == 1
                ? l10n.onePropositionPerRound
                : l10n.nPropositionsPerRound(propositionsPerUser),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
