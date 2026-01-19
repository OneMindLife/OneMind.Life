import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/core/errors/errors.dart';

void main() {
  group('ErrorMessages', () {
    group('getMessage()', () {
      test('returns user-friendly message for network error', () {
        final error = AppException.network();
        final message = ErrorMessages.getMessage(error);

        // Message should be user-friendly, not contain "Exception:"
        expect(message, isNot(contains('Exception:')));
        expect(message.length, greaterThan(10));
      });

      test('returns user-friendly message for auth required', () {
        final error = AppException.authRequired();
        final message = ErrorMessages.getMessage(error);

        expect(message.toLowerCase(), contains('sign in'));
      });

      test('returns user-friendly message for rate limited', () {
        final error = AppException.rateLimited();
        final message = ErrorMessages.getMessage(error);

        // Should mention waiting or trying again
        expect(message.toLowerCase(), anyOf(contains('wait'), contains('try')));
      });

      test('returns user-friendly message for insufficient credits', () {
        final error = AppException.insufficientCredits(
          required: 100,
          available: 50,
        );
        final message = ErrorMessages.getMessage(error);

        // Uses error's message since it's already user-friendly
        expect(message.toLowerCase(), contains('credits'));
      });

      test('returns user-friendly message for payment failed', () {
        final error = AppException.paymentFailed();
        final message = ErrorMessages.getMessage(error);

        expect(message.toLowerCase(), contains('payment'));
        expect(message.toLowerCase(), isNot(contains('exception:')));
      });

      test('returns user-friendly message for server error', () {
        final error = AppException.serverError();
        final message = ErrorMessages.getMessage(error);

        expect(message.toLowerCase(), anyOf(contains('try again'), contains('error')));
      });

      test('strips technical details from exception messages', () {
        final error = AppException(
          code: AppErrorCode.unknownError,
          message: 'Exception: PostgrestError(details: null, code: PGRST)',
        );
        final message = ErrorMessages.getMessage(error);

        // Should use default message, not the technical one
        expect(message, isNot(contains('PostgrestError')));
      });
    });

    group('getActionSuggestion()', () {
      test('returns suggestion for network error', () {
        final error = AppException.network();
        final suggestion = ErrorMessages.getActionSuggestion(error);

        expect(suggestion, isNotNull);
        expect(suggestion, contains('Wi-Fi'));
      });

      test('returns suggestion for rate limited', () {
        final error = AppException.rateLimited();
        final suggestion = ErrorMessages.getActionSuggestion(error);

        expect(suggestion, isNotNull);
        expect(suggestion, contains('Wait'));
      });

      test('returns suggestion for insufficient credits', () {
        final error = AppException.insufficientCredits(
          required: 10,
          available: 5,
        );
        final suggestion = ErrorMessages.getActionSuggestion(error);

        expect(suggestion, isNotNull);
        expect(suggestion, contains('Buy Credits'));
      });

      test('returns null for errors without suggestions', () {
        final error = AppException.chatNotFound();
        final suggestion = ErrorMessages.getActionSuggestion(error);

        expect(suggestion, isNull);
      });
    });

    group('getDisplay()', () {
      test('returns ErrorDisplay with all fields', () {
        final error = AppException.network();
        final display = ErrorMessages.getDisplay(error);

        expect(display.title, isNotEmpty);
        expect(display.message, isNotEmpty);
        expect(display.isRetryable, isTrue);
        expect(display.errorCode, 'networkError');
      });

      test('title is appropriate for error type', () {
        expect(
          ErrorMessages.getDisplay(AppException.network()).title,
          'Connection Error',
        );
        expect(
          ErrorMessages.getDisplay(AppException.authRequired()).title,
          'Sign In Required',
        );
        expect(
          ErrorMessages.getDisplay(AppException.paymentFailed()).title,
          'Payment Error',
        );
        expect(
          ErrorMessages.getDisplay(AppException.insufficientCredits(
            required: 10,
            available: 5,
          )).title,
          'Insufficient Credits',
        );
      });

      test('fullMessage includes action suggestion when present', () {
        final error = AppException.network();
        final display = ErrorMessages.getDisplay(error);

        expect(display.fullMessage, contains(display.message));
        expect(display.fullMessage, contains(display.actionSuggestion!));
      });

      test('fullMessage equals message when no suggestion', () {
        final error = AppException.chatNotFound();
        final display = ErrorMessages.getDisplay(error);

        expect(display.fullMessage, display.message);
      });
    });
  });

  group('ErrorDisplay', () {
    test('fullMessage with action suggestion', () {
      const display = ErrorDisplay(
        title: 'Error',
        message: 'Something went wrong.',
        actionSuggestion: 'Try again later.',
        isRetryable: true,
        errorCode: 'test',
      );

      expect(display.fullMessage, 'Something went wrong.\n\nTry again later.');
    });

    test('fullMessage without action suggestion', () {
      const display = ErrorDisplay(
        title: 'Error',
        message: 'Something went wrong.',
        isRetryable: false,
        errorCode: 'test',
      );

      expect(display.fullMessage, 'Something went wrong.');
    });
  });
}
