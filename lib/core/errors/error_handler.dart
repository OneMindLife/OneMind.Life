import 'dart:async';
import 'package:flutter/foundation.dart';
import 'app_exception.dart';

/// Callback type for error reporting (e.g., Sentry)
typedef ErrorReportCallback = Future<void> Function(
  AppException error,
  StackTrace? stackTrace,
);

/// Callback type for error logging
typedef ErrorLogCallback = void Function(
  String level,
  String message,
  Map<String, dynamic>? data,
);

/// Centralized error handler for the application.
/// Provides logging, reporting, and consistent error handling.
class ErrorHandler {
  static ErrorHandler? _instance;
  static ErrorHandler get instance => _instance ??= ErrorHandler._();

  ErrorHandler._();

  /// Reset the singleton instance (for testing purposes)
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  /// Initialize with custom error reporting (e.g., Sentry)
  factory ErrorHandler({
    ErrorReportCallback? reportCallback,
    ErrorLogCallback? logCallback,
  }) {
    _instance = ErrorHandler._();
    _instance!._reportCallback = reportCallback;
    _instance!._logCallback = logCallback;
    return _instance!;
  }

  ErrorReportCallback? _reportCallback;
  ErrorLogCallback? _logCallback;

  /// Set the error reporting callback (e.g., for Sentry integration)
  void setReportCallback(ErrorReportCallback callback) {
    _reportCallback = callback;
  }

  /// Set the logging callback
  void setLogCallback(ErrorLogCallback callback) {
    _logCallback = callback;
  }

  /// Handle an error, converting it to AppException if needed.
  /// Returns the AppException for display purposes.
  AppException handle(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    bool report = true,
  }) {
    final appException = error is AppException
        ? error
        : AppException.fromException(
            error,
            stackTrace: stackTrace,
            context: context,
          );

    // Log the error
    _log(appException, stackTrace);

    // Report to error tracking if appropriate
    if (report && appException.shouldReport) {
      _report(appException, stackTrace ?? appException.stackTrace);
    }

    return appException;
  }

  /// Wrap an async operation with error handling
  Future<T> wrapAsync<T>(
    Future<T> Function() operation, {
    Map<String, dynamic>? context,
    T Function(AppException)? onError,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      final appException = handle(
        error,
        stackTrace: stackTrace,
        context: context,
      );
      if (onError != null) {
        return onError(appException);
      }
      throw appException;
    }
  }

  /// Wrap an async operation with retry logic
  Future<T> wrapWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    Map<String, dynamic>? context,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        return await operation();
      } catch (error, stackTrace) {
        attempt++;
        final appException = handle(
          error,
          stackTrace: stackTrace,
          context: {...?context, 'attempt': attempt},
          report: attempt == maxRetries, // Only report on final failure
        );

        if (!appException.isRetryable || attempt >= maxRetries) {
          throw appException;
        }

        _logCallback?.call(
          'warning',
          'Retrying operation (attempt $attempt/$maxRetries)',
          {'error': appException.codeString, 'delay': delay.inMilliseconds},
        );

        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
  }

  /// Log an error
  void _log(AppException error, StackTrace? stackTrace) {
    final level = error.shouldReport ? 'error' : 'warning';
    final data = error.toJson();
    if (stackTrace != null) {
      data['stackTrace'] = stackTrace.toString().split('\n').take(10).join('\n');
    }

    if (_logCallback != null) {
      _logCallback!(level, error.message, data);
    } else {
      // Default logging
      if (kDebugMode) {
        print('[$level] ${error.codeString}: ${error.message}');
        if (error.technicalDetails != null) {
          print('  Details: ${error.technicalDetails}');
        }
        if (error.context != null) {
          print('  Context: ${error.context}');
        }
        if (stackTrace != null) {
          print('  Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}');
        }
      }
    }
  }

  /// Report an error to error tracking service
  Future<void> _report(AppException error, StackTrace? stackTrace) async {
    if (_reportCallback != null) {
      try {
        await _reportCallback!(error, stackTrace);
      } catch (e) {
        // Don't let error reporting failures cause additional problems
        if (kDebugMode) {
          print('Failed to report error: $e');
        }
      }
    }
  }

  /// Log an informational message
  void info(String message, [Map<String, dynamic>? data]) {
    if (_logCallback != null) {
      _logCallback!('info', message, data);
    } else if (kDebugMode) {
      print('[info] $message${data != null ? ' $data' : ''}');
    }
  }

  /// Log a warning message
  void warning(String message, [Map<String, dynamic>? data]) {
    if (_logCallback != null) {
      _logCallback!('warning', message, data);
    } else if (kDebugMode) {
      print('[warning] $message${data != null ? ' $data' : ''}');
    }
  }

  /// Log a debug message
  void debug(String message, [Map<String, dynamic>? data]) {
    if (_logCallback != null) {
      _logCallback!('debug', message, data);
    } else if (kDebugMode) {
      print('[debug] $message${data != null ? ' $data' : ''}');
    }
  }
}

/// Convenience functions for error handling
ErrorHandler get errorHandler => ErrorHandler.instance;

/// Handle an error and return an AppException
AppException handleError(
  dynamic error, {
  StackTrace? stackTrace,
  Map<String, dynamic>? context,
  bool report = true,
}) {
  return ErrorHandler.instance.handle(
    error,
    stackTrace: stackTrace,
    context: context,
    report: report,
  );
}

/// Wrap an async operation with error handling
Future<T> wrapAsync<T>(
  Future<T> Function() operation, {
  Map<String, dynamic>? context,
  T Function(AppException)? onError,
}) {
  return ErrorHandler.instance.wrapAsync(
    operation,
    context: context,
    onError: onError,
  );
}

/// Wrap an async operation with retry logic
Future<T> wrapWithRetry<T>(
  Future<T> Function() operation, {
  int maxRetries = 3,
  Duration initialDelay = const Duration(seconds: 1),
  Map<String, dynamic>? context,
}) {
  return ErrorHandler.instance.wrapWithRetry(
    operation,
    maxRetries: maxRetries,
    initialDelay: initialDelay,
    context: context,
  );
}
