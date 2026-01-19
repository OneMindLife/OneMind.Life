import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/core/api/api_config.dart';

void main() {
  group('ApiConfig', () {
    group('timeout values', () {
      test('defaultTimeout is 30 seconds', () {
        expect(ApiConfig.defaultTimeout, const Duration(seconds: 30));
      });

      test('quickTimeout is 10 seconds', () {
        expect(ApiConfig.quickTimeout, const Duration(seconds: 10));
      });

      test('longTimeout is 60 seconds', () {
        expect(ApiConfig.longTimeout, const Duration(seconds: 60));
      });
    });

    group('retry configuration', () {
      test('defaultMaxRetries is 3', () {
        expect(ApiConfig.defaultMaxRetries, 3);
      });

      test('initialRetryDelay is 1 second', () {
        expect(ApiConfig.initialRetryDelay, const Duration(seconds: 1));
      });

      test('maxRetryDelay is 30 seconds', () {
        expect(ApiConfig.maxRetryDelay, const Duration(seconds: 30));
      });
    });

    group('getTimeout()', () {
      test('returns quickTimeout for select operations', () {
        expect(ApiConfig.getTimeout('select'), ApiConfig.quickTimeout);
        expect(ApiConfig.getTimeout('maybeSingle'), ApiConfig.quickTimeout);
        expect(ApiConfig.getTimeout('single'), ApiConfig.quickTimeout);
      });

      test('returns longTimeout for long operations', () {
        expect(ApiConfig.getTimeout('upload'), ApiConfig.longTimeout);
        expect(ApiConfig.getTimeout('download'), ApiConfig.longTimeout);
        expect(ApiConfig.getTimeout('batch'), ApiConfig.longTimeout);
      });

      test('returns defaultTimeout for unknown operations', () {
        expect(ApiConfig.getTimeout('insert'), ApiConfig.defaultTimeout);
        expect(ApiConfig.getTimeout('update'), ApiConfig.defaultTimeout);
        expect(ApiConfig.getTimeout('delete'), ApiConfig.defaultTimeout);
      });

      test('returns defaultTimeout for null operation type', () {
        expect(ApiConfig.getTimeout(null), ApiConfig.defaultTimeout);
      });
    });
  });
}
