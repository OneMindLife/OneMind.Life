import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../widgets/name_section.dart' show kDisplayNameMaxLength;
import 'wizard_common.dart';

/// Dedicated final wizard step, shown ONLY when the creator has no display
/// name yet: creating a chat auto-joins them as host, so a name is required
/// before create. Users who already have a name never see this screen — for
/// them the agents step is the last one and creates directly.
class WizardStepHostName extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onCreate;
  final bool isLoading;

  const WizardStepHostName({
    super.key,
    required this.controller,
    required this.onCreate,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final canCreate = controller.text.trim().isNotEmpty;
        return WizardStepLayout(
          icon: Icons.badge_outlined,
          title: l10n.whatsYourName,
          subtitle: l10n.nameShownToOthers,
          onContinue: canCreate ? onCreate : null,
          continueLabel: l10n.createChat,
          continueIcon: Icons.rocket_launch,
          isLoading: isLoading,
          children: [
            TextField(
              key: const Key('host-name-field'),
              controller: controller,
              maxLength: kDisplayNameMaxLength,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: l10n.enterYourName,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (controller.text.trim().isNotEmpty && !isLoading) {
                  onCreate();
                }
              },
            ),
          ],
        );
      },
    );
  }
}
