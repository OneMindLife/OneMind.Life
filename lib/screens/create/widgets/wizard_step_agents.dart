import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'agent_section.dart';
import 'wizard_common.dart';

/// AI Agents step of the create chat wizard.
///
/// Normally the final step (Create Chat). When the creator has no display
/// name yet, a dedicated host-name step follows instead — see
/// [WizardStepHostName] — and this step's button becomes Continue.
class WizardStepAgents extends StatelessWidget {
  final AgentSettings agentSettings;
  final void Function(AgentSettings) onAgentSettingsChanged;
  final VoidCallback onContinue;
  final VoidCallback onCreate;
  final bool isFinalStep;
  final bool isLoading;

  const WizardStepAgents({
    super.key,
    required this.agentSettings,
    required this.onAgentSettingsChanged,
    required this.onContinue,
    required this.onCreate,
    required this.isFinalStep,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WizardStepLayout(
      icon: Icons.smart_toy_outlined,
      title: l10n.wizardAgentsTitle,
      onContinue: isFinalStep ? onCreate : onContinue,
      continueLabel: isFinalStep ? l10n.createChat : null,
      continueIcon: isFinalStep ? Icons.rocket_launch : Icons.arrow_forward,
      isLoading: isLoading,
      children: [
        AgentSection(
          settings: agentSettings,
          onChanged: onAgentSettingsChanged,
        ),
      ],
    );
  }
}
