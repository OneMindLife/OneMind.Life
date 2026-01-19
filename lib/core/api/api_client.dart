import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../errors/errors.dart';
import 'api_config.dart';

/// Wrapper around Supabase client that adds timeout and retry functionality.
///
/// Usage:
/// ```dart
/// final client = ApiClient(supabaseClient);
///
/// // Simple call with default timeout
/// final result = await client.execute(() =>
///   supabaseClient.from('chats').select().eq('id', 1).single()
/// );
///
/// // Call with retry
/// final result = await client.executeWithRetry(() =>
///   supabaseClient.from('chats').insert({...}).select().single()
/// );
/// ```
class ApiClient {
  final SupabaseClient _client;
  final ErrorHandler _errorHandler;
  final int _defaultMaxRetries;

  ApiClient(
    this._client, {
    int? defaultMaxRetries,
    ErrorHandler? errorHandler,
  })  : _defaultMaxRetries = defaultMaxRetries ?? ApiConfig.defaultMaxRetries,
        _errorHandler = errorHandler ?? ErrorHandler.instance;

  /// The underlying Supabase client
  SupabaseClient get supabase => _client;

  /// Execute an API call with timeout.
  ///
  /// Throws [AppException.timeout] if the operation takes too long.
  /// Other exceptions are converted to appropriate [AppException] types.
  Future<T> execute<T>(
    Future<T> Function() operation, {
    Duration? timeout,
    String? operationType,
    Map<String, dynamic>? context,
  }) async {
    final effectiveTimeout = timeout ?? ApiConfig.getTimeout(operationType);

    try {
      return await operation().timeout(
        effectiveTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Operation timed out after ${effectiveTimeout.inSeconds}s',
            effectiveTimeout,
          );
        },
      );
    } on TimeoutException {
      throw AppException.timeout(
        message: 'API call timed out after ${effectiveTimeout.inSeconds}s',
        context: context,
      );
    } on PostgrestException catch (e) {
      throw _handlePostgrestError(e, context);
    } on AuthException catch (e) {
      throw _handleAuthError(e, context);
    } catch (e, stackTrace) {
      throw _errorHandler.handle(e, stackTrace: stackTrace, context: context);
    }
  }

  /// Execute an API call with timeout and automatic retry.
  ///
  /// Retries on transient failures (network, timeout, server errors).
  /// Uses exponential backoff between retries.
  Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    Duration? timeout,
    int? maxRetries,
    Duration? initialDelay,
    String? operationType,
    Map<String, dynamic>? context,
  }) async {
    final effectiveTimeout = timeout ?? ApiConfig.getTimeout(operationType);
    final effectiveMaxRetries = maxRetries ?? _defaultMaxRetries;
    var delay = initialDelay ?? ApiConfig.initialRetryDelay;
    int attempt = 0;

    while (true) {
      try {
        return await execute<T>(
          operation,
          timeout: effectiveTimeout,
          context: {...?context, 'attempt': attempt + 1},
        );
      } catch (e) {
        attempt++;

        // Check if error is retryable
        final appException = e is AppException ? e : AppException.fromException(e);

        if (!appException.isRetryable || attempt >= effectiveMaxRetries) {
          // Not retryable or max retries reached
          if (e is AppException) {
            rethrow;
          }
          throw appException;
        }

        // Log retry attempt
        _errorHandler.warning(
          'Retrying API call (attempt $attempt/$effectiveMaxRetries)',
          {
            'error': appException.codeString,
            'delayMs': delay.inMilliseconds,
            ...?context,
          },
        );

        // Wait before retrying
        await Future.delayed(delay);

        // Exponential backoff with max cap
        delay = Duration(
          milliseconds:
              (delay.inMilliseconds * 2).clamp(0, ApiConfig.maxRetryDelay.inMilliseconds),
        );
      }
    }
  }

  /// Handle Postgrest errors and convert to appropriate AppException
  AppException _handlePostgrestError(
    PostgrestException e,
    Map<String, dynamic>? context,
  ) {
    final code = e.code;
    final message = e.message;

    // Network/connectivity issues
    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('socket')) {
      return AppException.network(
        message: message,
        context: context,
      );
    }

    // Authentication errors
    if (code == '401' || code == 'PGRST301') {
      return AppException.authRequired(
        message: message,
        context: context,
      );
    }

    // Permission/RLS errors
    if (code == '42501' || message.contains('RLS') || message.contains('policy')) {
      return AppException(
        code: AppErrorCode.validationError,
        message: 'Access denied',
        technicalDetails: message,
        context: context,
      );
    }

    // Not found
    if (code == 'PGRST116' || message.contains('not found')) {
      return AppException(
        code: AppErrorCode.chatNotFound,
        message: 'Resource not found',
        technicalDetails: message,
        context: context,
      );
    }

    // Unique constraint violation (duplicate)
    if (code == '23505') {
      return AppException(
        code: AppErrorCode.validationError,
        message: 'A record with this information already exists',
        technicalDetails: message,
        isRetryable: false,
        context: context,
      );
    }

    // Foreign key violation
    if (code == '23503') {
      return AppException(
        code: AppErrorCode.validationError,
        message: 'Referenced record does not exist',
        technicalDetails: message,
        isRetryable: false,
        context: context,
      );
    }

    // Server errors (500+) - retryable
    if (code != null && code.startsWith('5')) {
      return AppException.serverError(
        message: message,
        context: context,
      );
    }

    // Default to server error
    return AppException(
      code: AppErrorCode.serverError,
      message: 'Database operation failed',
      technicalDetails: 'PostgrestException: ${e.code} - ${e.message}',
      context: context,
    );
  }

  /// Handle Auth errors and convert to appropriate AppException
  AppException _handleAuthError(
    AuthException e,
    Map<String, dynamic>? context,
  ) {
    final message = e.message;

    if (message.contains('expired') || message.contains('refresh')) {
      return AppException.sessionExpired(
        message: message,
        context: context,
      );
    }

    if (message.contains('invalid') || message.contains('token')) {
      return AppException(
        code: AppErrorCode.authInvalidToken,
        message: message,
        context: context,
        isRetryable: false,
      );
    }

    return AppException.authRequired(
      message: message,
      context: context,
    );
  }

  // ==========================================================================
  // Convenience methods for common operations
  // ==========================================================================

  /// Fetch a list of records
  Future<List<Map<String, dynamic>>> fetchList(
    String table, {
    String? select,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    Duration? timeout,
  }) async {
    return execute(() async {
      var query = _client.from(table).select(select ?? '*');

      // Apply filters
      for (final entry in (filters ?? {}).entries) {
        query = query.eq(entry.key, entry.value);
      }

      // Build final query with order and limit
      final dynamic finalQuery;
      if (orderBy != null && limit != null) {
        finalQuery = query.order(orderBy, ascending: ascending).limit(limit);
      } else if (orderBy != null) {
        finalQuery = query.order(orderBy, ascending: ascending);
      } else if (limit != null) {
        finalQuery = query.limit(limit);
      } else {
        finalQuery = query;
      }

      final response = await finalQuery;
      return List<Map<String, dynamic>>.from(response as List);
    }, timeout: timeout ?? ApiConfig.quickTimeout, context: {'table': table});
  }

  /// Fetch a single record by ID
  Future<Map<String, dynamic>?> fetchById(
    String table,
    dynamic id, {
    String? select,
    String idColumn = 'id',
    Duration? timeout,
  }) async {
    return execute(() async {
      final response = await _client
          .from(table)
          .select(select ?? '*')
          .eq(idColumn, id)
          .maybeSingle();

      return response;
    }, timeout: timeout ?? ApiConfig.quickTimeout, context: {'table': table, 'id': id});
  }

  /// Insert a record
  Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> data, {
    String? select,
    Duration? timeout,
  }) async {
    return executeWithRetry(
      () async {
        final response =
            await _client.from(table).insert(data).select(select ?? '*').single();
        return response;
      },
      timeout: timeout,
      context: {'table': table, 'operation': 'insert'},
    );
  }

  /// Update a record
  Future<Map<String, dynamic>> update(
    String table,
    Map<String, dynamic> data, {
    required Map<String, dynamic> match,
    String? select,
    Duration? timeout,
  }) async {
    return executeWithRetry(
      () async {
        var query = _client.from(table).update(data);

        for (final entry in match.entries) {
          query = query.eq(entry.key, entry.value);
        }

        final response = await query.select(select ?? '*').single();
        return response;
      },
      timeout: timeout,
      context: {'table': table, 'operation': 'update', 'match': match},
    );
  }

  /// Call an RPC function
  Future<T> rpc<T>(
    String function, {
    Map<String, dynamic>? params,
    Duration? timeout,
    bool retry = false,
  }) async {
    Future<T> operation() async {
      final response = await _client.rpc(function, params: params);
      return response as T;
    }

    if (retry) {
      return executeWithRetry(
        operation,
        timeout: timeout,
        context: {'function': function},
      );
    }

    return execute(
      operation,
      timeout: timeout,
      context: {'function': function},
    );
  }
}

/// Extension to add timeout/retry capabilities to existing SupabaseClient usage
extension SupabaseClientExtension on SupabaseClient {
  /// Wrap a query with timeout
  Future<T> withTimeout<T>(
    Future<T> Function() query, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return query().timeout(
      timeout,
      onTimeout: () {
        throw AppException.timeout(
          message: 'Query timed out after ${timeout.inSeconds}s',
        );
      },
    );
  }
}
