import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'agent_section.dart';

/// Step 3 of the create chat wizard: AI Agents.
/// Allows users to configure AI agent participation.
class WizardStepAgents extends StatelessWidget {
  final AgentSettings agentSettings;
  final void Function(AgentSettings) onAgentSettingsChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onCreate;
  final bool needsHostName;
  final bool isLoading;

  const WizardStepAgents({
    super.key,
    required this.agentSettings,
    required this.onAgentSettingsChanged,
    required this.onBack,
    required this.onContinue,
    required this.onCreate,
    required this.needsHostName,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isFinalStep = !needsHostName;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AI Agents',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  AgentSection(
                    settings: agentSettings,
                    onChanged: onAgentSettingsChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : onBack,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.arrow_back, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.back),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : isFinalStep
                          ? onCreate
                          : onContinue,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(isFinalStep
                                ? l10n.createChat
                                : l10n.continue_),
                            const SizedBox(width: 8),
                            Icon(
                              isFinalStep
                                  ? Icons.rocket_launch
                                  : Icons.arrow_forward,
                              size: 18,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
