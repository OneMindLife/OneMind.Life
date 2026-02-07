import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/locale_provider.dart';
import '../l10n/generated/app_localizations.dart';

/// A widget that allows users to select their preferred language.
/// Can be displayed as a dropdown button or a popup menu.
class LanguageSelector extends ConsumerWidget {
  /// Whether to show as a compact icon button (true) or a dropdown (false)
  final bool compact;

  const LanguageSelector({super.key, this.compact = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final l10n = AppLocalizations.of(context);

    if (compact) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.language),
        tooltip: l10n.language,
        onSelected: (languageCode) {
          ref.read(localeProvider.notifier).setLocale(languageCode);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'en',
            child: Row(
              children: [
                if (locale.languageCode == 'en')
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('English'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'es',
            child: Row(
              children: [
                if (locale.languageCode == 'es')
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('Espanol'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'pt',
            child: Row(
              children: [
                if (locale.languageCode == 'pt')
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('Portugues'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'fr',
            child: Row(
              children: [
                if (locale.languageCode == 'fr')
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('Francais'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'de',
            child: Row(
              children: [
                if (locale.languageCode == 'de')
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('Deutsch'),
              ],
            ),
          ),
        ],
      );
    }

    // Full dropdown version
    return DropdownButton<String>(
      value: locale.languageCode,
      icon: const Icon(Icons.arrow_drop_down),
      underline: const SizedBox(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          ref.read(localeProvider.notifier).setLocale(newValue);
        }
      },
      items: const [
        DropdownMenuItem(
          value: 'en',
          child: Text('English'),
        ),
        DropdownMenuItem(
          value: 'es',
          child: Text('Espanol'),
        ),
        DropdownMenuItem(
          value: 'pt',
          child: Text('Portugues'),
        ),
        DropdownMenuItem(
          value: 'fr',
          child: Text('Francais'),
        ),
        DropdownMenuItem(
          value: 'de',
          child: Text('Deutsch'),
        ),
      ],
    );
  }
}

/// A list tile version of the language selector for settings screens
class LanguageSelectorTile extends ConsumerWidget {
  const LanguageSelectorTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final l10n = AppLocalizations.of(context);

    String languageName;
    switch (locale.languageCode) {
      case 'es':
        languageName = l10n.spanish;
        break;
      case 'pt':
        languageName = l10n.portuguese;
        break;
      case 'fr':
        languageName = l10n.french;
        break;
      case 'de':
        languageName = l10n.german;
        break;
      case 'en':
      default:
        languageName = l10n.english;
    }

    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l10n.language),
      subtitle: Text(languageName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLanguageDialog(context, ref),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final locale = ref.read(localeProvider);
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.language),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text(l10n.english),
                value: 'en',
                groupValue: locale.languageCode,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).setLocale(value);
                    Navigator.pop(dialogContext);
                  }
                },
              ),
              RadioListTile<String>(
                title: Text(l10n.spanish),
                value: 'es',
                groupValue: locale.languageCode,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).setLocale(value);
                    Navigator.pop(dialogContext);
                  }
                },
              ),
              RadioListTile<String>(
                title: Text(l10n.portuguese),
                value: 'pt',
                groupValue: locale.languageCode,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).setLocale(value);
                    Navigator.pop(dialogContext);
                  }
                },
              ),
              RadioListTile<String>(
                title: Text(l10n.french),
                value: 'fr',
                groupValue: locale.languageCode,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).setLocale(value);
                    Navigator.pop(dialogContext);
                  }
                },
              ),
              RadioListTile<String>(
                title: Text(l10n.german),
                value: 'de',
                groupValue: locale.languageCode,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).setLocale(value);
                    Navigator.pop(dialogContext);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}
