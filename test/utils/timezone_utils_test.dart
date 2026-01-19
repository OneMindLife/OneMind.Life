import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/utils/timezone_utils.dart';

void main() {
  group('allTimezones', () {
    test('contains common US timezones', () {
      expect(allTimezones, contains('America/New_York'));
      expect(allTimezones, contains('America/Chicago'));
      expect(allTimezones, contains('America/Denver'));
      expect(allTimezones, contains('America/Los_Angeles'));
      expect(allTimezones, contains('America/Anchorage'));
      expect(allTimezones, contains('Pacific/Honolulu'));
    });

    test('contains common European timezones', () {
      expect(allTimezones, contains('Europe/London'));
      expect(allTimezones, contains('Europe/Paris'));
      expect(allTimezones, contains('Europe/Berlin'));
      expect(allTimezones, contains('Europe/Madrid'));
      expect(allTimezones, contains('Europe/Rome'));
      expect(allTimezones, contains('Europe/Moscow'));
    });

    test('contains common Asian timezones', () {
      expect(allTimezones, contains('Asia/Tokyo'));
      expect(allTimezones, contains('Asia/Shanghai'));
      expect(allTimezones, contains('Asia/Hong_Kong'));
      expect(allTimezones, contains('Asia/Singapore'));
      expect(allTimezones, contains('Asia/Seoul'));
      expect(allTimezones, contains('Asia/Dubai'));
      expect(allTimezones, contains('Asia/Kolkata'));
    });

    test('contains Oceania timezones', () {
      expect(allTimezones, contains('Australia/Sydney'));
      expect(allTimezones, contains('Australia/Melbourne'));
      expect(allTimezones, contains('Pacific/Auckland'));
    });

    test('contains African timezones', () {
      expect(allTimezones, contains('Africa/Cairo'));
      expect(allTimezones, contains('Africa/Johannesburg'));
      expect(allTimezones, contains('Africa/Lagos'));
      expect(allTimezones, contains('Africa/Nairobi'));
    });

    test('contains UTC', () {
      expect(allTimezones, contains('UTC'));
    });

    test('has comprehensive timezone coverage (290+)', () {
      expect(allTimezones.length, greaterThan(290));
    });

    test('has no duplicates', () {
      final uniqueTimezones = allTimezones.toSet();
      expect(uniqueTimezones.length, allTimezones.length);
    });

    test('common timezones appear first in list', () {
      // Verify US timezones are at the start
      final nyIndex = allTimezones.indexOf('America/New_York');
      final laIndex = allTimezones.indexOf('America/Los_Angeles');
      expect(nyIndex, lessThan(10));
      expect(laIndex, lessThan(10));
    });
  });

  group('mapOffsetToTimezone', () {
    test('maps standard hour offsets', () {
      expect(mapOffsetToTimezone(const Duration(hours: -8)), 'America/Los_Angeles');
      expect(mapOffsetToTimezone(const Duration(hours: -5)), 'America/New_York');
      expect(mapOffsetToTimezone(const Duration(hours: 0)), 'UTC');
      expect(mapOffsetToTimezone(const Duration(hours: 1)), 'Europe/Paris');
      expect(mapOffsetToTimezone(const Duration(hours: 9)), 'Asia/Tokyo');
      expect(mapOffsetToTimezone(const Duration(hours: 10)), 'Australia/Sydney');
    });

    test('maps half-hour offsets', () {
      expect(
        mapOffsetToTimezone(const Duration(hours: 5, minutes: 30)),
        'Asia/Kolkata',
      );
      expect(
        mapOffsetToTimezone(const Duration(hours: 9, minutes: 30)),
        'Australia/Darwin',
      );
    });

    test('maps 45-minute offsets', () {
      expect(
        mapOffsetToTimezone(const Duration(hours: 5, minutes: 45)),
        'Asia/Kathmandu',
      );
    });

    test('maps extreme offsets', () {
      expect(mapOffsetToTimezone(const Duration(hours: -12)), 'Pacific/Kwajalein');
      expect(mapOffsetToTimezone(const Duration(hours: 14)), 'Pacific/Kiritimati');
    });

    test('returns UTC for unknown offsets', () {
      expect(mapOffsetToTimezone(const Duration(hours: 15)), 'UTC');
      expect(mapOffsetToTimezone(const Duration(hours: -13)), 'UTC');
    });
  });

  group('getTimezoneDisplayName', () {
    test('formats US timezone correctly', () {
      expect(
        getTimezoneDisplayName('America/New_York'),
        'New York (America)',
      );
    });

    test('formats European timezone correctly', () {
      expect(
        getTimezoneDisplayName('Europe/London'),
        'London (Europe)',
      );
    });

    test('formats Asian timezone correctly', () {
      expect(
        getTimezoneDisplayName('Asia/Hong_Kong'),
        'Hong Kong (Asia)',
      );
    });

    test('handles UTC', () {
      expect(getTimezoneDisplayName('UTC'), 'UTC');
    });

    test('handles multi-part city names', () {
      expect(
        getTimezoneDisplayName('America/Kentucky/Louisville'),
        'Kentucky/Louisville (America)',
      );
    });

    test('replaces underscores with spaces', () {
      expect(
        getTimezoneDisplayName('America/Los_Angeles'),
        'Los Angeles (America)',
      );
      expect(
        getTimezoneDisplayName('Asia/Ho_Chi_Minh'),
        'Ho Chi Minh (Asia)',
      );
    });
  });

  // Note: detectUserTimezone() requires FlutterTimezone plugin which
  // doesn't work in unit tests without platform channels.
  // Integration tests or manual testing should verify full detection.
}
