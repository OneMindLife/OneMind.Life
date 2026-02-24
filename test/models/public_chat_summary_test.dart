import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/public_chat_summary.dart';
import 'package:onemind_app/models/round.dart';

void main() {
  group('PublicChatSummary', () {
    group('fromJson', () {
      test('parses all fields correctly', () {
        final json = {
          'id': 1,
          'name': 'Public Test Chat',
          'description': 'A public chat for testing',
          'initial_message': 'What should we discuss?',
          'participant_count': 10,
          'created_at': '2024-01-01T00:00:00Z',
          'last_activity_at': '2024-06-15T12:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.id, 1);
        expect(summary.name, 'Public Test Chat');
        expect(summary.description, 'A public chat for testing');
        expect(summary.initialMessage, 'What should we discuss?');
        expect(summary.participantCount, 10);
        expect(summary.createdAt, DateTime.utc(2024, 1, 1, 0, 0, 0));
        expect(summary.lastActivityAt, DateTime.utc(2024, 6, 15, 12, 0, 0));
      });

      test('handles null description', () {
        final json = {
          'id': 2,
          'name': 'No Description Chat',
          'description': null,
          'initial_message': 'Test message',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
          'last_activity_at': null,
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.id, 2);
        expect(summary.name, 'No Description Chat');
        expect(summary.description, isNull);
        expect(summary.lastActivityAt, isNull);
      });

      test('handles missing participant_count', () {
        final json = {
          'id': 3,
          'name': 'Test Chat',
          'initial_message': 'Test message',
          'participant_count': null,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.participantCount, 0);
      });

      test('handles participant_count as double', () {
        final json = {
          'id': 4,
          'name': 'Test Chat',
          'initial_message': 'Test message',
          'participant_count': 7.0,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.participantCount, 7);
      });

      test('handles null initial_message', () {
        final json = {
          'id': 5,
          'name': 'Test Chat',
          'initial_message': null,
          'participant_count': 3,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.initialMessage, isNull);
        expect(summary.displayInitialMessage, '');
      });

      test('handles missing initial_message', () {
        final json = {
          'id': 6,
          'name': 'Test Chat',
          'participant_count': 3,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.initialMessage, isNull);
        expect(summary.displayInitialMessage, '');
      });

      test('parses dashboard phase fields', () {
        final json = {
          'id': 1,
          'name': 'Active Chat',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
          'current_round_phase': 'proposing',
          'current_round_custom_id': 3,
          'current_round_phase_ends_at': '2024-06-15T12:05:00Z',
          'current_round_phase_started_at': '2024-06-15T12:00:00Z',
          'schedule_paused': false,
          'host_paused': false,
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.currentRoundPhase, 'proposing');
        expect(summary.currentRoundNumber, 3);
        expect(summary.phaseEndsAt, DateTime.utc(2024, 6, 15, 12, 5, 0));
        expect(summary.phaseStartedAt, DateTime.utc(2024, 6, 15, 12, 0, 0));
        expect(summary.schedulePaused, false);
        expect(summary.hostPaused, false);
      });

      test('handles null dashboard phase fields', () {
        final json = {
          'id': 1,
          'name': 'Idle Chat',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
          'current_round_phase': null,
          'current_round_custom_id': null,
          'current_round_phase_ends_at': null,
          'current_round_phase_started_at': null,
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.currentRoundPhase, isNull);
        expect(summary.currentRoundNumber, isNull);
        expect(summary.phaseEndsAt, isNull);
        expect(summary.phaseStartedAt, isNull);
      });

      test('defaults schedule_paused and host_paused to false', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);

        expect(summary.schedulePaused, false);
        expect(summary.hostPaused, false);
      });
    });

    group('translationLanguages', () {
      test('defaults to [en] when not in JSON', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final summary = PublicChatSummary.fromJson(json);
        expect(summary.translationLanguages, ['en']);
      });

      test('parses translation_languages array', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
          'translation_languages': ['es', 'pt'],
        };

        final summary = PublicChatSummary.fromJson(json);
        expect(summary.translationLanguages, ['es', 'pt']);
      });

      test('handles null translation_languages', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'participant_count': 5,
          'created_at': '2024-01-01T00:00:00Z',
          'translation_languages': null,
        };

        final summary = PublicChatSummary.fromJson(json);
        expect(summary.translationLanguages, ['en']);
      });
    });

    group('displayInitialMessage', () {
      test('returns initialMessage when present', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          initialMessage: 'Test message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );
        expect(summary.displayInitialMessage, 'Test message');
      });

      test('returns empty string when initialMessage is null', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );
        expect(summary.displayInitialMessage, '');
      });

      test('returns translation when available', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          initialMessage: 'Original',
          initialMessageTranslated: 'Translated',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );
        expect(summary.displayInitialMessage, 'Translated');
      });
    });

    group('computed dashboard getters', () {
      test('currentPhase parses proposing', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'proposing',
        );
        expect(summary.currentPhase, RoundPhase.proposing);
      });

      test('currentPhase parses rating', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'rating',
        );
        expect(summary.currentPhase, RoundPhase.rating);
      });

      test('currentPhase parses waiting', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'waiting',
        );
        expect(summary.currentPhase, RoundPhase.waiting);
      });

      test('currentPhase returns null for null phase', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );
        expect(summary.currentPhase, isNull);
      });

      test('hasActiveTimer is true when phaseEndsAt and phase are set', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'proposing',
          phaseEndsAt: DateTime.now().add(const Duration(minutes: 5)),
        );
        expect(summary.hasActiveTimer, true);
      });

      test('hasActiveTimer is false when phaseEndsAt is null', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'proposing',
        );
        expect(summary.hasActiveTimer, false);
      });

      test('isPaused is true when schedulePaused', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          schedulePaused: true,
        );
        expect(summary.isPaused, true);
      });

      test('isPaused is true when hostPaused', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          hostPaused: true,
        );
        expect(summary.isPaused, true);
      });

      test('isPaused is false when neither paused', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );
        expect(summary.isPaused, false);
      });

      test('hasActiveRound is true when phase is set', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'proposing',
        );
        expect(summary.hasActiveRound, true);
      });

      test('hasActiveRound is false when phase is null', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );
        expect(summary.hasActiveRound, false);
      });

      test('timeRemaining returns null when phaseEndsAt is null', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );
        expect(summary.timeRemaining, isNull);
      });

      test('timeRemaining returns Duration.zero when past', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          phaseEndsAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        expect(summary.timeRemaining, Duration.zero);
      });

      test('timeRemaining returns positive duration when in future', () {
        final summary = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          phaseEndsAt: DateTime.now().add(const Duration(minutes: 5)),
        );
        expect(summary.timeRemaining!.inSeconds, greaterThan(0));
      });
    });

    group('equality', () {
      test('two summaries with same props are equal', () {
        final summary1 = PublicChatSummary(
          id: 1,
          name: 'Test',
          description: 'Desc',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final summary2 = PublicChatSummary(
          id: 1,
          name: 'Test',
          description: 'Desc',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(summary1, equals(summary2));
      });

      test('two summaries with different IDs are not equal', () {
        final summary1 = PublicChatSummary(
          id: 1,
          name: 'Test',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final summary2 = PublicChatSummary(
          id: 2,
          name: 'Test',
          initialMessage: 'Message',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(summary1, isNot(equals(summary2)));
      });

      test('summaries with different phase fields are not equal', () {
        final summary1 = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'proposing',
        );

        final summary2 = PublicChatSummary(
          id: 1,
          name: 'Test',
          participantCount: 5,
          createdAt: DateTime.utc(2024, 1, 1),
          currentRoundPhase: 'rating',
        );

        expect(summary1, isNot(equals(summary2)));
      });
    });
  });
}
