import 'package:flutter/material.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// AI participant section
class AISection extends StatelessWidget {
  final AISettings settings;
  final void Function(AISettings) onChanged;

  const AISection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('AI Participant'),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Enable OneMind AI'),
          value: settings.enabled,
          onChanged: (v) => onChanged(settings.copyWith(enabled: v)),
        ),
        if (settings.enabled)
          NumberInput(
            label: 'AI propositions per round',
            value: settings.propositionCount,
            onChanged: (v) => onChanged(settings.copyWith(propositionCount: v)),
            min: 1,
            max: 10,
          ),
      ],
    );
  }
}
