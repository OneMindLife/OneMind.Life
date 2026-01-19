import 'package:flutter/material.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Minimum to advance section
class MinimumAdvanceSection extends StatelessWidget {
  final MinimumSettings settings;
  final void Function(MinimumSettings) onChanged;

  const MinimumAdvanceSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Minimum to Advance'),
        Text(
          'If not met when timer ends, time extends automatically',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _MinimumInputCard(
          label: 'Proposing minimum',
          description: 'Number of propositions required before advancing to rating',
          value: settings.proposingMinimum,
          onChanged: (v) => onChanged(settings.copyWith(proposingMinimum: v)),
          min: 3, // Minimum 3: users can't rate own, so need 2+ visible to each
        ),
        const SizedBox(height: 12),
        _MinimumInputCard(
          label: 'Rating minimum',
          description: 'Average raters per proposition required before calculating winner',
          value: settings.ratingMinimum,
          onChanged: (v) => onChanged(settings.copyWith(ratingMinimum: v)),
          min: 2, // Minimum 2 for meaningful alignment
        ),
      ],
    );
  }
}

class _MinimumInputCard extends StatelessWidget {
  final String label;
  final String description;
  final int value;
  final void Function(int) onChanged;
  final int min;

  const _MinimumInputCard({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.min,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(100)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: NumberInput(
              label: '',
              value: value,
              onChanged: onChanged,
              min: min,
            ),
          ),
        ],
      ),
    );
  }
}
