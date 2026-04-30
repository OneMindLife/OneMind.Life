import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/providers.dart';

const String _donateUrl = 'https://buy.stripe.com/aFa6oHbXedYZg1xap4b3q01';

/// Quiet, dismissible "Support OneMind" prompt shown after a fresh
/// convergence is reached. Throttled by [DonatePromptService] so the
/// user is never asked more than once every 7 days.
///
/// Returns when the dialog is closed (regardless of which button).
Future<void> showSupportOneMindDialog(
  BuildContext context,
  WidgetRef ref, {
  required String source,
}) async {
  final l10n = AppLocalizations.of(context);
  final analytics = ref.read(analyticsServiceProvider);
  final donatePrompt = ref.read(donatePromptServiceProvider);
  await donatePrompt.markShown();
  await analytics.logDonatePromptShown(source: source);

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        icon: const Icon(Icons.favorite_outline, size: 32),
        title: Text(l10n.supportOneMindTitle),
        content: Text(l10n.supportOneMindBody),
        actions: [
          TextButton(
            onPressed: () async {
              await analytics.logDonatePromptDismissed(source: source);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(l10n.maybeLater),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.favorite_outline),
            onPressed: () async {
              await analytics.logDonateClicked(source: source);
              await donatePrompt.markEverDonated();
              await launchUrl(
                Uri.parse(
                  '$_donateUrl?utm_source=app&utm_medium=donate_button&utm_campaign=$source',
                ),
                mode: LaunchMode.externalApplication,
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            label: Text(l10n.donate),
          ),
        ],
      );
    },
  );
}
