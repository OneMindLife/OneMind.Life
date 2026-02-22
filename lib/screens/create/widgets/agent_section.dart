import 'package:flutter/material.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';

/// Agent configuration section for the create chat screen.
/// Allows users to enable AI agents, set count, and configure personalities.
class AgentSection extends StatelessWidget {
  final AgentSettings settings;
  final void Function(AgentSettings) onChanged;

  const AgentSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('AI Agents'),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Enable AI agents'),
          subtitle: const Text(
            'AI agents propose ideas and rate alongside humans',
          ),
          value: settings.enabled,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => onChanged(settings.copyWith(enabled: v)),
        ),
        if (settings.enabled) ...[
          const SizedBox(height: 16),
          NumberInput(
            label: 'Number of agents',
            value: settings.proposingAgentCount,
            onChanged: (v) => onChanged(settings.withCount(v)),
            min: 1,
            max: 5,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Customize agents individually'),
            subtitle: const Text(
              'Set name and personality per agent',
            ),
            value: settings.customizeIndividually,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) =>
                onChanged(settings.copyWith(customizeIndividually: v)),
          ),
          const SizedBox(height: 8),
          if (!settings.customizeIndividually) ...[
            TextFormField(
              key: const Key('agent_shared_instructions'),
              initialValue: settings.sharedInstructions,
              decoration: const InputDecoration(
                labelText: 'Instructions for all agents (optional)',
                hintText: 'e.g., Focus on practical solutions...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              onChanged: (v) =>
                  onChanged(settings.copyWith(sharedInstructions: v)),
            ),
          ] else ...[
            for (int i = 0; i < settings.agents.length; i++) ...[
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        key: Key('agent_name_$i'),
                        initialValue: settings.agents[i].name,
                        decoration: InputDecoration(
                          labelText: 'Agent ${i + 1} name',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final updated = List<AgentConfig>.from(settings.agents);
                          updated[i] = updated[i].copyWith(name: v);
                          onChanged(settings.copyWith(agents: updated));
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: Key('agent_personality_$i'),
                        initialValue: settings.agents[i].personality,
                        decoration: const InputDecoration(
                          labelText: 'Personality (optional)',
                          hintText: 'Leave empty for auto-assigned perspective',
                          border: OutlineInputBorder(),
                          isDense: true,
                          alignLabelWithHint: true,
                        ),
                        maxLines: 2,
                        onChanged: (v) {
                          final updated = List<AgentConfig>.from(settings.agents);
                          updated[i] = updated[i].copyWith(personality: v);
                          onChanged(settings.copyWith(agents: updated));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (settings.sharedInstructions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Shared instructions also apply to all agents',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Same agent count for both phases'),
            value: settings.useSameCount,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) {
              if (v) {
                onChanged(settings.copyWith(
                  useSameCount: true,
                  ratingAgentCount: settings.proposingAgentCount,
                ));
              } else {
                onChanged(settings.copyWith(useSameCount: false));
              }
            },
          ),
          if (!settings.useSameCount) ...[
            const SizedBox(height: 8),
            NumberInput(
              label: 'Rating agents',
              value: settings.ratingAgentCount,
              onChanged: (v) =>
                  onChanged(settings.copyWith(ratingAgentCount: v)),
              min: 1,
              max: 5,
            ),
          ],
        ],
      ],
    );
  }
}
