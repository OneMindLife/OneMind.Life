import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import 'email_invite_section.dart';
import 'form_inputs.dart';

/// Visibility and access settings section
class VisibilitySection extends StatelessWidget {
  final AccessMethod accessMethod;
  final List<String> inviteEmails;
  final bool requireAuth;
  final bool requireApproval;
  final void Function(AccessMethod) onAccessMethodChanged;
  final void Function(List<String>) onEmailsChanged;
  final void Function(bool) onRequireAuthChanged;
  final void Function(bool) onRequireApprovalChanged;

  const VisibilitySection({
    super.key,
    required this.accessMethod,
    required this.inviteEmails,
    required this.requireAuth,
    required this.requireApproval,
    required this.onAccessMethodChanged,
    required this.onEmailsChanged,
    required this.onRequireAuthChanged,
    required this.onRequireApprovalChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.visibility),
        const SizedBox(height: 8),
        Text(
          l10n.whoCanJoin,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _AccessMethodCard(
          method: AccessMethod.public,
          title: l10n.accessPublic,
          description: l10n.accessPublicDesc,
          icon: Icons.public,
          isSelected: accessMethod == AccessMethod.public,
          onTap: () => onAccessMethodChanged(AccessMethod.public),
        ),
        const SizedBox(height: 8),
        _AccessMethodCard(
          method: AccessMethod.code,
          title: l10n.accessCode,
          description: l10n.accessCodeDesc,
          icon: Icons.tag,
          isSelected: accessMethod == AccessMethod.code,
          onTap: () => onAccessMethodChanged(AccessMethod.code),
        ),
        const SizedBox(height: 8),
        _AccessMethodCard(
          method: AccessMethod.inviteOnly,
          title: l10n.accessEmail,
          description: l10n.accessEmailDesc,
          icon: Icons.email,
          isSelected: accessMethod == AccessMethod.inviteOnly,
          onTap: () => onAccessMethodChanged(AccessMethod.inviteOnly),
        ),
        if (accessMethod == AccessMethod.inviteOnly) ...[
          const SizedBox(height: 16),
          EmailInviteSection(
            emails: inviteEmails,
            onEmailsChanged: onEmailsChanged,
          ),
        ],
        const SizedBox(height: 16),
        // TODO: Re-enable when user authentication is implemented
        // See docs/FEATURE_REQUESTS.md - "User Authentication"
        // SwitchListTile(
        //   title: const Text('Require authentication'),
        //   subtitle: Text(requireAuth
        //       ? 'Users must sign in'
        //       : 'Anonymous users allowed'),
        //   value: requireAuth,
        //   onChanged: onRequireAuthChanged,
        // ),
        if (accessMethod != AccessMethod.public)
          SwitchListTile(
            title: Text(l10n.requireApproval),
            subtitle: Text(requireApproval
                ? l10n.hostApprovalRequired
                : l10n.instantJoin),
            value: requireApproval,
            onChanged: onRequireApprovalChanged,
          ),
      ],
    );
  }
}

class _AccessMethodCard extends StatelessWidget {
  final AccessMethod method;
  final String title;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AccessMethodCard({
    required this.method,
    required this.title,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withAlpha(50)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : null,
                        ),
                  ),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
