import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/chat.dart';

import '../fixtures/chat_fixtures.dart';

void main() {
  group('Chat', () {
    group('fromJson', () {
      test('parses minimal required fields', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'initial_message': 'What should we discuss?',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);

        expect(chat.id, 1);
        expect(chat.name, 'Test Chat');
        expect(chat.initialMessage, 'What should we discuss?');
        expect(chat.accessMethod, AccessMethod.public); // Default is now public
        expect(chat.requireAuth, false);
        expect(chat.requireApproval, false);
        expect(chat.isActive, true);
        expect(chat.isOfficial, false);
        expect(chat.startMode, StartMode.manual);
        expect(chat.proposingDurationSeconds, 86400);
        expect(chat.ratingDurationSeconds, 86400);
        expect(chat.proposingMinimum, 2);
        expect(chat.ratingMinimum, 2);
        expect(chat.enableAiParticipant, false);
        expect(chat.confirmationRoundsRequired, 2);
        expect(chat.showPreviousResults, false);
        expect(chat.propositionsPerUser, 1);
      });

      test('parses null initial_message', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'initial_message': null,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);

        expect(chat.id, 1);
        expect(chat.name, 'Test Chat');
        expect(chat.initialMessage, isNull);
        expect(chat.displayInitialMessage, '');
      });

      test('parses missing initial_message', () {
        final json = {
          'id': 1,
          'name': 'Test Chat',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);

        expect(chat.initialMessage, isNull);
        expect(chat.displayInitialMessage, '');
      });

      test('parses all fields', () {
        final json = {
          'id': 1,
          'name': 'Full Test Chat',
          'initial_message': 'Test message',
          'description': 'A description',
          'invite_code': 'ABC123',
          'access_method': 'invite_only',
          'require_auth': true,
          'require_approval': true,
          'creator_id': 'user-123',
          'creator_session_token': 'session-456',
          'is_active': true,
          'is_official': true,
          'expires_at': '2024-12-31T23:59:59Z',
          'last_activity_at': '2024-06-15T12:00:00Z',
          'start_mode': 'auto',
          'auto_start_participant_count': 10,
          'proposing_duration_seconds': 3600,
          'rating_duration_seconds': 1800,
          'proposing_minimum': 5,
          'rating_minimum': 3,
          'proposing_threshold_percent': 80,
          'proposing_threshold_count': 10,
          'rating_threshold_percent': 75,
          'rating_threshold_count': 8,
          'enable_ai_participant': true,
          'ai_propositions_count': 5,
          'confirmation_rounds_required': 3,
          'show_previous_results': true,
          'propositions_per_user': 5,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);

        expect(chat.id, 1);
        expect(chat.name, 'Full Test Chat');
        expect(chat.initialMessage, 'Test message');
        expect(chat.description, 'A description');
        expect(chat.inviteCode, 'ABC123');
        expect(chat.accessMethod, AccessMethod.inviteOnly);
        expect(chat.requireAuth, true);
        expect(chat.requireApproval, true);
        expect(chat.creatorId, 'user-123');
        expect(chat.creatorSessionToken, 'session-456');
        expect(chat.isActive, true);
        expect(chat.isOfficial, true);
        expect(chat.expiresAt, DateTime.utc(2024, 12, 31, 23, 59, 59));
        expect(chat.lastActivityAt, DateTime.utc(2024, 6, 15, 12, 0, 0));
        expect(chat.startMode, StartMode.auto);
        expect(chat.autoStartParticipantCount, 10);
        expect(chat.proposingDurationSeconds, 3600);
        expect(chat.ratingDurationSeconds, 1800);
        expect(chat.proposingMinimum, 5);
        expect(chat.ratingMinimum, 3);
        expect(chat.proposingThresholdPercent, 80);
        expect(chat.proposingThresholdCount, 10);
        expect(chat.ratingThresholdPercent, 75);
        expect(chat.ratingThresholdCount, 8);
        expect(chat.enableAiParticipant, true);
        expect(chat.aiPropositionsCount, 5);
        expect(chat.confirmationRoundsRequired, 3);
        expect(chat.showPreviousResults, true);
        expect(chat.propositionsPerUser, 5);
      });

      test('parses access_method public', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'access_method': 'public',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.accessMethod, AccessMethod.public);
      });

      test('parses access_method code', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'access_method': 'code',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.accessMethod, AccessMethod.code);
      });

      test('parses access_method invite_only', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'access_method': 'invite_only',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.accessMethod, AccessMethod.inviteOnly);
      });

      test('defaults access_method to public when null or unknown', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.accessMethod, AccessMethod.public);
      });

      test('parses start_mode manual', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'start_mode': 'manual',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.startMode, StartMode.manual);
      });

      test('parses start_mode auto', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'start_mode': 'auto',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.startMode, StartMode.auto);
      });

      test('parses start_mode scheduled as manual (backwards compatibility)', () {
        // 'scheduled' is no longer a valid start_mode - schedule is now independent
        // For backwards compatibility, 'scheduled' maps to 'manual'
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'start_mode': 'scheduled',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.startMode, StartMode.manual);
      });

      test('parses rating_start_mode auto', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'rating_start_mode': 'auto',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.ratingStartMode, StartMode.auto);
      });

      test('parses rating_start_mode manual', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'rating_start_mode': 'manual',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.ratingStartMode, StartMode.manual);
      });

      test('defaults rating_start_mode to auto when null', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.ratingStartMode, StartMode.auto);
      });

      test('parses schedule_type once', () {
        final json = ChatFixtures.json(
          startMode: 'scheduled',
          scheduleType: 'once',
          scheduledStartAt: DateTime.utc(2024, 6, 15, 10, 0, 0),
        );

        final chat = Chat.fromJson(json);
        expect(chat.scheduleType, ScheduleType.once);
        expect(chat.scheduledStartAt, DateTime.utc(2024, 6, 15, 10, 0, 0));
      });

      test('parses schedule_type recurring', () {
        final json = ChatFixtures.json(
          startMode: 'scheduled',
          scheduleType: 'recurring',
          scheduleWindows: [
            {
              'start_day': 'monday',
              'start_time': '09:00',
              'end_day': 'monday',
              'end_time': '10:00',
            },
            {
              'start_day': 'wednesday',
              'start_time': '09:00',
              'end_day': 'wednesday',
              'end_time': '10:00',
            },
            {
              'start_day': 'friday',
              'start_time': '09:00',
              'end_day': 'friday',
              'end_time': '10:00',
            },
          ],
          scheduleTimezone: 'America/New_York',
        );

        final chat = Chat.fromJson(json);
        expect(chat.scheduleType, ScheduleType.recurring);
        expect(chat.scheduleWindows.length, 3);
        expect(chat.scheduleWindows[0].startDay, 'monday');
        expect(chat.scheduleWindows[0].startTimeOfDay, const TimeOfDay(hour: 9, minute: 0));
        expect(chat.scheduleWindows[0].endTimeOfDay, const TimeOfDay(hour: 10, minute: 0));
        expect(chat.scheduleTimezone, 'America/New_York');
      });

      test('parses visible_outside_schedule', () {
        final json = ChatFixtures.json(
          startMode: 'scheduled',
          scheduleType: 'recurring',
          scheduleWindows: [
            {
              'start_day': 'wednesday',
              'start_time': '10:00',
              'end_day': 'wednesday',
              'end_time': '11:00',
            },
          ],
          visibleOutsideSchedule: false,
        );

        final chat = Chat.fromJson(json);
        expect(chat.visibleOutsideSchedule, false);
      });

      test('parses schedule_paused', () {
        final json = ChatFixtures.json(
          startMode: 'scheduled',
          scheduleType: 'recurring',
          scheduleWindows: [
            {
              'start_day': 'monday',
              'start_time': '09:00',
              'end_day': 'monday',
              'end_time': '10:00',
            },
          ],
          schedulePaused: true,
        );

        final chat = Chat.fromJson(json);
        expect(chat.schedulePaused, true);
      });

      test('parses host_paused', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'host_paused': true,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.hostPaused, true);
      });

      test('defaults host_paused to false', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.hostPaused, false);
      });

      test('isPaused returns true when schedulePaused is true', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'schedule_paused': true,
          'host_paused': false,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.isPaused, true);
      });

      test('isPaused returns true when hostPaused is true', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'schedule_paused': false,
          'host_paused': true,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.isPaused, true);
      });

      test('isPaused returns true when both pauses are true', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'schedule_paused': true,
          'host_paused': true,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.isPaused, true);
      });

      test('isPaused returns false when neither pause is true', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'schedule_paused': false,
          'host_paused': false,
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.isPaused, false);
      });

      test('defaults schedule fields correctly', () {
        final json = {
          'id': 1,
          'name': 'Test',
          'initial_message': 'Test',
          'created_at': '2024-01-01T00:00:00Z',
        };

        final chat = Chat.fromJson(json);
        expect(chat.scheduleType, isNull);
        expect(chat.scheduleTimezone, 'UTC');
        expect(chat.scheduledStartAt, isNull);
        expect(chat.scheduleWindows, isEmpty);
        expect(chat.visibleOutsideSchedule, true);
        expect(chat.schedulePaused, false);
      });
    });

    group('toJson', () {
      test('serializes public access method correctly', () {
        final chat = Chat(
          id: 1,
          name: 'Public Chat',
          initialMessage: 'Test message',
          accessMethod: AccessMethod.public,
          requireAuth: false,
          requireApproval: false,
          isActive: true,
          isOfficial: false,
          startMode: StartMode.manual,
          proposingDurationSeconds: 86400,
          ratingDurationSeconds: 86400,
          proposingMinimum: 2,
          ratingMinimum: 2,
          enableAiParticipant: false,
          confirmationRoundsRequired: 2,
          showPreviousResults: false,
          propositionsPerUser: 1,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final json = chat.toJson();
        expect(json['access_method'], 'public');
      });

      test('serializes correctly', () {
        final chat = Chat(
          id: 1,
          name: 'Test Chat',
          initialMessage: 'Test message',
          description: 'Description',
          accessMethod: AccessMethod.inviteOnly,
          requireAuth: true,
          requireApproval: true,
          creatorId: 'user-123',
          creatorSessionToken: 'session-456',
          isActive: true,
          isOfficial: false,
          startMode: StartMode.auto,
          autoStartParticipantCount: 10,
          proposingDurationSeconds: 3600,
          ratingDurationSeconds: 1800,
          proposingMinimum: 5,
          ratingMinimum: 3,
          proposingThresholdPercent: 80,
          proposingThresholdCount: 10,
          ratingThresholdPercent: 75,
          ratingThresholdCount: 8,
          enableAiParticipant: true,
          aiPropositionsCount: 5,
          confirmationRoundsRequired: 3,
          showPreviousResults: true,
          propositionsPerUser: 5,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final json = chat.toJson();

        expect(json['name'], 'Test Chat');
        expect(json['initial_message'], 'Test message');
        expect(json['description'], 'Description');
        expect(json['access_method'], 'invite_only');
        expect(json['require_auth'], true);
        expect(json['require_approval'], true);
        expect(json['creator_id'], 'user-123');
        expect(json['creator_session_token'], 'session-456');
        expect(json['start_mode'], 'auto');
        expect(json['auto_start_participant_count'], 10);
        expect(json['proposing_duration_seconds'], 3600);
        expect(json['rating_duration_seconds'], 1800);
        expect(json['proposing_minimum'], 5);
        expect(json['rating_minimum'], 3);
        expect(json['proposing_threshold_percent'], 80);
        expect(json['proposing_threshold_count'], 10);
        expect(json['rating_threshold_percent'], 75);
        expect(json['rating_threshold_count'], 8);
        expect(json['enable_ai_participant'], true);
        expect(json['ai_propositions_count'], 5);
        expect(json['confirmation_rounds_required'], 3);
        expect(json['show_previous_results'], true);
        expect(json['propositions_per_user'], 5);
      });

      test('serializes schedule fields for one-time schedule', () {
        // Schedule is now independent of start_mode
        final scheduledTime = DateTime.utc(2024, 6, 15, 10, 0, 0);
        final chat = Chat(
          id: 1,
          name: 'Scheduled Chat',
          initialMessage: 'Test',
          accessMethod: AccessMethod.code,
          requireAuth: false,
          requireApproval: false,
          isActive: true,
          isOfficial: false,
          startMode: StartMode.manual,
          proposingDurationSeconds: 86400,
          ratingDurationSeconds: 86400,
          proposingMinimum: 2,
          ratingMinimum: 2,
          enableAiParticipant: false,
          confirmationRoundsRequired: 2,
          showPreviousResults: false,
          propositionsPerUser: 1,
          createdAt: DateTime.utc(2024, 1, 1),
          scheduleType: ScheduleType.once,
          scheduledStartAt: scheduledTime,
        );

        final json = chat.toJson();

        expect(json['start_mode'], 'manual');
        expect(json['schedule_type'], 'once');
        expect(json['scheduled_start_at'], scheduledTime.toIso8601String());
        expect(chat.hasSchedule, true);
      });

      test('serializes schedule fields for recurring schedule', () {
        // Schedule is now independent of start_mode
        final chat = Chat(
          id: 1,
          name: 'Recurring Chat',
          initialMessage: 'Test',
          accessMethod: AccessMethod.code,
          requireAuth: false,
          requireApproval: false,
          isActive: true,
          isOfficial: false,
          startMode: StartMode.manual,
          proposingDurationSeconds: 300,
          ratingDurationSeconds: 300,
          proposingMinimum: 2,
          ratingMinimum: 2,
          enableAiParticipant: false,
          confirmationRoundsRequired: 2,
          showPreviousResults: false,
          propositionsPerUser: 1,
          createdAt: DateTime.utc(2024, 1, 1),
          scheduleType: ScheduleType.recurring,
          scheduleTimezone: 'America/New_York',
          scheduleWindows: const [
            ScheduleWindow(
              startDay: 'monday',
              startTime: '10:30',
              endDay: 'monday',
              endTime: '11:00',
            ),
            ScheduleWindow(
              startDay: 'wednesday',
              startTime: '10:30',
              endDay: 'wednesday',
              endTime: '11:00',
            ),
            ScheduleWindow(
              startDay: 'friday',
              startTime: '10:30',
              endDay: 'friday',
              endTime: '11:00',
            ),
          ],
          visibleOutsideSchedule: false,
        );

        final json = chat.toJson();

        expect(json['start_mode'], 'manual');
        expect(json['schedule_type'], 'recurring');
        expect(json['schedule_timezone'], 'America/New_York');
        expect(json['schedule_windows'], isNotNull);
        expect((json['schedule_windows'] as List).length, 3);
        expect(json['visible_outside_schedule'], false);
        expect(chat.hasSchedule, true);
      });
    });

    group('fixtures', () {
      test('ChatFixtures.scheduledOnce creates one-time scheduled chat', () {
        // Schedule is now independent of start_mode
        final chat = ChatFixtures.scheduledOnce();
        expect(chat.startMode, StartMode.manual);
        expect(chat.hasSchedule, true);
        expect(chat.scheduleType, ScheduleType.once);
        expect(chat.scheduledStartAt, isNotNull);
      });

      test('ChatFixtures.scheduledRecurring creates recurring scheduled chat', () {
        // Schedule is now independent of start_mode
        final chat = ChatFixtures.scheduledRecurring(
          windows: [
            {
              'start_day': 'tuesday',
              'start_time': '14:00',
              'end_day': 'tuesday',
              'end_time': '15:30',
            },
            {
              'start_day': 'thursday',
              'start_time': '14:00',
              'end_day': 'thursday',
              'end_time': '15:30',
            },
          ],
          timezone: 'Europe/London',
        );
        expect(chat.startMode, StartMode.manual);
        expect(chat.hasSchedule, true);
        expect(chat.scheduleType, ScheduleType.recurring);
        expect(chat.scheduleWindows.length, 2);
        expect(chat.scheduleWindows[0].startDay, 'tuesday');
        expect(chat.scheduleWindows[0].startTimeOfDay, const TimeOfDay(hour: 14, minute: 0));
        expect(chat.scheduleWindows[0].endTimeOfDay, const TimeOfDay(hour: 15, minute: 30));
        expect(chat.scheduleTimezone, 'Europe/London');
      });

      test('ChatFixtures.schedulePaused creates paused scheduled chat', () {
        // Schedule is now independent of start_mode
        final chat = ChatFixtures.schedulePaused();
        expect(chat.startMode, StartMode.manual);
        expect(chat.hasSchedule, true);
        expect(chat.schedulePaused, true);
      });
    });

    group('hasSchedule', () {
      test('returns true when scheduleType is set', () {
        final chat = ChatFixtures.scheduledOnce();
        expect(chat.hasSchedule, true);
      });

      test('returns false when scheduleType is null', () {
        final chat = ChatFixtures.model();
        expect(chat.hasSchedule, false);
      });
    });

    group('displayInitialMessage', () {
      test('returns initialMessage when present', () {
        final chat = ChatFixtures.model(initialMessage: 'Test message');
        expect(chat.displayInitialMessage, 'Test message');
      });

      test('returns empty string when initialMessage is null', () {
        final chat = Chat.fromJson({
          'id': 1,
          'name': 'Test',
          'initial_message': null,
          'created_at': '2024-01-01T00:00:00Z',
        });
        expect(chat.displayInitialMessage, '');
      });

      test('returns translation when available', () {
        final chat = ChatFixtures.withTranslation(
          initialMessage: 'Original',
          initialMessageTranslated: 'Translated',
          translationLanguage: 'es',
        );
        expect(chat.displayInitialMessage, 'Translated');
      });

      test('returns translation over empty string', () {
        final chat = Chat.fromJson({
          'id': 1,
          'name': 'Test',
          'initial_message': null,
          'initial_message_translated': 'Translated',
          'created_at': '2024-01-01T00:00:00Z',
        });
        expect(chat.displayInitialMessage, 'Translated');
      });
    });

    group('equality', () {
      test('two chats with same id are equal', () {
        final chat1 = Chat(
          id: 1,
          name: 'Test',
          initialMessage: 'Test',
          accessMethod: AccessMethod.code,
          requireAuth: false,
          requireApproval: false,
          isActive: true,
          isOfficial: false,
          startMode: StartMode.manual,
          proposingDurationSeconds: 86400,
          ratingDurationSeconds: 86400,
          proposingMinimum: 2,
          ratingMinimum: 2,
          enableAiParticipant: false,
          confirmationRoundsRequired: 2,
          showPreviousResults: false,
          propositionsPerUser: 1,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        final chat2 = Chat(
          id: 1,
          name: 'Test',
          initialMessage: 'Test',
          accessMethod: AccessMethod.code,
          requireAuth: false,
          requireApproval: false,
          isActive: true,
          isOfficial: false,
          startMode: StartMode.manual,
          proposingDurationSeconds: 86400,
          ratingDurationSeconds: 86400,
          proposingMinimum: 2,
          ratingMinimum: 2,
          enableAiParticipant: false,
          confirmationRoundsRequired: 2,
          showPreviousResults: false,
          propositionsPerUser: 1,
          createdAt: DateTime.utc(2024, 1, 1),
        );

        expect(chat1, equals(chat2));
      });
    });
  });
}
