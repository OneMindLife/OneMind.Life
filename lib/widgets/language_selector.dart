import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/locale_provider.dart';
import '../l10n/generated/app_localizations.dart';

/// Language display names keyed by code.
const _languageNames = {
  'en': 'English',
  'es': 'Espanol',
  'pt': 'Portugues',
  'fr': 'Francais',
  'de': 'Deutsch',
};

/// A compact language selector that opens the enhanced language dialog.
class LanguageSelector extends ConsumerWidget {
  final bool compact;

  const LanguageSelector({super.key, this.compact = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    if (compact) {
      return IconButton(
        icon: const Icon(Icons.language),
        tooltip: l10n.language,
        onPressed: () => showEnhancedLanguageDialog(context, ref),
      );
    }

    // Full dropdown version (legacy — opens enhanced dialog on tap)
    final locale = ref.watch(localeProvider);
    return InkWell(
      onTap: () => showEnhancedLanguageDialog(context, ref),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_languageNames[locale.languageCode] ?? 'English'),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

/// A list tile version of the language selector for settings screens.
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
      case 'pt':
        languageName = l10n.portuguese;
      case 'fr':
        languageName = l10n.french;
      case 'de':
        languageName = l10n.german;
      case 'en':
      default:
        languageName = l10n.english;
    }

    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l10n.language),
      subtitle: Text(languageName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showEnhancedLanguageDialog(context, ref),
    );
  }
}

/// Shows the enhanced language dialog with primary language (radio)
/// and "I also speak" (checkboxes).
void showEnhancedLanguageDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (dialogContext) => _EnhancedLanguageDialog(ref: ref),
  );
}

class _EnhancedLanguageDialog extends StatefulWidget {
  final WidgetRef ref;

  const _EnhancedLanguageDialog({required this.ref});

  @override
  State<_EnhancedLanguageDialog> createState() =>
      _EnhancedLanguageDialogState();
}

class _EnhancedLanguageDialogState extends State<_EnhancedLanguageDialog> {
  late String _primaryLanguage;
  late Set<String> _additionalLanguages;

  @override
  void initState() {
    super.initState();
    _primaryLanguage = widget.ref.read(localeProvider).languageCode;
    final spoken = widget.ref.read(spokenLanguagesProvider);
    // Additional = spoken minus primary
    _additionalLanguages =
        spoken.where((code) => code != _primaryLanguage).toSet();
  }

  String _localizedName(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context);
    switch (code) {
      case 'es':
        return l10n.spanish;
      case 'pt':
        return l10n.portuguese;
      case 'fr':
        return l10n.french;
      case 'de':
        return l10n.german;
      case 'en':
      default:
        return l10n.english;
    }
  }

  void _save() {
    // Update primary language
    widget.ref.read(localeProvider.notifier).setLocale(_primaryLanguage);

    // Update spoken languages = primary + additional
    final spoken = [_primaryLanguage, ..._additionalLanguages];
    widget.ref.read(spokenLanguagesProvider.notifier).setSpokenLanguages(spoken);

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final codes = ['en', 'es', 'pt', 'fr', 'de'];

    return AlertDialog(
      title: Text(l10n.language),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Primary Language section
            Text(
              l10n.primaryLanguage,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            ...codes.map(
              (code) => RadioListTile<String>(
                title: Text(_localizedName(context, code)),
                value: code,
                groupValue: _primaryLanguage,
                dense: true,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _primaryLanguage = value;
                      // Remove from additional if it was there
                      _additionalLanguages.remove(value);
                    });
                  }
                },
              ),
            ),
            const Divider(),
            // "I also speak" section
            Text(
              l10n.iAlsoSpeak,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            ...codes
                .where((code) => code != _primaryLanguage)
                .map(
                  (code) => CheckboxListTile(
                    title: Text(_localizedName(context, code)),
                    value: _additionalLanguages.contains(code),
                    dense: true,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _additionalLanguages.add(code);
                        } else {
                          _additionalLanguages.remove(code);
                        }
                      });
                    },
                  ),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
