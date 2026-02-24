import 'package:flutter/material.dart';

/// Language name lookup (native names for display).
const _languageNames = {
  'en': 'English',
  'es': 'Español',
  'pt': 'Português',
  'fr': 'Français',
  'de': 'Deutsch',
};

/// A language selector scoped to a single chat's supported languages.
///
/// Unlike [LanguageSelector], this widget:
/// - Only shows languages the chat supports ([availableLanguages])
/// - Does NOT touch the global [localeProvider] — calls [onLanguageChanged] instead
/// - Hides itself when the chat has 0 or 1 languages
class ChatLanguageSelector extends StatelessWidget {
  final List<String> availableLanguages;
  final String currentLanguageCode;
  final ValueChanged<String> onLanguageChanged;

  const ChatLanguageSelector({
    super.key,
    required this.availableLanguages,
    required this.currentLanguageCode,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Hide when there's nothing to choose
    if (availableLanguages.length <= 1) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.translate),
      tooltip: 'Content language',
      onSelected: onLanguageChanged,
      itemBuilder: (context) => availableLanguages.map((code) {
        final name = _languageNames[code] ?? code;
        return PopupMenuItem<String>(
          value: code,
          child: Row(
            children: [
              if (currentLanguageCode == code)
                const Icon(Icons.check, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(name),
            ],
          ),
        );
      }).toList(),
    );
  }
}
