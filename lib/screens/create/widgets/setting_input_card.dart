import 'package:flutter/material.dart';
import 'form_inputs.dart';

/// Reusable card for numeric settings with label and description.
/// Used in both Required Participation and End Phase Early sections.
class SettingInputCard extends StatelessWidget {
  final String label;
  final String description;
  final int value;
  final void Function(int) onChanged;
  final int min;
  final int max;

  const SettingInputCard({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.min,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha(100),
        ),
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
            width: 130,
            child: NumberInput(
              label: '',
              value: value,
              onChanged: onChanged,
              min: min,
              max: max,
            ),
          ),
        ],
      ),
    );
  }
}
