import 'package:flutter/material.dart' show TimeOfDay;

/// Pure helpers for the cadence-anchor ("First deadline") wizard section.
///
/// A cadence anchor is the user-chosen end of the FIRST phase. The repeating
/// wall-clock grid is derived from it: {anchor's local time-of-day + n x
/// duration}. `null` anchor = no cadence (plain duration chaining) — that is
/// the default; cadence is strictly opt-in. See docs/CADENCE_ANCHOR_SPEC.md.

/// Minimum runway between "now" and the first deadline, so the first phase is
/// never a sliver: `LEAST(duration / 4, 1 hour)`.
Duration minRunway(Duration duration) {
  final quarter = duration ~/ 4;
  const oneHour = Duration(hours: 1);
  return quarter < oneHour ? quarter : oneHour;
}

/// The valid range for an anchor chosen at [now]:
/// `[now + runway, now + duration]`. The upper bound guarantees the first
/// phase is never LONGER than the stated duration; the lower bound guarantees
/// it is never a sliver.
({DateTime earliest, DateTime latest}) anchorWindow(
    DateTime now, Duration duration) {
  return (
    earliest: now.add(minRunway(duration)),
    latest: now.add(duration),
  );
}

/// Whether a pair of phase durations (seconds) can carry a cadence anchor in
/// the wizard UI: equal phases + a whole-hour duration that divides 24h
/// (1/2/3/4/6/8/12/24h — otherwise the grid wanders the clock).
///
/// Note this is deliberately STRICTER than the DB gate (`86400 % d = 0`):
/// sub-hour divisors like 90min pass the modulo but are excluded from the UI
/// per the spec's enumerated whole-hour list.
bool isCadenceCoherent(int proposingSeconds, int ratingSeconds) {
  return proposingSeconds == ratingSeconds &&
      proposingSeconds > 0 &&
      proposingSeconds % 3600 == 0 &&
      86400 % proposingSeconds == 0;
}

/// Typed descriptor for one suggestion chip in the anchor section.
///
/// Chips are pure UI sugar: they pre-fill an anchor value (or unset it) —
/// the backend never knows any specific rhythm exists.
sealed class CadenceChip {
  const CadenceChip();
}

/// "Full duration" — unset the anchor (plain chaining). Always present and
/// the DEFAULT selection.
class FullDurationChip extends CadenceChip {
  const FullDurationChip();
}

/// "3 AM / 3 PM rhythm" (12h durations only) — [value] is the next 3am/3pm
/// in device-local time at or after now + runway.
class AmPmRhythmChip extends CadenceChip {
  const AmPmRhythmChip(this.value);
  final DateTime value;
}

/// "Same time daily…" (24h durations only) — opens the time picker.
class DailyTimeChip extends CadenceChip {
  const DailyTimeChip();
}

/// "On the hour" (other coherent durations) — [value] is the next whole hour
/// at or after now + runway.
class OnTheHourChip extends CadenceChip {
  const OnTheHourChip(this.value);
  final DateTime value;
}

/// The suggestion chips for [duration] as of [now]. Empty when the duration
/// cannot carry a cadence (does not divide 24h) — the anchor section is not
/// rendered at all in that case.
List<CadenceChip> chipsFor(Duration duration, DateTime now) {
  final secs = duration.inSeconds;
  if (!isCadenceCoherent(secs, secs)) return const [];

  final earliest = now.add(minRunway(duration));
  if (secs == 43200) {
    return [
      const FullDurationChip(),
      AmPmRhythmChip(_nextThreeBoundary(earliest)),
    ];
  }
  if (secs == 86400) {
    return const [FullDurationChip(), DailyTimeChip()];
  }
  return [
    const FullDurationChip(),
    OnTheHourChip(_nextWholeHour(earliest)),
  ];
}

/// The daily wall-clock flip times implied by [anchor] + [duration], sorted
/// ascending. One entry for 24h durations, two for 12h, four for 6h, etc.
/// Times are taken from [anchor]'s own (local) clock face.
List<TimeOfDay> previewFlipTimes(DateTime anchor, Duration duration) {
  final secs = duration.inSeconds;
  if (secs <= 0 || 86400 % secs != 0) {
    return [TimeOfDay.fromDateTime(anchor)];
  }
  final count = 86400 ~/ secs;
  final stepMinutes = secs ~/ 60;
  final baseMinutes = anchor.hour * 60 + anchor.minute;
  final minutes = List<int>.generate(
    count,
    (k) => (baseMinutes + k * stepMinutes) % 1440,
  )..sort();
  return minutes
      .map((m) => TimeOfDay(hour: m ~/ 60, minute: m % 60))
      .toList(growable: false);
}

/// Maps a wall-clock time picked in the time picker onto the concrete anchor
/// instant inside [anchorWindow] — the earliest grid-equivalent occurrence
/// (picked time + k x duration) at or after now + runway. Returns null when
/// no occurrence lands inside the window (the picked time cannot be a valid
/// first deadline for this duration).
DateTime? anchorForPickedTime(TimeOfDay picked, DateTime now, Duration duration) {
  final window = anchorWindow(now, duration);
  // Start a full day back so stepping by duration (<= 24h) sweeps the window.
  var candidate = DateTime(
    now.year,
    now.month,
    now.day - 1,
    picked.hour,
    picked.minute,
  );
  while (candidate.isBefore(window.earliest)) {
    candidate = candidate.add(duration);
  }
  return candidate.isAfter(window.latest) ? null : candidate;
}

/// The next 03:00 or 15:00 at or after [after], on [after]'s own clock.
DateTime _nextThreeBoundary(DateTime after) {
  final candidates = [
    DateTime(after.year, after.month, after.day, 3),
    DateTime(after.year, after.month, after.day, 15),
    DateTime(after.year, after.month, after.day + 1, 3),
  ];
  return candidates.firstWhere((c) => !c.isBefore(after));
}

/// The next whole hour at or after [after].
DateTime _nextWholeHour(DateTime after) {
  final floor = DateTime(after.year, after.month, after.day, after.hour);
  return floor == after ? floor : floor.add(const Duration(hours: 1));
}
