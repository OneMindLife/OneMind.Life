import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../tutorial_data.dart';

/// Welcome panel with template selection — the first screen of the tutorial
class TutorialIntroPanel extends ConsumerWidget {
  final void Function(String templateKey) onSelect;
  final VoidCallback onSkip;

  const TutorialIntroPanel({
    super.key,
    required this.onSelect,
    required this.onSkip,
  });

  String _getTemplateName(String key, AppLocalizations l10n) {
    switch (key) {
      case 'personal':
        return l10n.tutorialTemplatePersonal;
      case 'family':
        return l10n.tutorialTemplateFamily;
      case 'community':
        return l10n.tutorialTemplateCommunity;
      case 'workplace':
        return l10n.tutorialTemplateWorkplace;
      case 'government':
        return l10n.tutorialTemplateGovernment;
      case 'world':
        return l10n.tutorialTemplateWorld;
      default:
        return key;
    }
  }

  String _getTemplateDescription(String key, AppLocalizations l10n) {
    switch (key) {
      case 'personal':
        return l10n.tutorialTemplatePersonalDesc;
      case 'family':
        return l10n.tutorialTemplateFamilyDesc;
      case 'community':
        return l10n.tutorialTemplateCommunityDesc;
      case 'workplace':
        return l10n.tutorialTemplateWorkplaceDesc;
      case 'government':
        return l10n.tutorialTemplateGovernmentDesc;
      case 'world':
        return l10n.tutorialTemplateWorldDesc;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Watch locale to rebuild when language changes
    ref.watch(localeProvider);

    const templateKeys = ['personal', 'family', 'community', 'workplace', 'government', 'world'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App icon
          Icon(
            Icons.groups_rounded,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            l10n.tutorialWelcomeTitle,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.tutorialWelcomeSubtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Template cards
          ...templateKeys.map((key) {
            final template = TutorialTemplate.templates[key]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildTemplateCard(
                context,
                icon: template.icon,
                name: _getTemplateName(key, l10n),
                description: _getTemplateDescription(key, l10n),
                onTap: () => onSelect(key),
              ),
            );
          }),
          const SizedBox(height: 16),
          // Legal agreement text
          _buildAgreementText(context, l10n),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onSkip,
            child: Text(l10n.tutorialSkipButton),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(
    BuildContext context, {
    required IconData icon,
    required String name,
    required String description,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgreementText(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${l10n.byContinuingYouAgree} ',
          style: textStyle,
        ),
        GestureDetector(
          onTap: () => context.push('/terms'),
          child: Text(
            l10n.termsOfServiceTitle,
            style: textStyle?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        Text(
          ' ${l10n.andText} ',
          style: textStyle,
        ),
        GestureDetector(
          onTap: () => context.push('/privacy'),
          child: Text(
            l10n.privacyPolicyTitle,
            style: textStyle?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        Text(
          '.',
          style: textStyle,
        ),
      ],
    );
  }
}
