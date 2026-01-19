import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/core/errors/app_exception.dart';
import 'package:onemind_app/models/round.dart';

import '../fixtures/round_fixtures.dart';

void main() {
  group('Round', () {
    group('fromJson', () {
      test('parses all required fields', () {
        final json = {
          'id': 1,
          'cycle_id': 10,
          'custom_id': 3,
          'phase': 'proposing',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final round = Round.fromJson(json);

        expect(round.id, 1);
        expect(round.cycleId, 10);
        expect(round.customId, 3);
        expect(round.phase, RoundPhase.proposing);
        expect(round.createdAt, DateTime.utc(2024, 1, 1));
      });

      test('parses all optional fields', () {
        final json = {
          'id': 1,
          'cycle_id': 10,
          'custom_id': 3,
          'phase': 'rating',
          'phase_started_at': '2024-01-01T10:00:00Z',
          'phase_ends_at': '2024-01-01T11:00:00Z',
          'winning_proposition_id': 42,
          'created_at': '2024-01-01T00:00:00Z',
          'completed_at': '2024-01-01T12:00:00Z',
        };

        final round = Round.fromJson(json);

        expect(round.id, 1);
        expect(round.cycleId, 10);
        expect(round.customId, 3);
        expect(round.phase, RoundPhase.rating);
        expect(round.phaseStartedAt, DateTime.utc(2024, 1, 1, 10, 0, 0));
        expect(round.phaseEndsAt, DateTime.utc(2024, 1, 1, 11, 0, 0));
        expect(round.winningPropositionId, 42);
        expect(round.createdAt, DateTime.utc(2024, 1, 1));
        expect(round.completedAt, DateTime.utc(2024, 1, 1, 12, 0, 0));
      });

      test('handles null optional fields', () {
        final json = {
          'id': 1,
          'cycle_id': 10,
          'custom_id': 3,
          'phase': 'proposing',
          'phase_started_at': null,
          'phase_ends_at': null,
          'winning_proposition_id': null,
          'created_at': '2024-01-01T00:00:00Z',
          'completed_at': null,
        };

        final round = Round.fromJson(json);

        expect(round.phaseStartedAt, isNull);
        expect(round.phaseEndsAt, isNull);
        expect(round.winningPropositionId, isNull);
        expect(round.completedAt, isNull);
      });
    });

    group('phase parsing', () {
      test('parses "waiting" phase', () {
        final json = RoundFixtures.json(phase: 'waiting');
        final round = Round.fromJson(json);
        expect(round.phase, RoundPhase.waiting);
      });

      test('parses "proposing" phase', () {
        final json = RoundFixtures.json(phase: 'proposing');
        final round = Round.fromJson(json);
        expect(round.phase, RoundPhase.proposing);
      });

      test('parses "rating" phase', () {
        final json = RoundFixtures.json(phase: 'rating');
        final round = Round.fromJson(json);
        expect(round.phase, RoundPhase.rating);
      });

      test('throws exception for unknown phase', () {
        final json = RoundFixtures.json(phase: 'unknown_phase');
        expect(
          () => Round.fromJson(json),
          throwsA(isA<AppException>()),
        );
      });

      test('defaults to waiting for null phase', () {
        final json = {
          'id': 1,
          'cycle_id': 1,
          'custom_id': 1,
          'phase': null,
          'created_at': '2024-01-01T00:00:00Z',
        };
        final round = Round.fromJson(json);
        expect(round.phase, RoundPhase.waiting);
      });
    });

    group('isComplete', () {
      test('returns true when completedAt is set', () {
        final round = RoundFixtures.completed();
        expect(round.isComplete, true);
      });

      test('returns false when completedAt is null', () {
        final round = RoundFixtures.proposing();
        expect(round.isComplete, false);
      });

      test('returns false for waiting round', () {
        final round = RoundFixtures.waiting();
        expect(round.isComplete, false);
      });

      test('returns false for rating round without completedAt', () {
        final round = RoundFixtures.rating();
        expect(round.isComplete, false);
      });
    });

    group('timeRemaining', () {
      test('returns null when phaseEndsAt is null', () {
        final round = RoundFixtures.waiting();
        expect(round.timeRemaining, isNull);
      });

      test('returns positive duration when timer is active', () {
        final round = RoundFixtures.proposing(
          timeRemaining: const Duration(hours: 1),
        );
        final remaining = round.timeRemaining;

        expect(remaining, isNotNull);
        // Allow some tolerance for test execution time
        expect(remaining!.inMinutes, greaterThanOrEqualTo(59));
        expect(remaining.inMinutes, lessThanOrEqualTo(60));
      });

      test('returns Duration.zero when timer has expired', () {
        final round = RoundFixtures.timerExpired();
        expect(round.timeRemaining, Duration.zero);
      });

      test('returns zero for expired timer during rating phase', () {
        final now = DateTime.now();
        final json = RoundFixtures.json(
          phase: 'rating',
          phaseStartedAt: now.subtract(const Duration(hours: 2)),
          phaseEndsAt: now.subtract(const Duration(minutes: 30)),
        );
        final round = Round.fromJson(json);

        expect(round.timeRemaining, Duration.zero);
      });

      test('handles different time remaining values', () {
        // Test with 30 minutes remaining
        final round30min = RoundFixtures.proposing(
          timeRemaining: const Duration(minutes: 30),
        );
        expect(round30min.timeRemaining!.inMinutes, closeTo(30, 1));

        // Test with 24 hours remaining
        final round24h = RoundFixtures.proposing(
          timeRemaining: const Duration(hours: 24),
        );
        expect(round24h.timeRemaining!.inHours, closeTo(24, 1));

        // Test with just seconds remaining
        final round10s = RoundFixtures.proposing(
          timeRemaining: const Duration(seconds: 10),
        );
        expect(round10s.timeRemaining!.inSeconds, closeTo(10, 2));
      });
    });

    group('fixtures', () {
      test('RoundFixtures.model creates valid round', () {
        final round = RoundFixtures.model(
          id: 5,
          cycleId: 10,
          customId: 2,
          phase: RoundPhase.rating,
        );

        expect(round.id, 5);
        expect(round.cycleId, 10);
        expect(round.customId, 2);
        expect(round.phase, RoundPhase.rating);
      });

      test('RoundFixtures.waiting creates waiting phase round', () {
        final round = RoundFixtures.waiting(id: 1, cycleId: 5, customId: 3);

        expect(round.id, 1);
        expect(round.cycleId, 5);
        expect(round.customId, 3);
        expect(round.phase, RoundPhase.waiting);
      });

      test('RoundFixtures.proposing creates proposing phase round', () {
        final round = RoundFixtures.proposing();
        expect(round.phase, RoundPhase.proposing);
      });

      test('RoundFixtures.rating creates rating phase round', () {
        final round = RoundFixtures.rating();
        expect(round.phase, RoundPhase.rating);
      });

      test('RoundFixtures.completed creates completed round with winner', () {
        final round = RoundFixtures.completed(winningPropositionId: 42);

        expect(round.isComplete, true);
        expect(round.winningPropositionId, 42);
      });

      test('RoundFixtures.timerExpired creates expired round', () {
        final round = RoundFixtures.timerExpired();
        expect(round.timeRemaining, Duration.zero);
      });

      test('RoundFixtures.list creates list of rounds', () {
        final rounds = RoundFixtures.list(count: 5, cycleId: 10);

        expect(rounds.length, 5);
        expect(rounds.every((r) => r.cycleId == 10), true);

        // Each round should have sequential customId
        for (var i = 0; i < rounds.length; i++) {
          expect(rounds[i].customId, i + 1);
        }
      });

      test('RoundFixtures.list with includeCompleted=false', () {
        final rounds = RoundFixtures.list(
          count: 3,
          cycleId: 1,
          includeCompleted: false,
        );

        // Last round should be in proposing phase (not completed)
        expect(rounds.last.phase, RoundPhase.proposing);
        expect(rounds.last.isComplete, false);
      });
    });

    group('equality', () {
      test('two rounds with same props are equal', () {
        final round1 = RoundFixtures.model(
          id: 1,
          cycleId: 10,
          customId: 3,
          phase: RoundPhase.proposing,
          winningPropositionId: null,
        );

        final round2 = RoundFixtures.model(
          id: 1,
          cycleId: 10,
          customId: 3,
          phase: RoundPhase.proposing,
          winningPropositionId: null,
        );

        expect(round1, equals(round2));
      });

      test('rounds with different ids are not equal', () {
        final round1 = RoundFixtures.model(id: 1);
        final round2 = RoundFixtures.model(id: 2);

        expect(round1, isNot(equals(round2)));
      });

      test('rounds with different cycleIds are not equal', () {
        final round1 = RoundFixtures.model(id: 1, cycleId: 10);
        final round2 = RoundFixtures.model(id: 1, cycleId: 20);

        expect(round1, isNot(equals(round2)));
      });

      test('rounds with different customIds are not equal', () {
        final round1 = RoundFixtures.model(id: 1, customId: 1);
        final round2 = RoundFixtures.model(id: 1, customId: 2);

        expect(round1, isNot(equals(round2)));
      });

      test('rounds with different phases are not equal', () {
        final round1 = RoundFixtures.model(id: 1, phase: RoundPhase.proposing);
        final round2 = RoundFixtures.model(id: 1, phase: RoundPhase.rating);

        expect(round1, isNot(equals(round2)));
      });

      test('rounds with different winningPropositionIds are not equal', () {
        final round1 = RoundFixtures.model(id: 1, winningPropositionId: 10);
        final round2 = RoundFixtures.model(id: 1, winningPropositionId: 20);

        expect(round1, isNot(equals(round2)));
      });

      test('round equals itself', () {
        final round = RoundFixtures.model();
        expect(round, equals(round));
      });

      test('hashCode is consistent with equality', () {
        final round1 = RoundFixtures.model(
          id: 1,
          cycleId: 10,
          customId: 3,
          phase: RoundPhase.rating,
        );

        final round2 = RoundFixtures.model(
          id: 1,
          cycleId: 10,
          customId: 3,
          phase: RoundPhase.rating,
        );

        expect(round1.hashCode, equals(round2.hashCode));
      });
    });

    group('RoundPhase enum', () {
      test('has three values', () {
        expect(RoundPhase.values.length, 3);
      });

      test('contains waiting, proposing, rating', () {
        expect(RoundPhase.values, contains(RoundPhase.waiting));
        expect(RoundPhase.values, contains(RoundPhase.proposing));
        expect(RoundPhase.values, contains(RoundPhase.rating));
      });

      test('enum names are correct', () {
        expect(RoundPhase.waiting.name, 'waiting');
        expect(RoundPhase.proposing.name, 'proposing');
        expect(RoundPhase.rating.name, 'rating');
      });
    });

    group('edge cases', () {
      test('handles very large ids', () {
        final json = RoundFixtures.json(
          id: 2147483647, // Max 32-bit int
          cycleId: 2147483647,
          customId: 999999,
        );
        final round = Round.fromJson(json);

        expect(round.id, 2147483647);
        expect(round.cycleId, 2147483647);
        expect(round.customId, 999999);
      });

      test('handles minimum customId of 1', () {
        final round = RoundFixtures.model(customId: 1);
        expect(round.customId, 1);
      });

      test('handles far future dates', () {
        final json = {
          'id': 1,
          'cycle_id': 1,
          'custom_id': 1,
          'phase': 'proposing',
          'phase_ends_at': '2099-12-31T23:59:59Z',
          'created_at': '2024-01-01T00:00:00Z',
        };
        final round = Round.fromJson(json);

        expect(round.phaseEndsAt, DateTime.utc(2099, 12, 31, 23, 59, 59));
        expect(round.timeRemaining!.inDays, greaterThan(365 * 70));
      });

      test('round can transition from proposing to rating', () {
        // Simulate a round progressing through phases
        final proposingRound = RoundFixtures.proposing(id: 1, customId: 1);
        expect(proposingRound.phase, RoundPhase.proposing);
        expect(proposingRound.isComplete, false);

        final ratingRound = RoundFixtures.rating(id: 1, customId: 1);
        expect(ratingRound.phase, RoundPhase.rating);
        expect(ratingRound.isComplete, false);

        final completedRound = RoundFixtures.completed(
          id: 1,
          customId: 1,
          winningPropositionId: 42,
        );
        expect(completedRound.isComplete, true);
        expect(completedRound.winningPropositionId, 42);
      });

      test('multiple rounds in same cycle have different customIds', () {
        final rounds = RoundFixtures.list(count: 5, cycleId: 1);

        final customIds = rounds.map((r) => r.customId).toSet();
        expect(customIds.length, 5); // All unique
      });
    });
  });
}
