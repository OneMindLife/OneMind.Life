import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/locale_provider.dart';

/// Mixin that provides language change awareness to StateNotifiers.
///
/// This mixin eliminates duplicate locale listener code across notifiers
/// by providing a standard pattern for:
/// - Tracking the current language code
/// - Listening for locale changes
/// - Triggering refresh when language changes
///
/// Usage:
/// ```dart
/// class MyNotifier extends StateNotifier<AsyncValue<MyState>>
///     with LanguageAwareMixin {
///   MyNotifier(Ref ref) : super(const AsyncLoading()) {
///     initializeLanguageSupport(ref);
///   }
///
///   @override
///   void onLanguageChanged(String newLanguageCode) {
///     // Refresh data with new language
///     _refreshForLanguageChange();
///   }
///
///   @override
///   void dispose() {
///     disposeLanguageSupport();
///     super.dispose();
///   }
/// }
/// ```
mixin LanguageAwareMixin<T> on StateNotifier<T> {
  String _currentLanguageCode = 'en';
  ProviderSubscription<Locale>? _localeSubscription;

  /// Get the current language code for translations
  String get languageCode => _currentLanguageCode;

  /// Initialize language support by setting up the locale listener.
  /// Call this in the constructor after super().
  void initializeLanguageSupport(Ref ref) {
    // Get initial language
    _currentLanguageCode = ref.read(languageServiceProvider).getCurrentLanguage();

    // Listen for locale changes
    _localeSubscription = ref.listen<Locale>(
      localeProvider,
      (previous, next) {
        final newLanguageCode = next.languageCode;
        if (_currentLanguageCode != newLanguageCode) {
          _currentLanguageCode = newLanguageCode;
          onLanguageChanged(newLanguageCode);
        }
      },
    );
  }

  /// Called when the language changes.
  /// Override this to refresh data with the new language.
  void onLanguageChanged(String newLanguageCode);

  /// Clean up the locale subscription.
  /// Call this in dispose() before super.dispose().
  void disposeLanguageSupport() {
    _localeSubscription?.close();
  }
}
