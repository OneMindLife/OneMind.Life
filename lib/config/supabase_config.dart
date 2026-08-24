import 'env_config.dart';

/// Supabase configuration for OneMind app
///
/// By default, connects to the remote production Supabase instance.
/// Override via --dart-define to use a different backend.
///
/// Build examples:
/// ```bash
/// # Default: connects to remote production Supabase
/// flutter run
///
/// # Use local Supabase instance
/// flutter run \
///   --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
///   --dart-define=SUPABASE_ANON_KEY=<local-anon-key>
/// ```
class SupabaseConfig {
  // Private constructor to prevent instantiation
  SupabaseConfig._();

  /// Remote Supabase URL
  static const String _remoteUrl = 'https://ccyuxrtrklgpkzcryzpj.supabase.co';

  /// Remote Supabase anon key
  static const String _remoteAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjeXV4cnRya2xncGt6Y3J5enBqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5ODkzOTksImV4cCI6MjA4MzU2NTM5OX0.RR7W2SZD7BS9y3-I1YpyfB550fb0ZckduN-814RqycE';

  /// Local Supabase URL for development
  static const String _localUrl = 'http://127.0.0.1:54321';

  /// Get the Supabase URL
  /// Uses environment variable if set, otherwise falls back to remote
  static String get url {
    if (EnvConfig.supabaseUrl.isNotEmpty) {
      return EnvConfig.supabaseUrl;
    }
    // Fall back to remote Supabase
    return _remoteUrl;
  }

  /// Get the Supabase anonymous key
  /// Uses environment variable if set, otherwise falls back to remote
  static String get anonKey {
    if (EnvConfig.supabaseAnonKey.isNotEmpty) {
      return EnvConfig.supabaseAnonKey;
    }
    // Fall back to remote Supabase
    return _remoteAnonKey;
  }

  /// Whether using local Supabase instance
  static bool get isLocal => url == _localUrl;

  /// Whether configuration is properly set for non-local environments
  static bool get isConfigured => EnvConfig.isValid;

  /// Validate configuration for production builds.
  ///
  /// Deliberately does NOT throw. OneMind ships with hardcoded remote prod
  /// defaults (_remoteUrl/_remoteAnonKey), so a build that sets
  /// ENVIRONMENT=production WITHOUT the SUPABASE_* dart-defines still connects
  /// to prod correctly via those defaults. The old `throw StateError` here ran in
  /// main() before runApp and white-screened the entire app the moment
  /// ENVIRONMENT=production was set without the dart-defines (2026-05-31 outage).
  /// Never crash boot over this — log a warning and carry on with the defaults.
  static void validateForProduction() {
    if (EnvConfig.isProduction && !EnvConfig.isValid) {
      // ignore: avoid_print
      print('[config] ENVIRONMENT=production but SUPABASE_* dart-defines are '
          'unset — using built-in remote defaults. ${EnvConfig.validationError}');
    }
  }
}
