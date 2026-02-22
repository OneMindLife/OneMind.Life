import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'agent_section.dart';

/// Step 3 of the create chat wizard: AI Agents (final step)
/// Allows users to configure AI agent participation, then creates the chat.
class WizardStepAgents extends StatelessWidget {
  final AgentSettings agentSettings;
  final void Function(AgentSettings) onAgentSettingsChanged;
  final TextEditingController hostNameController;
  final bool needsHostName;
  final GlobalKey<FormState> formKey;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final bool isLoading;

  const WizardStepAgents({
    super.key,
    required this.agentSettings,
    required this.onAgentSettingsChanged,
    required this.hostNameController,
    required this.needsHostName,
    required this.formKey,
    required this.onBack,
    required this.onCreate,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Large icon as visual anchor
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      'AI Agents',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      'Add AI agents to propose ideas and rate alongside humans',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    AgentSection(
                      settings: agentSettings,
                      onChanged: onAgentSettingsChanged,
                    ),

                    // Host name section (only if not already set)
                    if (needsHostName) ...[
                      const SizedBox(height: 24),
                      Divider(color: theme.colorScheme.outline.withAlpha(77)),
                      const SizedBox(height: 16),
                      Text(
                        l10n.wizardOneLastThing,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: hostNameController,
                        decoration: InputDecoration(
                          labelText: l10n.displayName,
                          hintText: l10n.enterYourName,
                          border: const OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.pleaseEnterYourName;
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Navigation buttons
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
                        : () {
                            if (!needsHostName ||
                                (formKey.currentState?.validate() ?? false)) {
                              onCreate();
                            }
                          },
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
                              Text(l10n.createChat),
                              const SizedBox(width: 8),
                              const Icon(Icons.rocket_launch, size: 18),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
