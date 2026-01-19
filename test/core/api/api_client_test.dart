import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/api/api_client.dart';
import 'package:onemind_app/core/api/api_config.dart';
import 'package:onemind_app/core/errors/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Mock classes
class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late MockSupabaseClient mockClient;
  late ApiClient apiClient;

  setUp(() {
    // Reset singleton to ensure test isolation
    ErrorHandler.resetInstance();
    mockClient = MockSupabaseClient();
    apiClient = ApiClient(mockClient);
  });

  group('ApiClient', () {
    group('execute()', () {
      test('returns result on successful operation', () async {
        final result = await apiClient.execute(() async => {'id': 1, 'name': 'Test'});

        expect(result, {'id': 1, 'name': 'Test'});
      });

      test('throws AppException.timeout on timeout', () async {
        expect(
          () async => await apiClient.execute(
            () async {
              await Future.delayed(const Duration(seconds: 5));
              return null;
            },
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.networkTimeout)
                .having((e) => e.isRetryable, 'isRetryable', true),
          ),
        );
      });

      test('applies correct timeout based on operation type', () async {
        // Quick operation should use quickTimeout
        final timeout = ApiConfig.getTimeout('select');
        expect(timeout, ApiConfig.quickTimeout);

        // Long operation should use longTimeout
        final longTimeout = ApiConfig.getTimeout('upload');
        expect(longTimeout, ApiConfig.longTimeout);
      });

      test('converts PostgrestException to AppException', () async {
        expect(
          () async => await apiClient.execute(() async {
            throw PostgrestException(
              message: 'Connection failed',
              code: '500',
            );
          }),
          throwsA(isA<AppException>()),
        );
      });

      test('handles network errors from PostgrestException', () async {
        expect(
          () async => await apiClient.execute(() async {
            throw PostgrestException(
              message: 'network connection failed',
              code: '0',
            );
          }),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.networkError),
          ),
        );
      });

      test('handles auth errors from PostgrestException', () async {
        expect(
          () async => await apiClient.execute(() async {
            throw PostgrestException(
              message: 'Unauthorized',
              code: '401',
            );
          }),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.authRequired),
          ),
        );
      });

      test('handles unique constraint violation', () async {
        expect(
          () async => await apiClient.execute(() async {
            throw PostgrestException(
              message: 'duplicate key value violates unique constraint',
              code: '23505',
            );
          }),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.validationError)
                .having((e) => e.isRetryable, 'isRetryable', false),
          ),
        );
      });

      test('handles not found error', () async {
        expect(
          () async => await apiClient.execute(() async {
            throw PostgrestException(
              message: 'Row not found',
              code: 'PGRST116',
            );
          }),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.chatNotFound),
          ),
        );
      });

      test('handles AuthException with expired token', () async {
        expect(
          () async => await apiClient.execute(() async {
            throw AuthException('Token expired');
          }),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.authSessionExpired),
          ),
        );
      });

      test('handles AuthException with invalid token', () async {
        expect(
          () async => await apiClient.execute(() async {
            throw AuthException('Invalid token');
          }),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.authInvalidToken),
          ),
        );
      });
    });

    group('executeWithRetry()', () {
      test('returns result on first successful attempt', () async {
        int attempts = 0;

        final result = await apiClient.executeWithRetry(() async {
          attempts++;
          return 'success';
        });

        expect(result, 'success');
        expect(attempts, 1);
      });

      test('retries on retryable error and succeeds', () async {
        int attempts = 0;

        final result = await apiClient.executeWithRetry(
          () async {
            attempts++;
            if (attempts < 3) {
              throw AppException.network();
            }
            return 'success after retry';
          },
          initialDelay: const Duration(milliseconds: 10),
        );

        expect(result, 'success after retry');
        expect(attempts, 3);
      });

      test('throws after max retries exceeded', () async {
        int attempts = 0;
        AppException? caughtException;

        try {
          await apiClient.executeWithRetry(
            () async {
              attempts++;
              throw AppException.network();
            },
            maxRetries: 3,
            initialDelay: const Duration(milliseconds: 1),
          );
        } on AppException catch (e) {
          caughtException = e;
        }

        expect(
          caughtException,
          isA<AppException>().having((e) => e.code, 'code', AppErrorCode.networkError),
        );
        expect(attempts, 3);
      });

      test('does not retry non-retryable errors', () async {
        int attempts = 0;

        await expectLater(
          () => apiClient.executeWithRetry(
            () async {
              attempts++;
              throw AppException(
                code: AppErrorCode.validationError,
                message: 'Invalid input',
                isRetryable: false,
              );
            },
            initialDelay: const Duration(milliseconds: 10),
          ),
          throwsA(isA<AppException>()),
        );

        expect(attempts, 1); // Should not retry
      });

      test('uses exponential backoff', () async {
        final timestamps = <DateTime>[];
        int attempts = 0;

        try {
          await apiClient.executeWithRetry(
            () async {
              attempts++;
              timestamps.add(DateTime.now());
              throw AppException.network();
            },
            maxRetries: 3,
            initialDelay: const Duration(milliseconds: 50),
          );
        } catch (_) {}

        expect(attempts, 3);
        // Verify delays increased (approximately)
        if (timestamps.length >= 3) {
          final delay1 = timestamps[1].difference(timestamps[0]).inMilliseconds;
          final delay2 = timestamps[2].difference(timestamps[1]).inMilliseconds;
          // Second delay should be roughly double the first
          expect(delay2, greaterThan(delay1));
        }
      });
    });

    // Note: rpc() tests require complex mocking of PostgrestFilterBuilder
    // These are tested indirectly through integration tests;

    group('SupabaseClientExtension', () {
      test('withTimeout returns result on success', () async {
        final result = await mockClient.withTimeout(
          () async => 'test result',
        );
        expect(result, 'test result');
      });

      test('withTimeout throws AppException.timeout on timeout', () async {
        expect(
          () async => await mockClient.withTimeout(
            () async {
              await Future.delayed(const Duration(seconds: 5));
              return null;
            },
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', AppErrorCode.networkTimeout),
          ),
        );
      });
    });
  });

  group('timeout scenarios', () {
    test('short timeout catches slow operations', () async {
      expect(
        () async => await apiClient.execute(
          () async {
            await Future.delayed(const Duration(milliseconds: 200));
            return null;
          },
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('long timeout allows slow operations', () async {
      final result = await apiClient.execute(
        () async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 'completed';
        },
        timeout: const Duration(milliseconds: 500),
      );

      expect(result, 'completed');
    });
  });

  group('error handling edge cases', () {
    test('handles server error (5xx)', () async {
      expect(
        () async => await apiClient.execute(() async {
          throw PostgrestException(
            message: 'Internal server error',
            code: '500',
          );
        }),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', AppErrorCode.serverError)
              .having((e) => e.isRetryable, 'isRetryable', true),
        ),
      );
    });

    test('handles RLS error', () async {
      expect(
        () async => await apiClient.execute(() async {
          throw PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          );
        }),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', AppErrorCode.validationError),
        ),
      );
    });

    test('handles foreign key violation', () async {
      expect(
        () async => await apiClient.execute(() async {
          throw PostgrestException(
            message: 'insert or update on table violates foreign key constraint',
            code: '23503',
          );
        }),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', AppErrorCode.validationError)
              .having((e) => e.isRetryable, 'isRetryable', false),
        ),
      );
    });

    test('handles generic auth exception', () async {
      expect(
        () async => await apiClient.execute(() async {
          throw AuthException('Authentication failed');
        }),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', AppErrorCode.authRequired),
        ),
      );
    });
  });
}
