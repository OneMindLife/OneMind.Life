import 'package:equatable/equatable.dart';

/// Error codes for the application.
/// These codes are used for error tracking and user-friendly message mapping.
enum AppErrorCode {
  // Network errors (1xx)
  networkError,
  networkTimeout,
  networkOffline,

  // Authentication errors (2xx)
  authRequired,
  authInvalidToken,
  authSessionExpired,

  // Validation errors (3xx)
  validationError,
  validationInvalidInput,
  validationMissingField,
  validationOutOfRange,

  // Resource errors (4xx)
  notFound,
  alreadyExists,
  conflict,

  // Permission errors (5xx)
  forbidden,
  rateLimited,
  insufficientCredits,

  // Billing errors (6xx)
  billingError,
  billingPaymentFailed,
  billingPaymentDeclined,
  billingInvalidAmount,
  billingWebhookError,

  // Chat errors (7xx)
  chatNotFound,
  chatClosed,
  chatFull,

  // Participant errors (8xx)
  participantNotFound,
  participantKicked,
  participantNotActive,

  // Proposition errors (9xx)
  propositionLimitReached,
  propositionRoundClosed,
  propositionDuplicate,

  // Rating errors (10xx)
  ratingAlreadySubmitted,
  ratingRoundClosed,
  ratingInvalidValue,

  // Server errors (99x)
  serverError,
  serverMaintenance,
  unknownError,
}

/// Base exception class for all application errors.
/// Provides structured error information for logging and user display.
class AppException extends Equatable implements Exception {
  final AppErrorCode code;
  final String message;
  final String? technicalDetails;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;
  final bool isRetryable;

  const AppException({
    required this.code,
    required this.message,
    this.technicalDetails,
    this.originalError,
    this.stackTrace,
    this.context,
    this.isRetryable = false,
  });

