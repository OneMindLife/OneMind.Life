import 'app_exception.dart';

/// User-friendly error messages for each error code.
/// These are designed to be clear and actionable for end users.
class ErrorMessages {
  ErrorMessages._();

  /// Default messages for each error code
  static const Map<AppErrorCode, String> _defaultMessages = {
    // Network errors
    AppErrorCode.networkError:
        'Unable to connect. Please check your internet connection and try again.',
    AppErrorCode.networkTimeout:
        'The request is taking too long. Please try again.',
    AppErrorCode.networkOffline:
        'You appear to be offline. Please check your internet connection.',

    // Auth errors
    AppErrorCode.authRequired:
        'Please sign in to continue.',
    AppErrorCode.authInvalidToken:
        'Your session is invalid. Please sign in again.',
    AppErrorCode.authSessionExpired:
        'Your session has expired. Please sign in again.',

    // Validation errors
    AppErrorCode.validationError:
        'Please check your input and try again.',
    AppErrorCode.validationInvalidInput:
        'Invalid input. Please check and try again.',
    AppErrorCode.validationMissingField:
        'Please fill in all required fields.',
    AppErrorCode.validationOutOfRange:
        'Value is out of the allowed range.',

    // Resource errors
    AppErrorCode.notFound:
        'The requested item could not be found.',
    AppErrorCode.alreadyExists:
        'This item already exists.',
    AppErrorCode.conflict:
        'A conflict occurred. Please refresh and try again.',

    // Permission errors
    AppErrorCode.forbidden:
        'You don\'t have permission to do this.',
    AppErrorCode.rateLimited:
        'Too many requests. Please wait a moment and try again.',
    AppErrorCode.insufficientCredits:
        'You don\'t have enough credits. Please purchase more to continue.',

    // Billing errors
    AppErrorCode.billingError:
        'A billing error occurred. Please try again or contact support.',
    AppErrorCode.billingPaymentFailed:
        'Payment failed. Please try again or use a different payment method.',
    AppErrorCode.billingPaymentDeclined:
        'Your payment was declined. Please try a different payment method.',
    AppErrorCode.billingInvalidAmount:
        'Invalid credit amount. Please enter a valid number.',
    AppErrorCode.billingWebhookError:
        'Payment processing error. If charged, credits will appear shortly.',

    // Chat errors
    AppErrorCode.chatNotFound:
        'Chat not found. It may have been deleted or the link is invalid.',
    AppErrorCode.chatClosed:
        'This chat is no longer active.',
    AppErrorCode.chatFull:
        'This chat is full and not accepting new participants.',

    // Participant errors
    AppErrorCode.participantNotFound:
        'You are not a participant in this chat.',
    AppErrorCode.participantKicked:
        'You have been removed from this chat.',
    AppErrorCode.participantNotActive:
        'Your participation is not active.',

    // Proposition errors
    AppErrorCode.propositionLimitReached:
        'You\'ve reached the maximum number of propositions for this round.',
    AppErrorCode.propositionRoundClosed:
        'This round is closed for new propositions.',
    AppErrorCode.propositionDuplicate:
        'You\'ve already submitted this proposition.',

    // Rating errors
    AppErrorCode.ratingAlreadySubmitted:
        'You\'ve already submitted your ratings for this round.',
    AppErrorCode.ratingRoundClosed:
        'The rating period has ended for this round.',
    AppErrorCode.ratingInvalidValue:
        'Invalid rating value. Please use the slider to rate.',

    // Server errors
    AppErrorCode.serverError:
        'Something went wrong on our end. Please try again later.',
    AppErrorCode.serverMaintenance:
        'The service is temporarily unavailable for maintenance.',
    AppErrorCode.unknownError:
        'An unexpected error occurred. Please try again.',
  };

  /// Action suggestions for each error code
  static const Map<AppErrorCode, String> _actionSuggestions = {
    AppErrorCode.networkError: 'Check your Wi-Fi or mobile data connection.',
    AppErrorCode.networkTimeout: 'Try again in a few seconds.',
    AppErrorCode.networkOffline: 'Connect to the internet to continue.',
    AppErrorCode.authRequired: 'Tap "Sign In" to continue.',
    AppErrorCode.authSessionExpired: 'Tap "Sign In" to continue.',
    AppErrorCode.rateLimited: 'Wait 30 seconds before trying again.',
    AppErrorCode.insufficientCredits: 'Tap "Buy Credits" to purchase more.',
    AppErrorCode.billingPaymentFailed: 'Check your card details or try another card.',
    AppErrorCode.billingPaymentDeclined: 'Contact your bank or use a different card.',
    AppErrorCode.serverError: 'If the problem persists, contact support.',
  };

  /// Get the user-friendly message for an error
  static String getMessage(AppException error) {
    // Use the exception's message if it's already user-friendly
    if (!error.message.contains('Exception:') &&
        !error.message.contains('Error:') &&
        error.message.length < 200) {
      return error.message;
    }
    // Otherwise use the default message for the error code
    return _defaultMessages[error.code] ?? _defaultMessages[AppErrorCode.unknownError]!;
  }

  /// Get the action suggestion for an error
  static String? getActionSuggestion(AppException error) {
    return _actionSuggestions[error.code];
  }

  /// Get a complete error display with message and action
  static ErrorDisplay getDisplay(AppException error) {
    return ErrorDisplay(
      title: _getTitleForCode(error.code),
      message: getMessage(error),
      actionSuggestion: getActionSuggestion(error),
      isRetryable: error.isRetryable,
      errorCode: error.codeString,
    );
  }

  static String _getTitleForCode(AppErrorCode code) {
    switch (code) {
      case AppErrorCode.networkError:
      case AppErrorCode.networkTimeout:
      case AppErrorCode.networkOffline:
        return 'Connection Error';
      case AppErrorCode.authRequired:
      case AppErrorCode.authInvalidToken:
      case AppErrorCode.authSessionExpired:
        return 'Sign In Required';
      case AppErrorCode.validationError:
      case AppErrorCode.validationInvalidInput:
      case AppErrorCode.validationMissingField:
      case AppErrorCode.validationOutOfRange:
        return 'Invalid Input';
      case AppErrorCode.forbidden:
      case AppErrorCode.rateLimited:
        return 'Access Denied';
      case AppErrorCode.insufficientCredits:
        return 'Insufficient Credits';
      case AppErrorCode.billingError:
      case AppErrorCode.billingPaymentFailed:
      case AppErrorCode.billingPaymentDeclined:
      case AppErrorCode.billingInvalidAmount:
        return 'Payment Error';
      case AppErrorCode.chatNotFound:
      case AppErrorCode.chatClosed:
      case AppErrorCode.chatFull:
        return 'Chat Unavailable';
      case AppErrorCode.propositionLimitReached:
      case AppErrorCode.propositionRoundClosed:
      case AppErrorCode.ratingAlreadySubmitted:
      case AppErrorCode.ratingRoundClosed:
        return 'Round Closed';
      case AppErrorCode.serverError:
      case AppErrorCode.serverMaintenance:
        return 'Server Error';
      default:
        return 'Error';
    }
  }
}

/// Display information for an error
class ErrorDisplay {
  final String title;
  final String message;
  final String? actionSuggestion;
  final bool isRetryable;
  final String errorCode;

  const ErrorDisplay({
    required this.title,
    required this.message,
    this.actionSuggestion,
    required this.isRetryable,
    required this.errorCode,
  });

  /// Get the full message including action suggestion
  String get fullMessage {
    if (actionSuggestion != null) {
      return '$message\n\n$actionSuggestion';
    }
    return message;
  }
}
