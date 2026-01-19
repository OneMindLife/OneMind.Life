/// API configuration and timeout settings
class ApiConfig {
  /// Default timeout for API calls
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Timeout for quick operations (reads, single row fetches)
  static const Duration quickTimeout = Duration(seconds: 10);

  /// Timeout for long operations (large uploads, batch operations)
  static const Duration longTimeout = Duration(seconds: 60);

  /// Default number of retries for transient failures
  static const int defaultMaxRetries = 3;

  /// Initial delay between retries (doubles on each attempt)
  static const Duration initialRetryDelay = Duration(seconds: 1);

  /// Maximum delay between retries
  static const Duration maxRetryDelay = Duration(seconds: 30);

  /// Operations that should use quick timeout
  static const Set<String> quickOperations = {
    'select',
    'maybeSingle',
    'single',
  };

  /// Operations that should use long timeout
  static const Set<String> longOperations = {
    'upload',
    'download',
    'batch',
  };

  /// Get appropriate timeout for operation type
  static Duration getTimeout(String? operationType) {
    if (operationType != null) {
      if (quickOperations.contains(operationType)) {
        return quickTimeout;
      }
      if (longOperations.contains(operationType)) {
        return longTimeout;
      }
    }
    return defaultTimeout;
  }

  // Private constructor - this is a static configuration class
  const ApiConfig._();
}
