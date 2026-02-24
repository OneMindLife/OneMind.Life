import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import '../fixtures/chat_fixtures.dart';
import '../fixtures/chat_dashboard_info_fixtures.dart';

void main() {
  group('ChatDashboardInfo', () {
    group('fromJson', () {
      test('parses idle chat (no active round)', () {
        final json = ChatDashboardInfoFixtures.json(
          id: 1,
          name: 'Idle Test',
          participantCount: 5,
        );

        final info = ChatDashboardInfo.fromJson(json);

        expect(info.chat.id, 1);
        expect(info.chat.name, 'Idle Test');
        expect(info.participantCount, 5);
        expect(info.currentRoundPhase, isNull);
        expect(info.currentRoundNumber, isNull);
        expect(info.phaseEndsAt, isNull);
        expect(info.phaseStartedAt, isNull);
        expect(info.currentCycleId, isNull);
      });

      test('parses active proposing round with timer', () {
        final endsAt = DateTime.now().add(const Duration(minutes: 5));
        final startedAt = DateTime.now().subtract(const Duration(minutes: 2));
        final json = ChatDashboardInfoFixtures.json(
          id: 2,
          currentRoundPhase: 'proposing',
          currentRoundCustomId: 3,
          currentRoundPhaseEndsAt: endsAt,
          currentRoundPhaseStartedAt: startedAt,
          currentCycleId: 42,
        );

        final info = ChatDashboardInfo.fromJson(json);

        expect(info.currentRoundPhase, RoundPhase.proposing);
        expect(info.currentRoundNumber, 3);
        expect(info.phaseEndsAt, isNotNull);
        expect(info.phaseStartedAt, isNotNull);
        expect(info.currentCycleId, 42);
      });

      test('parses rating phase', () {
        final json = ChatDashboardInfoFixtures.json(
          currentRoundPhase: 'rating',
          currentRoundCustomId: 2,
        );

        final info = ChatDashboardInfo.fromJson(json);
        expect(info.currentRoundPhase, RoundPhase.rating);
      });

      test('parses waiting phase', () {
        final json = ChatDashboardInfoFixtures.json(
          currentRoundPhase: 'waiting',
        );

        final info = ChatDashboardInfo.fromJson(json);
        expect(info.currentRoundPhase, RoundPhase.waiting);
      });

      test('handles null participant_count gracefully', () {
        final json = ChatDashboardInfoFixtures.json();
        json['participant_count'] = null;

        final info = ChatDashboardInfo.fromJson(json);
        expect(info.participantCount, 0);
      });
    });

    group('computed getters', () {
      test('hasActiveTimer returns true when phaseEndsAt and phase are set', () {
        final info = ChatDashboardInfoFixtures.proposingTimed();
        expect(info.hasActiveTimer, isTrue);
      });

      test('hasActiveTimer returns false for manual mode', () {
        final info = ChatDashboardInfoFixtures.proposingManual();
        expect(info.hasActiveTimer, isFalse);
      });

      test('hasActiveTimer returns false when idle', () {
        final info = ChatDashboardInfoFixtures.idle();
        expect(info.hasActiveTimer, isFalse);
      });

      test('isPaused returns true when host paused', () {
        final info = ChatDashboardInfoFixtures.paused();
        expect(info.isPaused, isTrue);
      });

      test('isPaused returns false for active chat', () {
        final info = ChatDashboardInfoFixtures.proposingTimed();
        expect(info.isPaused, isFalse);
      });

      test('hasActiveRound returns true when phase is set', () {
        final info = ChatDashboardInfoFixtures.proposingTimed();
        expect(info.hasActiveRound, isTrue);
      });

      test('hasActiveRound returns false when idle', () {
        final info = ChatDashboardInfoFixtures.idle();
        expect(info.hasActiveRound, isFalse);
      });

      test('timeRemaining returns positive duration for future timer', () {
        final info = ChatDashboardInfoFixtures.proposingTimed(
          timerRemaining: const Duration(minutes: 5),
        );
        expect(info.timeRemaining, isNotNull);
        expect(info.timeRemaining!.inSeconds, greaterThan(0));
      });

      test('timeRemaining returns Duration.zero for expired timer', () {
        final info = ChatDashboardInfo(
          chat: ChatFixtures.model(),
          participantCount: 3,
          currentRoundPhase: RoundPhase.proposing,
          phaseEndsAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        expect(info.timeRemaining, Duration.zero);
      });

      test('timeRemaining returns null when no timer', () {
        final info = ChatDashboardInfoFixtures.idle();
        expect(info.timeRemaining, isNull);
      });
    });

    group('Equatable', () {
      test('equal instances are equal', () {
        final chat = ChatFixtures.model(id: 1);
        final a = ChatDashboardInfo(chat: chat, participantCount: 3);
        final b = ChatDashboardInfo(chat: chat, participantCount: 3);
        expect(a, equals(b));
      });

      test('different participantCount are not equal', () {
        final chat = ChatFixtures.model(id: 1);
        final a = ChatDashboardInfo(chat: chat, participantCount: 3);
        final b = ChatDashboardInfo(chat: chat, participantCount: 5);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
