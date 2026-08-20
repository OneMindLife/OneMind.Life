import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import 'wizard_common.dart';

/// Step 2 of the create chat wizard: Who Can Join?
/// A simple Public/Private toggle using two selectable cards.
class WizardStepVisibility extends StatelessWidget {
  final AccessMethod accessMethod;
  final ValueChanged<AccessMethod> onAccessMethodChanged;
  final VoidCallback onContinue;

  const WizardStepVisibility({
    super.key,
    required this.accessMethod,
    required this.onAccessMethodChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WizardStepLayout(
      icon: Icons.visibility_outlined,
      title: l10n.wizardVisibilityTitle,
      onContinue: onContinue,
      children: [
        WizardSelectCard(
          icon: Icons.public,
          title: l10n.wizardVisibilityPublicTitle,
          description: l10n.wizardVisibilityPublicDesc,
          selected: accessMethod == AccessMethod.public,
          onTap: () => onAccessMethodChanged(AccessMethod.public),
        ),
        const SizedBox(height: 16),
        WizardSelectCard(
          icon: Icons.lock_outline,
          title: l10n.wizardVisibilityPrivateTitle,
          description: l10n.wizardVisibilityPrivateDesc,
          selected: accessMethod == AccessMethod.code,
          onTap: () => onAccessMethodChanged(AccessMethod.code),
        ),
        const SizedBox(height: 16),
        WizardSelectCard(
          icon: Icons.vpn_key_outlined,
          title: l10n.wizardVisibilityPersonalCodeTitle,
          description: l10n.wizardVisibilityPersonalCodeDesc,
          selected: accessMethod == AccessMethod.personalCode,
          onTap: () => onAccessMethodChanged(AccessMethod.personalCode),
        ),
      ],
    );
  }
}
