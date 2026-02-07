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

  /// Remote Supabase URL (must be provided via --dart-define)
  static const String _remoteUrl = 'https://YOUR_PROJECT.supabase.co';

  /// Remote Supabase anon key (must be provided via --dart-define)
  static const String _remoteAnonKey = 'your-anon-key';

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

  /// Validate configuration for production builds
  /// Throws if required environment variables are missing in production
  static void validateForProduction() {
    if (EnvConfig.isProduction && !EnvConfig.isValid) {
      throw StateError(
        'Production build requires environment configuration. '
        '${EnvConfig.validationError}',
      );
    }
  }
}
