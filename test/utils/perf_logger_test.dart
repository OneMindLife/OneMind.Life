import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/utils/perf_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit tests for the PerfLogger surface. We can't reach the Supabase
/// client without an integration env, so these focus on the contract
/// guarantees: it never throws, the disabled flag fully suppresses
/// emission, correlation IDs are unique, and `measure` returns the
/// underlying future's value (or rethrows the error).

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PerfLogger.enabled = false; // default to disabled — no DB calls in tests
  });

  group('correlation ids', () {
    test('start returns a UUID-shaped string', () {
      final id = PerfLogger.start('foo');
      expect(id, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('two starts produce distinct ids', () {
      final a = PerfLogger.start('foo');
      final b = PerfLogger.start('bar');
      expect(a, isNot(equals(b)));
    });

    test('100 starts produce 100 unique ids', () {
      final ids = List.generate(100, (_) => PerfLogger.start('x')).toSet();
      expect(ids.length, 100);
    });
  });

  group('no-throw contract', () {
    test('start does not throw even with no Supabase client wired up', () {
      expect(() => PerfLogger.start('action'), returnsNormally);
    });

    test('end does not throw for an unknown correlation id', () {
      expect(() => PerfLogger.end('not-a-real-id'), returnsNormally);
    });

    test('error does not throw', () {
      expect(() => PerfLogger.error('not-a-real-id', Exception('boom')),
          returnsNormally);
    });

    test('measure rethrows the underlying error', () async {
      Object? caught;
      try {
        await PerfLogger.measure<int>('action', () async {
          throw StateError('boom');
        });
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
    });

    test('measure returns the future value', () async {
      final out = await PerfLogger.measure<int>('action', () async => 42);
      expect(out, 42);
    });
  });

  group('enabled flag', () {
    test('start still returns a correlation id when disabled '
        '(callers can still wire it through their code)', () {
      PerfLogger.enabled = false;
      final id = PerfLogger.start('action');
      expect(id, isNotEmpty);
    });

    test('measure runs the function whether logging is enabled or not',
        () async {
      PerfLogger.enabled = false;
      final got = await PerfLogger.measure<String>('a', () async => 'ok');
      expect(got, 'ok');

      PerfLogger.enabled = true;
      final got2 = await PerfLogger.measure<String>('a', () async => 'ok2');
      expect(got2, 'ok2');
    });
  });
}
