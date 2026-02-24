/// Utility for language display in chat surfaces.
class LanguageUtils {
  static const _nativeNames = {
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'de': 'Deutsch',
  };

  /// Returns the native display name for a language code.
  static String displayName(String code) => _nativeNames[code] ?? code;

  /// Returns comma-separated native names, sorted alphabetically.
  /// e.g. "English" or "Deutsch, English, Español, Français, Português"
  static String shortLabel(List<String> languages) {
    if (languages.isEmpty) return displayName('en');
    final names = languages.map(displayName).toList()..sort();
    return names.join(', ');
  }
}