  /// Create from a generic exception
  factory AppException.fromException(
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    if (error is AppException) {
      return error;
    }

    final errorString = error.toString().toLowerCase();

    // Detect network errors
    if (errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('network')) {
      return AppException.network(
        message: 'Network connection failed',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    // Detect timeout errors
    if (errorString.contains('timeout') || errorString.contains('timed out')) {
      return AppException.timeout(
        message: 'Request timed out',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    // Detect auth errors
    if (errorString.contains('unauthorized') ||
        errorString.contains('unauthenticated') ||
        errorString.contains('jwt')) {
      return AppException.authRequired(
        message: 'Authentication required',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    // Detect rate limiting
    if (errorString.contains('rate limit') || errorString.contains('429')) {
      return AppException.rateLimited(
        message: 'Too many requests',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    // Default to unknown error
    return AppException(
      code: AppErrorCode.unknownError,
      message: 'An unexpected error occurred',
      technicalDetails: error.toString(),
      originalError: error,
      stackTrace: stackTrace,
      context: context,
      isRetryable: false,
    );
  }

  // ============================================================================
  // Network error factories
  // ============================================================================

  factory AppException.network({
    String message = 'Network error occurred',
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.networkError,
      message: message,
      technicalDetails: originalError?.toString(),
      originalError: originalError,
      stackTrace: stackTrace,
      context: context,
      isRetryable: true,
    );
  }

  factory AppException.timeout({
    String message = 'Request timed out',
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.networkTimeout,
      message: message,
      technicalDetails: originalError?.toString(),
      originalError: originalError,
      stackTrace: stackTrace,
      context: context,
      isRetryable: true,
    );
  }

  factory AppException.offline({
    String message = 'No internet connection',
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.networkOffline,
      message: message,
      context: context,
      isRetryable: true,
    );
  }

  // ============================================================================
  // Auth error factories
  // ============================================================================

  factory AppException.authRequired({
    String message = 'Please sign in to continue',
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.authRequired,
      message: message,
      technicalDetails: originalError?.toString(),
      originalError: originalError,
      stackTrace: stackTrace,
      context: context,
      isRetryable: false,
    );
  }

  factory AppException.sessionExpired({
    String message = 'Your session has expired. Please sign in again.',
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.authSessionExpired,
      message: message,
      context: context,
      isRetryable: false,
    );
  }

  // ============================================================================
  // Validation error factories
  // ============================================================================

  factory AppException.validation({
    required String message,
    String? field,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.validationError,
      message: message,
      context: {...?context, if (field != null) 'field': field},
      isRetryable: false,
    );
  }

  factory AppException.outOfRange({
    required String field,
    required num min,
    required num max,
    num? actual,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.validationOutOfRange,
      message: '$field must be between $min and $max',
      context: {
        ...?context,
        'field': field,
        'min': min,
        'max': max,
        if (actual != null) 'actual': actual,
      },
      isRetryable: false,
    );
  }

  // ============================================================================
  // Permission error factories
  // ============================================================================

  factory AppException.forbidden({
    String message = 'You do not have permission to perform this action',
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.forbidden,
      message: message,
      context: context,
      isRetryable: false,
    );
  }

  factory AppException.rateLimited({
    String message = 'Too many requests. Please wait before trying again.',
    int? retryAfterSeconds,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.rateLimited,
      message: message,
      technicalDetails: originalError?.toString(),
      originalError: originalError,
      stackTrace: stackTrace,
      context: {
        ...?context,
        if (retryAfterSeconds != null) 'retryAfterSeconds': retryAfterSeconds,
      },
      isRetryable: true,
    );
  }

  factory AppException.insufficientCredits({
    required int required,
    required int available,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.insufficientCredits,
      message: 'Insufficient credits. You need $required but have $available.',
      context: {
        ...?context,
        'required': required,
        'available': available,
      },
      isRetryable: false,
    );
  }

  // ============================================================================
  // Billing error factories
  // ============================================================================

  factory AppException.billingError({
    required String message,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.billingError,
      message: message,
      technicalDetails: originalError?.toString(),
      originalError: originalError,
      stackTrace: stackTrace,
      context: context,
      isRetryable: false,
    );
  }

  factory AppException.paymentFailed({
    String message = 'Payment failed. Please try again or use a different payment method.',
    String? declineCode,
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.billingPaymentFailed,
      message: message,
      technicalDetails: originalError?.toString(),
      originalError: originalError,
      stackTrace: stackTrace,
      context: {
        ...?context,
        if (declineCode != null) 'declineCode': declineCode,
      },
      isRetryable: true,
    );
  }

  factory AppException.invalidCreditAmount({
    required int min,
    required int max,
    int? actual,
  }) {
    return AppException(
      code: AppErrorCode.billingInvalidAmount,
      message: 'Credit amount must be between $min and $max',
      context: {
        'min': min,
        'max': max,
        if (actual != null) 'actual': actual,
      },
      isRetryable: false,
    );
  }

  // ============================================================================
  // Chat error factories
  // ============================================================================

  factory AppException.chatNotFound({
    int? chatId,
    String? inviteCode,
  }) {
    return AppException(
      code: AppErrorCode.chatNotFound,
      message: 'Chat not found',
      context: {
        if (chatId != null) 'chatId': chatId,
        if (inviteCode != null) 'inviteCode': inviteCode,
      },
      isRetryable: false,
    );
  }

  // ============================================================================
  // Proposition error factories
  // ============================================================================

  factory AppException.propositionLimitReached({
    required int limit,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.propositionLimitReached,
      message: 'You have reached the limit of $limit propositions for this round',
      context: {...?context, 'limit': limit},
      isRetryable: false,
    );
  }

  factory AppException.roundClosed({
    String message = 'This round is no longer accepting submissions',
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.propositionRoundClosed,
      message: message,
      context: context,
      isRetryable: false,
    );
  }

  // ============================================================================
  // Server error factories
  // ============================================================================

  factory AppException.serverError({
    String message = 'A server error occurred. Please try again later.',
    dynamic originalError,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return AppException(
      code: AppErrorCode.serverError,
      message: message,
      technicalDetails: originalError?.toString(),
      originalError: originalError,
      stackTrace: stackTrace,
      context: context,
      isRetryable: true,
    );
  }

  // ============================================================================
  // Helper methods
  // ============================================================================

  /// Returns true if this error should be reported to error tracking
  bool get shouldReport {
    switch (code) {
      case AppErrorCode.validationError:
      case AppErrorCode.validationInvalidInput:
      case AppErrorCode.validationMissingField:
      case AppErrorCode.validationOutOfRange:
      case AppErrorCode.authRequired:
      case AppErrorCode.authSessionExpired:
      case AppErrorCode.rateLimited:
      case AppErrorCode.networkOffline:
        return false;
      default:
        return true;
    }
  }

  /// Returns the error code as a string for logging
  String get codeString => code.name;

  @override
  List<Object?> get props => [code, message, technicalDetails, context];

  @override
  String toString() {
    final buffer = StringBuffer('AppException($codeString): $message');
    if (technicalDetails != null) {
      buffer.write(' [$technicalDetails]');
    }
    return buffer.toString();
  }

  /// Convert to JSON for logging/reporting
  Map<String, dynamic> toJson() {
    return {
      'code': codeString,
      'message': message,
      if (technicalDetails != null) 'technicalDetails': technicalDetails,
      if (context != null) 'context': context,
      'isRetryable': isRetryable,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
