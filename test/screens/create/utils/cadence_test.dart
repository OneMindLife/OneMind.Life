import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/utils/cadence.dart';

void main() {
  group('minRunway', () {
    test('is duration/4 for short durations', () {
      expect(minRunway(const Duration(hours: 1)), const Duration(minutes: 15));
      expect(minRunway(const Duration(hours: 2)), const Duration(minutes: 30));
      expect(minRunway(const Duration(hours: 3)), const Duration(minutes: 45));
    });

    test('caps at 1 hour for long durations', () {
      expect(minRunway(const Duration(hours: 4)), const Duration(hours: 1));
      expect(minRunway(const Duration(hours: 12)), const Duration(hours: 1));
      expect(minRunway(const Duration(hours: 24)), const Duration(hours: 1));
    });
  });

  group('anchorWindow', () {
    test('is [now + runway, now + duration]', () {
      final now = DateTime(2026, 7, 2, 10, 0);
      final window = anchorWindow(now, const Duration(hours: 12));
      expect(window.earliest, DateTime(2026, 7, 2, 11, 0));
      expect(window.latest, DateTime(2026, 7, 2, 22, 0));
    });

    test('uses the quarter-duration runway for short phases', () {
      final now = DateTime(2026, 7, 2, 10, 0);
      final window = anchorWindow(now, const Duration(hours: 2));
      expect(window.earliest, DateTime(2026, 7, 2, 10, 30));
      expect(window.latest, DateTime(2026, 7, 2, 12, 0));
    });
  });

  group('isCadenceCoherent', () {
    test('true for equal 24h-dividing durations', () {
      for (final h in [1, 2, 3, 4, 6, 8, 12, 24]) {
        expect(isCadenceCoherent(h * 3600, h * 3600), isTrue,
            reason: '${h}h should be coherent');
      }
    });

    test('false when durations differ', () {
      expect(isCadenceCoherent(43200, 86400), isFalse);
    });

    test('false when the duration does not divide 24h', () {
      expect(isCadenceCoherent(18000, 18000), isFalse); // 5h
      expect(isCadenceCoherent(5400, 5400), isFalse); // 90min
    });

    test('false for non-positive durations', () {
      expect(isCadenceCoherent(0, 0), isFalse);
    });
  });

  group('chipsFor', () {
    test('12h: Full duration + 3am/3pm rhythm', () {
      final now = DateTime(2026, 7, 2, 10, 0);
      final chips = chipsFor(const Duration(hours: 12), now);
      expect(chips, hasLength(2));
      expect(chips[0], isA<FullDurationChip>());
      expect(chips[1], isA<AmPmRhythmChip>());
      // Runway = 1h -> earliest 11:00 -> next 3am/3pm is 3 PM today.
      expect((chips[1] as AmPmRhythmChip).value, DateTime(2026, 7, 2, 15, 0));
    });

    test('12h: boundary inside the runway is skipped to the following one',
        () {
      // now 2:30 -> earliest 3:30 -> 3 AM is inside the runway -> 3 PM.
      final now = DateTime(2026, 7, 2, 2, 30);
      final chips = chipsFor(const Duration(hours: 12), now);
      expect((chips[1] as AmPmRhythmChip).value, DateTime(2026, 7, 2, 15, 0));
    });

    test('12h: late evening wraps to 3 AM tomorrow', () {
      final now = DateTime(2026, 7, 2, 20, 0);
      final chips = chipsFor(const Duration(hours: 12), now);
      expect((chips[1] as AmPmRhythmChip).value, DateTime(2026, 7, 3, 3, 0));
    });

    test('24h: Full duration + Same time daily', () {
      final now = DateTime(2026, 7, 2, 10, 0);
      final chips = chipsFor(const Duration(hours: 24), now);
      expect(chips, hasLength(2));
      expect(chips[0], isA<FullDurationChip>());
      expect(chips[1], isA<DailyTimeChip>());
    });

    test('6h: Full duration + On the hour', () {
      final now = DateTime(2026, 7, 2, 10, 20);
      final chips = chipsFor(const Duration(hours: 6), now);
      expect(chips, hasLength(2));
      expect(chips[0], isA<FullDurationChip>());
      expect(chips[1], isA<OnTheHourChip>());
      // Runway = 1h -> earliest 11:20 -> next whole hour is 12:00.
      expect((chips[1] as OnTheHourChip).value, DateTime(2026, 7, 2, 12, 0));
    });

    test('1h: On the hour with quarter-duration runway', () {
      final now = DateTime(2026, 7, 2, 10, 20);
      final chips = chipsFor(const Duration(hours: 1), now);
      // Runway = 15min -> earliest 10:35 -> next whole hour is 11:00.
      expect((chips[1] as OnTheHourChip).value, DateTime(2026, 7, 2, 11, 0));
    });

    test('on-the-hour keeps an exact whole-hour earliest bound', () {
      // now 10:00 with 1h runway (4h duration) -> earliest exactly 11:00.
      final now = DateTime(2026, 7, 2, 10, 0);
      final chips = chipsFor(const Duration(hours: 4), now);
      expect((chips[1] as OnTheHourChip).value, DateTime(2026, 7, 2, 11, 0));
    });

    test('5h (does not divide 24h): no chips', () {
      final now = DateTime(2026, 7, 2, 10, 0);
      expect(chipsFor(const Duration(hours: 5), now), isEmpty);
    });

    test('90min (does not divide 24h): no chips', () {
      final now = DateTime(2026, 7, 2, 10, 0);
      expect(chipsFor(const Duration(minutes: 90), now), isEmpty);
    });
  });

  group('previewFlipTimes', () {
    test('12h anchor yields two flip times sorted ascending', () {
      final anchor = DateTime(2026, 7, 2, 15, 0);
      final flips = previewFlipTimes(anchor, const Duration(hours: 12));
      expect(flips, [
        const TimeOfDay(hour: 3, minute: 0),
        const TimeOfDay(hour: 15, minute: 0),
      ]);
    });

    test('24h anchor yields a single flip time', () {
      final anchor = DateTime(2026, 7, 2, 9, 30);
      final flips = previewFlipTimes(anchor, const Duration(hours: 24));
      expect(flips, [const TimeOfDay(hour: 9, minute: 30)]);
    });

    test('6h anchor yields four flip times', () {
      final anchor = DateTime(2026, 7, 2, 14, 0);
      final flips = previewFlipTimes(anchor, const Duration(hours: 6));
      expect(flips, [
        const TimeOfDay(hour: 2, minute: 0),
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ]);
    });

    test('midnight wrap: 11 PM anchor with 12h phases', () {
      final anchor = DateTime(2026, 7, 2, 23, 0);
      final flips = previewFlipTimes(anchor, const Duration(hours: 12));
      expect(flips, [
        const TimeOfDay(hour: 11, minute: 0),
        const TimeOfDay(hour: 23, minute: 0),
      ]);
    });

    test('non-hour anchor minutes are preserved', () {
      final anchor = DateTime(2026, 7, 2, 22, 45);
      final flips = previewFlipTimes(anchor, const Duration(hours: 12));
      expect(flips, [
        const TimeOfDay(hour: 10, minute: 45),
        const TimeOfDay(hour: 22, minute: 45),
      ]);
    });
  });

  group('anchorForPickedTime', () {
    final now = DateTime(2026, 7, 2, 10, 0); // 12h window: [11:00, 22:00]

    test('maps a wall time inside the window to today', () {
      final anchor = anchorForPickedTime(
          const TimeOfDay(hour: 15, minute: 0), now, const Duration(hours: 12));
      expect(anchor, DateTime(2026, 7, 2, 15, 0));
    });

    test('accepts the exact earliest bound', () {
      final anchor = anchorForPickedTime(
          const TimeOfDay(hour: 11, minute: 0), now, const Duration(hours: 12));
      expect(anchor, DateTime(2026, 7, 2, 11, 0));
    });

    test('accepts the exact latest bound', () {
      final anchor = anchorForPickedTime(
          const TimeOfDay(hour: 22, minute: 0), now, const Duration(hours: 12));
      expect(anchor, DateTime(2026, 7, 2, 22, 0));
    });

    test('uses the grid-equivalent occurrence when the literal time is out of '
        'window', () {
      // Picking 23:00 with 12h phases means the grid {11:00, 23:00}; 23:00
      // today is past the latest bound (22:00) but 11:00 today is in window —
      // the window is shorter than the grid spacing, so it's the unique fit.
      final anchor = anchorForPickedTime(
          const TimeOfDay(hour: 23, minute: 0), now, const Duration(hours: 12));
      expect(anchor, DateTime(2026, 7, 2, 11, 0));
    });

    test('returns null when no occurrence lands in the window', () {
      // Grid {10:30, 22:30}: 10:30 today is inside the runway, 22:30 is past
      // the latest bound -> unrepresentable.
      final anchor = anchorForPickedTime(const TimeOfDay(hour: 22, minute: 30),
          now, const Duration(hours: 12));
      expect(anchor, isNull);
    });

    test('24h duration: morning time rolls to tomorrow', () {
      final anchor = anchorForPickedTime(
          const TimeOfDay(hour: 9, minute: 0), now, const Duration(hours: 24));
      expect(anchor, DateTime(2026, 7, 3, 9, 0));
    });
  });
}
