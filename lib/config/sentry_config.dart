import 'package:flutter/foundation.dart';

/// Sentry configuration for OneMind app
///
/// Values are injected at compile time via --dart-define flags.
/// Example build command:
/// ```
/// flutter build web \
///   --dart-define=SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
/// ```
class SentryConfig {
  // Private constructor to prevent instantiation
  SentryConfig._();

  /// Sentry DSN (Data Source Name)
  /// Set via: --dart-define=SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
  static const String dsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  /// Whether Sentry is configured
  static bool get isConfigured => dsn.isNotEmpty;

  /// Whether to enable Sentry
  /// Only enable in release mode when DSN is configured
  static bool get isEnabled => !kDebugMode && isConfigured;

  /// Environment name for Sentry
  static String get environment {
    if (kDebugMode) return 'development';
    const env = String.fromEnvironment('ENVIRONMENT', defaultValue: 'production');
    return env;
  }

  /// Sample rate for error events (0.0 to 1.0)
  /// In production, capture all errors
  static double get sampleRate => 1.0;

  /// Sample rate for performance traces (0.0 to 1.0)
  /// Lower to reduce costs
  static double get tracesSampleRate => kDebugMode ? 1.0 : 0.2;
}
