/// Environment configuration for OneMind app
///
/// Values are injected at compile time via --dart-define flags.
/// Example build command:
/// ```
/// flutter build apk \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=your-anon-key
/// ```
///
/// For development, you can create a `.env` file and use a script to pass values,
/// or set them in your IDE's run configuration.
class EnvConfig {
  // Private constructor to prevent instantiation
  EnvConfig._();

  /// Supabase project URL
  /// Set via: --dart-define=SUPABASE_URL=https://your-project.supabase.co
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Supabase anonymous/public key
  /// Set via: --dart-define=SUPABASE_ANON_KEY=your-anon-key
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Current environment (development, staging, production)
  /// Set via: --dart-define=ENVIRONMENT=production
  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Web app base URL for deep links and QR codes
  /// Set via: --dart-define=WEB_APP_URL=https://YOUR_DOMAIN
  static const String webAppUrl = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: 'https://YOUR_DOMAIN',
  );

  /// Whether we're in production mode
  static bool get isProduction => environment == 'production';

  /// Whether we're in staging mode
  static bool get isStaging => environment == 'staging';

  /// Whether we're in development mode
  static bool get isDevelopment => environment == 'development';

  /// Validate that all required configuration is present
  /// Returns a list of missing configuration keys
  static List<String> validate() {
    final missing = <String>[];

    if (supabaseUrl.isEmpty) {
      missing.add('SUPABASE_URL');
    }
    if (supabaseAnonKey.isEmpty) {
      missing.add('SUPABASE_ANON_KEY');
    }

    return missing;
  }

  /// Check if configuration is valid
  static bool get isValid => validate().isEmpty;

  /// Get a human-readable error message for missing configuration
  static String? get validationError {
    final missing = validate();
    if (missing.isEmpty) return null;

    return 'Missing required environment variables: ${missing.join(', ')}. '
        'Please set them via --dart-define flags or in your IDE run configuration.';
  }
}
