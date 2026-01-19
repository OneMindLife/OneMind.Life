import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/core/errors/errors.dart';

void main() {
  group('AppException', () {
    group('factory constructors', () {
      test('network() creates retryable network error', () {
        final error = AppException.network(message: 'Connection failed');

        expect(error.code, AppErrorCode.networkError);
        expect(error.message, 'Connection failed');
        expect(error.isRetryable, isTrue);
      });

      test('timeout() creates retryable timeout error', () {
        final error = AppException.timeout();

        expect(error.code, AppErrorCode.networkTimeout);
        expect(error.isRetryable, isTrue);
      });

      test('offline() creates retryable offline error', () {
        final error = AppException.offline();

        expect(error.code, AppErrorCode.networkOffline);
        expect(error.isRetryable, isTrue);
      });

      test('authRequired() creates non-retryable auth error', () {
        final error = AppException.authRequired();

        expect(error.code, AppErrorCode.authRequired);
        expect(error.isRetryable, isFalse);
      });

      test('sessionExpired() creates non-retryable auth error', () {
        final error = AppException.sessionExpired();

        expect(error.code, AppErrorCode.authSessionExpired);
        expect(error.isRetryable, isFalse);
      });

      test('validation() creates non-retryable validation error', () {
        final error = AppException.validation(
          message: 'Invalid email',
          field: 'email',
        );

        expect(error.code, AppErrorCode.validationError);
        expect(error.message, 'Invalid email');
        expect(error.context?['field'], 'email');
        expect(error.isRetryable, isFalse);
      });

      test('outOfRange() creates error with min/max context', () {
        final error = AppException.outOfRange(
          field: 'credits',
          min: 1,
          max: 100,
          actual: 0,
        );

        expect(error.code, AppErrorCode.validationOutOfRange);
        expect(error.message, 'credits must be between 1 and 100');
        expect(error.context?['min'], 1);
        expect(error.context?['max'], 100);
        expect(error.context?['actual'], 0);
      });

      test('rateLimited() is retryable with retry info', () {
        final error = AppException.rateLimited(retryAfterSeconds: 30);

        expect(error.code, AppErrorCode.rateLimited);
        expect(error.isRetryable, isTrue);
        expect(error.context?['retryAfterSeconds'], 30);
      });

      test('insufficientCredits() includes required and available', () {
        final error = AppException.insufficientCredits(
          required: 100,
          available: 50,
        );

        expect(error.code, AppErrorCode.insufficientCredits);
        expect(error.message, contains('100'));
        expect(error.message, contains('50'));
        expect(error.context?['required'], 100);
        expect(error.context?['available'], 50);
      });

      test('paymentFailed() is retryable', () {
        final error = AppException.paymentFailed(declineCode: 'insufficient_funds');

        expect(error.code, AppErrorCode.billingPaymentFailed);
        expect(error.isRetryable, isTrue);
        expect(error.context?['declineCode'], 'insufficient_funds');
      });

      test('serverError() is retryable', () {
        final error = AppException.serverError();

        expect(error.code, AppErrorCode.serverError);
        expect(error.isRetryable, isTrue);
      });
    });

    group('fromException()', () {
      test('returns same error if already AppException', () {
        final original = AppException.network();
        final result = AppException.fromException(original);

        expect(identical(result, original), isTrue);
      });

      test('detects network errors from exception message', () {
        final error = AppException.fromException(
          Exception('socket connection refused'),
        );

        expect(error.code, AppErrorCode.networkError);
        expect(error.isRetryable, isTrue);
      });

      test('detects timeout errors from exception message', () {
        final error = AppException.fromException(
          Exception('request timed out after 30s'),
        );

        expect(error.code, AppErrorCode.networkTimeout);
        expect(error.isRetryable, isTrue);
      });

      test('detects auth errors from exception message', () {
        final error = AppException.fromException(
          Exception('unauthorized: invalid jwt token'),
        );

        expect(error.code, AppErrorCode.authRequired);
      });

      test('detects rate limiting from exception message', () {
        final error = AppException.fromException(
          Exception('rate limit exceeded (429)'),
        );

        expect(error.code, AppErrorCode.rateLimited);
        expect(error.isRetryable, isTrue);
      });

      test('falls back to unknown error for unrecognized exceptions', () {
        final error = AppException.fromException(
          Exception('some random error'),
        );

        expect(error.code, AppErrorCode.unknownError);
        expect(error.isRetryable, isFalse);
      });

      test('preserves stack trace', () {
        final stackTrace = StackTrace.current;
        final error = AppException.fromException(
          Exception('test'),
          stackTrace: stackTrace,
        );

        expect(error.stackTrace, stackTrace);
      });

      test('preserves context', () {
        final error = AppException.fromException(
          Exception('test'),
          context: {'userId': 123},
        );

        expect(error.context?['userId'], 123);
      });
    });

    group('shouldReport', () {
      test('returns false for validation errors', () {
        expect(AppException.validation(message: 'test').shouldReport, isFalse);
      });

      test('returns false for auth required', () {
        expect(AppException.authRequired().shouldReport, isFalse);
      });

      test('returns false for rate limited', () {
        expect(AppException.rateLimited().shouldReport, isFalse);
      });

      test('returns false for offline', () {
        expect(AppException.offline().shouldReport, isFalse);
      });

      test('returns true for server errors', () {
        expect(AppException.serverError().shouldReport, isTrue);
      });

      test('returns true for payment errors', () {
        expect(AppException.paymentFailed().shouldReport, isTrue);
      });

      test('returns true for network errors', () {
        expect(AppException.network().shouldReport, isTrue);
      });
    });

    group('toJson()', () {
      test('includes all relevant fields', () {
        final error = AppException(
          code: AppErrorCode.billingError,
          message: 'Payment failed',
          technicalDetails: 'Stripe error: card_declined',
          context: {'amount': 100},
          isRetryable: true,
        );

        final json = error.toJson();

        expect(json['code'], 'billingError');
        expect(json['message'], 'Payment failed');
        expect(json['technicalDetails'], 'Stripe error: card_declined');
        expect(json['context'], {'amount': 100});
        expect(json['isRetryable'], isTrue);
        expect(json['timestamp'], isNotNull);
      });

      test('omits null fields', () {
        final error = AppException(
          code: AppErrorCode.unknownError,
          message: 'Test',
        );

        final json = error.toJson();

        expect(json.containsKey('technicalDetails'), isFalse);
        expect(json.containsKey('context'), isFalse);
      });
    });

    group('toString()', () {
      test('includes code and message', () {
        final error = AppException(
          code: AppErrorCode.networkError,
          message: 'Connection failed',
        );

        expect(error.toString(), contains('networkError'));
        expect(error.toString(), contains('Connection failed'));
      });

      test('includes technical details if present', () {
        final error = AppException(
          code: AppErrorCode.serverError,
          message: 'Server error',
          technicalDetails: 'HTTP 500',
        );

        expect(error.toString(), contains('HTTP 500'));
      });
    });

    group('equality', () {
      test('equal errors have same props', () {
        final error1 = AppException(
          code: AppErrorCode.networkError,
          message: 'Test',
          context: {'key': 'value'},
        );
        final error2 = AppException(
          code: AppErrorCode.networkError,
          message: 'Test',
          context: {'key': 'value'},
        );

        expect(error1, equals(error2));
      });

      test('different codes are not equal', () {
        final error1 = AppException(
          code: AppErrorCode.networkError,
          message: 'Test',
        );
        final error2 = AppException(
          code: AppErrorCode.serverError,
          message: 'Test',
        );

        expect(error1, isNot(equals(error2)));
      });
    });
  });
}
