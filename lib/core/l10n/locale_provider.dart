import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onemind_app/providers/providers.dart';
import 'language_service.dart';

/// Provider for SharedPreferences instance.
/// Must be overridden in ProviderScope with the actual instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  );
});

/// Provider for LanguageService
final languageServiceProvider = Provider<LanguageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final client = ref.watch(supabaseProvider);
  return LanguageService(prefs, client);
});

/// State notifier for managing locale state
class LocaleNotifier extends StateNotifier<Locale> {
  final LanguageService _languageService;

  LocaleNotifier(this._languageService)
      : super(Locale(_languageService.getCurrentLanguage()));

  /// Initialize locale from storage/device/database
  Future<void> initialize() async {
    final languageCode = await _languageService.initializeLanguage();
    state = Locale(languageCode);
  }

  /// Update locale and persist the change
  Future<void> setLocale(String languageCode) async {
    if (!LanguageService.supportedLanguageCodes.contains(languageCode)) {
      return;
    }

    final success = await _languageService.updateLanguage(languageCode);
    if (success) {
      state = Locale(languageCode);
    }
  }

  /// Get current language code
  String get currentLanguageCode => state.languageCode;
}

/// Provider for the current locale
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  final languageService = ref.watch(languageServiceProvider);
  return LocaleNotifier(languageService);
});

/// Provider for supported locales
final supportedLocalesProvider = Provider<List<Locale>>((ref) {
  return LanguageService.supportedLanguageCodes
      .map((code) => Locale(code))
      .toList();
});
