import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing user language preferences.
///
/// Follows a local-first approach:
/// 1. Load from SharedPreferences first
/// 2. Fall back to device language if supported
/// 3. Default to English
/// 4. Sync to database when logged in
class LanguageService {
  final SharedPreferences _prefs;
  final SupabaseClient _supabase;

  static const String _localeKey = 'locale';
  static const String _spokenLanguagesKey = 'spoken_languages';
  static const List<String> supportedLanguageCodes = ['en', 'es', 'pt', 'fr', 'de'];

  LanguageService(this._prefs, this._supabase);

  /// Get the current stored language code
  String? get storedLanguageCode => _prefs.getString(_localeKey);

  /// Get the device's preferred language
  String get deviceLanguage {
    final deviceLocale = PlatformDispatcher.instance.locale;
    if (supportedLanguageCodes.contains(deviceLocale.languageCode)) {
      return deviceLocale.languageCode;
    }
    return 'en'; // Default to English if device language not supported
  }

  /// Initialize language preference.
  /// Priority: stored preference > device language > English
  Future<String> initializeLanguage() async {
    // 1. Check local storage first
    final stored = _prefs.getString(_localeKey);
    if (stored != null && supportedLanguageCodes.contains(stored)) {
      return stored;
    }

    // 2. Use device language if supported
    final deviceLang = deviceLanguage;
    await _prefs.setString(_localeKey, deviceLang);

    // 3. If user is logged in, sync with database
    if (_supabase.auth.currentUser != null) {
      try {
        final response = await _supabase
            .from('users')
            .select('language_code')
            .eq('id', _supabase.auth.currentUser!.id)
            .maybeSingle();

        if (response != null && response['language_code'] != null) {
          // Database has a preference - use it
          final dbLang = response['language_code'] as String;
          if (supportedLanguageCodes.contains(dbLang)) {
            await _prefs.setString(_localeKey, dbLang);
            return dbLang;
          }
        } else {
          // Backfill - user logged in but no database preference yet
          await _updateDatabaseLanguage(deviceLang);
        }
      } catch (e) {
        // On error, continue with device language
      }
    }

    return deviceLang;
  }

  /// Update language preference (both local and database if logged in)
  Future<bool> updateLanguage(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode)) {
      return false;
    }

    try {
      // Always update local storage first
      await _prefs.setString(_localeKey, languageCode);

      // If logged in, also update database
      if (_supabase.auth.currentUser != null) {
        await _updateDatabaseLanguage(languageCode);
      }

      return true;
    } catch (e) {
      // Even if database update fails, local update may have succeeded
      return _prefs.getString(_localeKey) == languageCode;
    }
  }

  /// Update database language preference
  Future<bool> _updateDatabaseLanguage(String languageCode) async {
    try {
      await _supabase.rpc(
        'update_user_language_code',
        params: {'p_language_code': languageCode},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get current language code (synchronous, from local storage)
  String getCurrentLanguage() {
    final stored = _prefs.getString(_localeKey);
    if (stored != null && supportedLanguageCodes.contains(stored)) {
      return stored;
    }
    return 'en';
  }

  // =========================================================================
  // Spoken languages (for smart translation fallback on discover screen)
  // =========================================================================

  /// Get spoken languages from local storage.
  /// Defaults to [current primary language] if not set.
  List<String> getSpokenLanguages() {
    final stored = _prefs.getStringList(_spokenLanguagesKey);
    if (stored != null && stored.isNotEmpty) return stored;
    return [getCurrentLanguage()];
  }

  /// Update spoken languages locally and sync to database.
  Future<void> setSpokenLanguages(List<String> codes) async {
    await _prefs.setStringList(_spokenLanguagesKey, codes);
    if (_supabase.auth.currentUser != null) {
      await _updateDatabaseSpokenLanguages(codes);
    }
  }

  /// Sync spoken languages to database via RPC.
  Future<bool> _updateDatabaseSpokenLanguages(List<String> codes) async {
    try {
      await _supabase.rpc(
        'update_user_spoken_languages',
        params: {'p_languages': codes},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  // =========================================================================
  // Per-chat viewing language (separate from app UI language)
  // =========================================================================

  /// Get the persisted viewing language for a specific chat.
  /// Returns null if no preference has been set for this chat.
  String? getChatViewingLanguage(int chatId) {
    return _prefs.getString('chat_viewing_lang_$chatId');
  }

  /// Persist the viewing language for a specific chat.
  Future<void> setChatViewingLanguage(int chatId, String code) async {
    await _prefs.setString('chat_viewing_lang_$chatId', code);
  }

  /// Reset service (useful for logout)
  Future<void> reset() async {
    // Keep the local preference, just reset initialization state
    // This allows the preference to persist across sessions
  }
}
