import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/core/errors/errors.dart';

void main() {
  group('ErrorHandler', () {
    late List<Map<String, dynamic>> loggedErrors;
    late List<AppException> reportedErrors;

    setUp(() {
      loggedErrors = [];
      reportedErrors = [];

      // Reset singleton and configure with test callbacks
      ErrorHandler(
        logCallback: (level, message, data) {
          loggedErrors.add({
            'level': level,
            'message': message,
            'data': data,
          });
        },
        reportCallback: (error, stackTrace) async {
          reportedErrors.add(error);
        },
      );
    });

    group('handle()', () {
      test('converts generic exception to AppException', () {
        final result = ErrorHandler.instance.handle(
          Exception('network connection failed'),
        );

        expect(result, isA<AppException>());
        expect(result.code, AppErrorCode.networkError);
      });

      test('returns AppException unchanged', () {
        final original = AppException.serverError();
        final result = ErrorHandler.instance.handle(original);

        expect(identical(result, original), isTrue);
      });

      test('logs the error', () {
        ErrorHandler.instance.handle(AppException.serverError());

        expect(loggedErrors, hasLength(1));
        expect(loggedErrors.first['level'], 'error');
      });

      test('reports errors that should be reported', () {
        ErrorHandler.instance.handle(AppException.serverError());

        expect(reportedErrors, hasLength(1));
        expect(reportedErrors.first.code, AppErrorCode.serverError);
      });

      test('does not report validation errors', () {
        ErrorHandler.instance.handle(
          AppException.validation(message: 'test'),
        );

        expect(reportedErrors, isEmpty);
      });

      test('does not report when report=false', () {
        ErrorHandler.instance.handle(
          AppException.serverError(),
          report: false,
        );

        expect(reportedErrors, isEmpty);
      });

      test('includes context in error', () {
        final result = ErrorHandler.instance.handle(
          Exception('test'),
          context: {'userId': 123},
        );

        expect(result.context?['userId'], 123);
      });
    });

    group('wrapAsync()', () {
      test('returns result on success', () async {
        final result = await ErrorHandler.instance.wrapAsync(
          () async => 42,
        );

        expect(result, 42);
      });

      test('converts exception to AppException on failure', () async {
        expect(
          () => ErrorHandler.instance.wrapAsync(
            () async => throw Exception('network error'),
          ),
          throwsA(isA<AppException>()),
        );
      });

      test('calls onError callback if provided', () async {
        AppException? capturedError;
        final result = await ErrorHandler.instance.wrapAsync(
          () async => throw Exception('test'),
          onError: (error) {
            capturedError = error;
            return -1;
          },
        );

        expect(result, -1);
        expect(capturedError, isNotNull);
      });

      test('includes context in error', () async {
        try {
          await ErrorHandler.instance.wrapAsync(
            () async => throw Exception('test'),
            context: {'operation': 'fetchData'},
          );
        } on AppException catch (e) {
          expect(e.context?['operation'], 'fetchData');
        }
      });
    });

    group('wrapWithRetry()', () {
      test('returns result on first success', () async {
        int attempts = 0;
        final result = await ErrorHandler.instance.wrapWithRetry(
          () async {
            attempts++;
            return 'success';
          },
        );

        expect(result, 'success');
        expect(attempts, 1);
      });

      test('retries on retryable error', () async {
        int attempts = 0;
        final result = await ErrorHandler.instance.wrapWithRetry(
          () async {
            attempts++;
            if (attempts < 3) {
              throw AppException.network();
            }
            return 'success';
          },
          initialDelay: const Duration(milliseconds: 1),
        );

        expect(result, 'success');
        expect(attempts, 3);
      });

      test('gives up after maxRetries', () async {
        expect(
          () => ErrorHandler.instance.wrapWithRetry(
            () async {
              throw AppException.network();
            },
            maxRetries: 3,
            initialDelay: const Duration(milliseconds: 1),
          ),
          throwsA(isA<AppException>()),
        );
      });

      test('does not retry non-retryable errors', () async {
        int attempts = 0;
        expect(
          () => ErrorHandler.instance.wrapWithRetry(
            () async {
              attempts++;
              throw AppException.authRequired();
            },
            initialDelay: const Duration(milliseconds: 1),
          ),
          throwsA(isA<AppException>()),
        );
        // Wait for async completion
        await Future.delayed(const Duration(milliseconds: 10));
        expect(attempts, 1);
      });

      test('only reports on final failure', () async {
        try {
          await ErrorHandler.instance.wrapWithRetry(
            () async => throw AppException.network(),
            maxRetries: 3,
            initialDelay: const Duration(milliseconds: 1),
          );
        } catch (_) {}

        // Should only report once (on final failure)
        expect(reportedErrors, hasLength(1));
      });
    });

    group('convenience functions', () {
      test('handleError() works', () {
        final result = handleError(Exception('test'));
        expect(result, isA<AppException>());
      });

      test('wrapAsync() works', () async {
        final result = await wrapAsync(() async => 42);
        expect(result, 42);
      });

      test('wrapWithRetry() works', () async {
        final result = await wrapWithRetry(
          () async => 'success',
          initialDelay: const Duration(milliseconds: 1),
        );
        expect(result, 'success');
      });
    });

    group('logging', () {
      test('info() logs at info level', () {
        ErrorHandler.instance.info('Test message', {'key': 'value'});

        expect(loggedErrors, hasLength(1));
        expect(loggedErrors.first['level'], 'info');
        expect(loggedErrors.first['message'], 'Test message');
      });

      test('warning() logs at warning level', () {
        ErrorHandler.instance.warning('Warning message');

        expect(loggedErrors, hasLength(1));
        expect(loggedErrors.first['level'], 'warning');
      });

      test('debug() logs at debug level', () {
        ErrorHandler.instance.debug('Debug message');

        expect(loggedErrors, hasLength(1));
        expect(loggedErrors.first['level'], 'debug');
      });
    });
  });
}
