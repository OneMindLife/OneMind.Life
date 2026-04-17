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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(settings.enabled ? 'Yes' : 'No'),
          value: settings.enabled,
          onChanged: (v) => onChanged(settings.copyWith(enabled: v)),
        ),
        if (settings.enabled) ...[
          const Divider(),
          SettingTile(
            question: 'Should agents also rate?',
            description: settings.agentsAlsoRate
                ? 'Yes, agents rate alongside humans'
                : 'No, agents only propose ideas',
            trailing: Switch(
              value: settings.agentsAlsoRate,
              onChanged: (v) =>
                  onChanged(settings.copyWith(agentsAlsoRate: v)),
            ),
          ),
          SettingTile(
            question: 'How many agents?',
            description: '${settings.agentCount} ${settings.agentCount == 1 ? 'agent' : 'agents'} will participate',
            trailing: NumberInput(
              label: '',
              value: settings.agentCount,
              onChanged: (v) => onChanged(settings.withCount(v)),
              min: 1,
              max: 5,
            ),
          ),
          SettingTile(
            question: 'Customize agents?',
            description: settings.customizeAgents
                ? 'Yes, configure instructions or personalities'
                : 'No, use auto-generated agents',
            trailing: Switch(
              value: settings.customizeAgents,
              onChanged: (v) => onChanged(settings.copyWith(
                customizeAgents: v,
                customizeIndividually:
                    v ? settings.customizeIndividually : false,
              )),
            ),
          ),
          if (settings.customizeAgents) ...[
            SettingTile(
              question: 'Customize each agent separately?',
              description: settings.customizeIndividually
                  ? 'Yes, set name and personality per agent'
                  : 'No, use shared instructions for all',
              trailing: Switch(
                value: settings.customizeIndividually,
                onChanged: (v) =>
                    onChanged(settings.copyWith(customizeIndividually: v)),
              ),
            ),
            const SizedBox(height: 8),
            if (!settings.customizeIndividually) ...[
              TextFormField(
                key: const Key('agent_shared_instructions'),
                initialValue: settings.sharedInstructions,
                decoration: InputDecoration(
                  hintText:
                      'e.g., Make agents focus on practical solutions...',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
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
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            final updated =
                                List<AgentConfig>.from(settings.agents);
                            updated[i] = updated[i].copyWith(name: v);
                            onChanged(settings.copyWith(agents: updated));
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: Key('agent_personality_$i'),
                          initialValue: settings.agents[i].personality,
                          decoration: InputDecoration(
                            labelText: 'Personality (optional)',
                            hintText:
                                'Leave empty for auto-assigned perspective',
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                            alignLabelWithHint: true,
                          ),
                          maxLines: 2,
                          onChanged: (v) {
                            final updated =
                                List<AgentConfig>.from(settings.agents);
                            updated[i] =
                                updated[i].copyWith(personality: v);
                            onChanged(settings.copyWith(agents: updated));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ],
      ],
    );
  }
}
