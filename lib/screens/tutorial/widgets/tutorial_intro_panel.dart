import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../widgets/language_selector.dart';

/// Welcome panel shown at the start of the tutorial
class TutorialIntroPanel extends ConsumerWidget {
  final VoidCallback onStart;
  final VoidCallback onSkip;

  const TutorialIntroPanel({
    super.key,
    required this.onStart,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Watch locale to rebuild when language changes
    ref.watch(localeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Language selector at top right
          const Align(
            alignment: Alignment.topRight,
            child: LanguageSelector(compact: true),
          ),
          const SizedBox(height: 16),
          // App icon or logo placeholder
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
          const SizedBox(height: 32),
          // What you'll learn
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tutorialWhatYoullLearn,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildBulletPoint(context, l10n.tutorialBullet1),
                _buildBulletPoint(context, l10n.tutorialBullet2),
                _buildBulletPoint(context, l10n.tutorialBullet3),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // The question
          Text(
            l10n.tutorialTheQuestion,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"${l10n.tutorialQuestion}"',
            style: theme.textTheme.titleLarge?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // Start button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.tutorialStartButton),
            ),
          ),
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

  Widget _buildBulletPoint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
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
