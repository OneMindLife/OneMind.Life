import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';

/// Wizard step for configuring chat language support.
/// Single language = no translations needed.
/// Multiple languages = auto-translations between them.
class WizardStepTranslations extends StatelessWidget {
  final TranslationSettings translationSettings;
  final void Function(TranslationSettings) onTranslationSettingsChanged;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const WizardStepTranslations({
    super.key,
    required this.translationSettings,
    required this.onTranslationSettingsChanged,
    required this.onBack,
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final userLocale = Localizations.localeOf(context);
    final userLangCode = _localeToLanguageCode(userLocale);

    // Single language mode = translations NOT enabled
    final isSingleLanguage = !translationSettings.enabled;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.language,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.wizardTranslationsTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.wizardTranslationsSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    title: Text(l10n.singleLanguageToggle),
                    subtitle: Text(
                      isSingleLanguage
                          ? l10n.singleLanguageDesc
                          : l10n.multiLanguageDesc,
                    ),
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
                    Text(
                      l10n.chatLanguageLabel,
                      style: theme.textTheme.titleSmall,
                    ),
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
                    Text(
                      l10n.selectLanguages,
                      style: theme.textTheme.titleSmall,
                    ),
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
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.arrow_back, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.back),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: onContinue,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n.continue_),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
