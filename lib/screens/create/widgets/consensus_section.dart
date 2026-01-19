import 'package:flutter/material.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Consensus Settings'),
        const SizedBox(height: 16),
        NumberInput(
          label: 'Confirmation rounds',
          value: settings.confirmationRoundsRequired,
          onChanged: (v) =>
              onChanged(settings.copyWith(confirmationRoundsRequired: v)),
          min: 1,
          max: 2, // Limited to 1-2 for practical consensus
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 4),
          child: Text(
            settings.confirmationRoundsRequired == 1
                ? 'First winner reaches consensus immediately'
                : 'Same proposition must win ${settings.confirmationRoundsRequired} rounds in a row',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Show full results from past rounds'),
          subtitle: Text(settings.showPreviousResults
              ? 'Users see all propositions and ratings'
              : 'Users only see the winning proposition'),
          value: settings.showPreviousResults,
          onChanged: (v) =>
              onChanged(settings.copyWith(showPreviousResults: v)),
        ),
      ],
    );
  }
}
