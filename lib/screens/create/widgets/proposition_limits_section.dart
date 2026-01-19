import 'package:flutter/material.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Proposition Limits'),
        const SizedBox(height: 16),
        NumberInput(
          label: 'Propositions per user',
          value: propositionsPerUser,
          onChanged: onChanged,
          min: 1,
          max: 20,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 4),
          child: Text(
            propositionsPerUser == 1
                ? 'Each user can submit 1 proposition per round'
                : 'Each user can submit up to $propositionsPerUser propositions per round',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
