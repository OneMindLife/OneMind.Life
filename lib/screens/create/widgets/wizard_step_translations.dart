import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'wizard_common.dart';

/// Wizard step for configuring chat language support.
/// Single language = no translations needed.
/// Multiple languages = auto-translations between them.
class WizardStepTranslations extends StatelessWidget {
  final TranslationSettings translationSettings;
  final void Function(TranslationSettings) onTranslationSettingsChanged;
  final VoidCallback onContinue;

  const WizardStepTranslations({
    super.key,
    required this.translationSettings,
    required this.onTranslationSettingsChanged,
    required this.onContinue,
  });

  static const _allLanguages = {
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'de': 'Deutsch',
  };

  /// Map locale code to our supported language codes.
  /// Returns 'en' if the locale isn't directly supported.
  static String _localeToLanguageCode(Locale locale) {
    final code = locale.languageCode;
    if (_allLanguages.containsKey(code)) return code;
    return 'en';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final userLocale = Localizations.localeOf(context);
    final userLangCode = _localeToLanguageCode(userLocale);

    // Single language mode = translations NOT enabled
    final isSingleLanguage = !translationSettings.enabled;

    return WizardStepLayout(
      icon: Icons.language,
      title: l10n.wizardTranslationsTitle,
      onContinue: onContinue,
      children: [
        WizardToggleCard(
          icon: Icons.translate,
          title: l10n.singleLanguageToggle,
          description: isSingleLanguage
              ? l10n.singleLanguageDesc
              : l10n.multiLanguageDesc,
          value: isSingleLanguage,
          onChanged: (value) {
            if (value) {
              // Switching to single language: pick user's locale language
              onTranslationSettingsChanged(
                translationSettings.copyWith(
                  enabled: false,
                  languages: {userLangCode},
                ),
              );
            } else {
              // Switching to multi-language: select all languages
              onTranslationSettingsChanged(
                translationSettings.copyWith(
                  enabled: true,
                  languages: _allLanguages.keys.toSet(),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 16),
        if (isSingleLanguage) ...[
          // Single language: dropdown to pick which one
          WizardSectionLabel(l10n.chatLanguageLabel),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: translationSettings.languages.first,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
            ),
            items: _allLanguages.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onTranslationSettingsChanged(
                  translationSettings.copyWith(
                    languages: {value},
                  ),
                );
              }
            },
          ),
        ] else ...[
          // Multi-language: checkboxes
          WizardSectionLabel(l10n.selectLanguages),
          const SizedBox(height: 8),
          ..._allLanguages.entries.map((entry) {
            final isSelected =
                translationSettings.languages.contains(entry.key);
            return CheckboxListTile(
              title: Text(entry.value),
              value: isSelected,
              onChanged: (checked) {
                final newLangs =
                    Set<String>.from(translationSettings.languages);
                if (checked == true) {
                  newLangs.add(entry.key);
                } else {
                  // Must keep at least 2 for multi-language mode
                  if (newLangs.length > 2) {
                    newLangs.remove(entry.key);
                  }
                }
                onTranslationSettingsChanged(
                  translationSettings.copyWith(languages: newLangs),
                );
              },
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: Text(
              l10n.autoTranslateHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
