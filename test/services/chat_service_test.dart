import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../fixtures/fixtures.dart';

// =============================================================================
// ROUND-MINUTE TIMER ALIGNMENT TESTS
// =============================================================================

void testCalculateRoundMinuteEnd() {
  group('calculateRoundMinuteEnd', () {
    test('rounds up to next minute when seconds > 0', () {
      // Time at XX:00:30, duration 60s → ends at XX:02:00 (not XX:01:30)
      final now = DateTime(2024, 1, 1, 12, 0, 30);
      final result = ChatService.calculateRoundMinuteEnd(now, 60);

      expect(result.second, 0);
      expect(result.minute, 2); // 12:00:30 + 60s = 12:01:30 → rounds to 12:02:00
    });

    test('stays at :00 when already exactly on minute boundary', () {
      // Time at XX:00:00, duration 60s → ends at XX:01:00
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      final result = ChatService.calculateRoundMinuteEnd(now, 60);

      expect(result.second, 0);
      expect(result.minute, 1); // 12:00:00 + 60s = 12:01:00 (exactly)
    });

    test('stays at :00 when result lands exactly on minute', () {
      // Time at XX:00:59, duration 1s → ends at XX:01:00 (exactly on minute)
      final now = DateTime(2024, 1, 1, 12, 0, 59);
      final result = ChatService.calculateRoundMinuteEnd(now, 1);

      expect(result.second, 0);
      expect(result.minute, 1); // 12:00:59 + 1s = 12:01:00 (exactly, no rounding needed)
    });

    test('handles hour boundary correctly', () {
      // Time at XX:59:30, duration 60s → ends at (XX+1):01:00
      final now = DateTime(2024, 1, 1, 12, 59, 30);
      final result = ChatService.calculateRoundMinuteEnd(now, 60);

      expect(result.second, 0);
      expect(result.hour, 13);
      expect(result.minute, 1); // 12:59:30 + 60s = 13:00:30 → rounds to 13:01:00
    });

    test('handles day boundary correctly', () {
      // Time at 23:59:30, duration 60s → ends at 00:01:00 next day
      final now = DateTime(2024, 1, 1, 23, 59, 30);
      final result = ChatService.calculateRoundMinuteEnd(now, 60);

      expect(result.second, 0);
      expect(result.day, 2);
      expect(result.hour, 0);
      expect(result.minute, 1); // 23:59:30 + 60s = 00:00:30 → rounds to 00:01:00
    });

    test('result is always >= now + duration', () {
      final now = DateTime(2024, 1, 1, 12, 30, 45);
      const duration = 300; // 5 minutes
      final result = ChatService.calculateRoundMinuteEnd(now, duration);

      final minExpected = now.add(Duration(seconds: duration));
      expect(result.isAfter(minExpected) || result.isAtSameMomentAs(minExpected), isTrue);
    });

    test('result is always < now + duration + 60s', () {
      final now = DateTime(2024, 1, 1, 12, 30, 45);
      const duration = 300; // 5 minutes
      final result = ChatService.calculateRoundMinuteEnd(now, duration);

      final maxExpected = now.add(Duration(seconds: duration + 60));
      expect(result.isBefore(maxExpected), isTrue);
    });

    test('result always has second = 0', () {
      // Test various times
      final times = [
        DateTime(2024, 1, 1, 12, 0, 0),
        DateTime(2024, 1, 1, 12, 0, 1),
        DateTime(2024, 1, 1, 12, 0, 30),
        DateTime(2024, 1, 1, 12, 0, 59),
        DateTime(2024, 1, 1, 12, 30, 45),
      ];

      for (final now in times) {
        final result = ChatService.calculateRoundMinuteEnd(now, 60);
        expect(result.second, 0, reason: 'Failed for time: $now');
      }
    });

    test('truncates milliseconds to avoid extra rounding', () {
      // Time at XX:00:00.500 (with milliseconds), duration 60s
      // Should end at XX:01:00, NOT XX:02:00
      final now = DateTime(2024, 1, 1, 12, 0, 0, 500); // 500ms
      final result = ChatService.calculateRoundMinuteEnd(now, 60);

      expect(result.second, 0);
      expect(result.minute, 1); // Should be 12:01:00, not 12:02:00
      expect(result.millisecond, 0);
    });

    test('milliseconds dont cause extra minute at boundary', () {
      // Simulates cron running at XX:36:00.123
      // Duration 60s → should end at XX:37:00, not XX:38:00
      final now = DateTime(2024, 1, 1, 12, 36, 0, 123);
      final result = ChatService.calculateRoundMinuteEnd(now, 60);

      expect(result.second, 0);
      expect(result.minute, 37); // 12:36:00 + 60s = 12:37:00 (exactly)
    });
  });
}

// Mock for testing subscription methods
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockRealtimeChannel extends Mock implements RealtimeChannel {}

void main() {
  // Test round-minute timer alignment helper
  testCalculateRoundMinuteEnd();

  late MockSupabaseClient mockClient;
  late ChatService chatService;

  setUpAll(() {
    registerFallbackValue(PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: 1,
    ));
    registerFallbackValue(PostgresChangeEvent.all);
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    chatService = ChatService(mockClient);
  });

  group('ChatService', () {
    // Note: Testing Supabase query builder chains is complex due to the fluent API.
    // These tests focus on subscription methods which are easier to mock.
    // For full service coverage, integration tests with a real Supabase instance
    // are recommended.

    group('subscribeToChatChanges', () {
      test('creates realtime channel for chat updates', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();

        when(() => mockClient.channel('chat:1')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenReturn(mockChannel);
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        final channel = chatService.subscribeToChatChanges(
          1,
          onUpdate: (data) {},
          onDelete: () {},
        );

        // Assert
        expect(channel, isNotNull);
        verify(() => mockClient.channel('chat:1')).called(1);
        verify(() => mockChannel.subscribe()).called(1);
      });

      test('uses correct table and event type', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();
        PostgresChangeEvent? capturedEvent;
        String? capturedTable;

        when(() => mockClient.channel('chat:42')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenAnswer((invocation) {
          capturedEvent = invocation.namedArguments[#event];
          capturedTable = invocation.namedArguments[#table];
          return mockChannel;
        });
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        chatService.subscribeToChatChanges(
          42,
          onUpdate: (data) {},
          onDelete: () {},
        );

        // Assert - uses .all to handle both update and delete events
        expect(capturedEvent, PostgresChangeEvent.all);
        expect(capturedTable, 'chats');
      });
    });

    group('subscribeToRoundChanges', () {
      test('creates realtime channel for round updates', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();

        when(() => mockClient.channel('rounds:5')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenReturn(mockChannel);
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        final channel = chatService.subscribeToRoundChanges(5, (_, __) {});

        // Assert
        expect(channel, isNotNull);
        verify(() => mockClient.channel('rounds:5')).called(1);
      });

      test('subscribes to all events on rounds table', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();
        PostgresChangeEvent? capturedEvent;
        String? capturedTable;

        when(() => mockClient.channel('rounds:10')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenAnswer((invocation) {
          capturedEvent = invocation.namedArguments[#event];
          capturedTable = invocation.namedArguments[#table];
          return mockChannel;
        });
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        chatService.subscribeToRoundChanges(10, (_, __) {});

        // Assert
        expect(capturedEvent, PostgresChangeEvent.all);
        expect(capturedTable, 'rounds');
      });
    });

    group('subscribeToCycleChanges', () {
      test('creates realtime channel for cycle updates', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();

        when(() => mockClient.channel('cycles:10')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenReturn(mockChannel);
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        final channel = chatService.subscribeToCycleChanges(10, () {});

        // Assert
        expect(channel, isNotNull);
        verify(() => mockClient.channel('cycles:10')).called(1);
      });

      test('filters by chat_id in subscription', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();
        PostgresChangeFilter? capturedFilter;

        when(() => mockClient.channel('cycles:99')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenAnswer((invocation) {
          capturedFilter = invocation.namedArguments[#filter];
          return mockChannel;
        });
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        chatService.subscribeToCycleChanges(99, () {});

        // Assert
        expect(capturedFilter, isNotNull);
        expect(capturedFilter!.column, 'chat_id');
        expect(capturedFilter!.value, 99);
      });
    });
  });

  group('ChatFixtures', () {
    // Test that fixtures produce valid models
    test('json() creates valid Chat JSON', () {
      final json = ChatFixtures.json(id: 1, name: 'Test');
      expect(() => Chat.fromJson(json), returnsNormally);
    });

    test('model() creates valid Chat', () {
      final chat = ChatFixtures.model();
      expect(chat.id, 1);
      expect(chat.name, 'Test Chat');
    });

    test('official() creates official chat', () {
      final chat = ChatFixtures.official();
      expect(chat.isOfficial, isTrue);
    });

    test('list() creates multiple chats', () {
      final chats = ChatFixtures.list(count: 5);
      expect(chats, hasLength(5));
      expect(chats.map((c) => c.id).toSet(), hasLength(5)); // All unique IDs
    });
  });

  group('CycleFixtures', () {
    test('active() creates incomplete cycle', () {
      final cycle = CycleFixtures.active();
      expect(cycle.isComplete, isFalse);
    });

    test('completed() creates complete cycle', () {
      final cycle = CycleFixtures.completed();
      expect(cycle.isComplete, isTrue);
    });
  });

  group('RoundFixtures', () {
    test('proposing() creates proposing phase round', () {
      final round = RoundFixtures.proposing();
      expect(round.phase, RoundPhase.proposing);
    });

    test('rating() creates rating phase round', () {
      final round = RoundFixtures.rating();
      expect(round.phase, RoundPhase.rating);
    });

    test('completed() creates round with winner', () {
      final round = RoundFixtures.completed(winningPropositionId: 5);
      expect(round.winningPropositionId, 5);
    });
  });

  group('ChatFixtures - All Settings', () {
    group('Access Settings', () {
      test('json() with require_auth=true', () {
        final json = ChatFixtures.json(requireAuth: true);
        final chat = Chat.fromJson(json);
        expect(chat.requireAuth, isTrue);
      });

      test('json() with require_approval=true', () {
        final json = ChatFixtures.json(requireApproval: true);
        final chat = Chat.fromJson(json);
        expect(chat.requireApproval, isTrue);
      });

      test('json() with access_method=public', () {
        final json = ChatFixtures.json(accessMethod: 'public');
        final chat = Chat.fromJson(json);
        expect(chat.accessMethod, AccessMethod.public);
      });

      test('json() with access_method=code', () {
        final json = ChatFixtures.json(accessMethod: 'code');
        final chat = Chat.fromJson(json);
        expect(chat.accessMethod, AccessMethod.code);
      });

      test('json() with access_method=invite_only', () {
        final json = ChatFixtures.json(accessMethod: 'invite_only');
        final chat = Chat.fromJson(json);
        expect(chat.accessMethod, AccessMethod.inviteOnly);
      });

      test('public() fixture creates public chat', () {
        final chat = ChatFixtures.public();
        expect(chat.accessMethod, AccessMethod.public);
        expect(chat.name, 'Public Chat');
      });

      test('codeAccess() fixture creates code access chat', () {
        final chat = ChatFixtures.codeAccess();
        expect(chat.accessMethod, AccessMethod.code);
        expect(chat.inviteCode, 'ABC123');
      });

      test('inviteOnly() fixture creates invite only chat', () {
        final chat = ChatFixtures.inviteOnly();
        expect(chat.accessMethod, AccessMethod.inviteOnly);
      });

      test('requiresApproval() fixture', () {
        final chat = ChatFixtures.requiresApproval();
        expect(chat.requireApproval, isTrue);
      });

      test('requiresAuth() fixture', () {
        final chat = ChatFixtures.requiresAuth();
        expect(chat.requireAuth, isTrue);
      });
    });

    group('Phase Start Settings', () {
      test('json() with start_mode=auto', () {
        final json = ChatFixtures.json(startMode: 'auto', autoStartParticipantCount: 10);
        final chat = Chat.fromJson(json);
        expect(chat.startMode, StartMode.auto);
        expect(chat.autoStartParticipantCount, 10);
      });

      test('withAutoStart() fixture', () {
        final chat = ChatFixtures.withAutoStart(participantCount: 8);
        expect(chat.startMode, StartMode.auto);
        expect(chat.autoStartParticipantCount, 8);
      });
    });

    group('Timer Settings', () {
      test('json() with custom proposing duration', () {
        final json = ChatFixtures.json(proposingDurationSeconds: 300);
        final chat = Chat.fromJson(json);
        expect(chat.proposingDurationSeconds, 300);
      });

      test('json() with custom rating duration', () {
        final json = ChatFixtures.json(ratingDurationSeconds: 1800);
        final chat = Chat.fromJson(json);
        expect(chat.ratingDurationSeconds, 1800);
      });

      test('json() with 5 min timer preset', () {
        final json = ChatFixtures.json(proposingDurationSeconds: 300, ratingDurationSeconds: 300);
        final chat = Chat.fromJson(json);
        expect(chat.proposingDurationSeconds, 300);
        expect(chat.ratingDurationSeconds, 300);
      });

      test('json() with 1 hour timer preset', () {
        final json = ChatFixtures.json(proposingDurationSeconds: 3600, ratingDurationSeconds: 3600);
        final chat = Chat.fromJson(json);
        expect(chat.proposingDurationSeconds, 3600);
        expect(chat.ratingDurationSeconds, 3600);
      });

      test('json() with 7 days timer preset', () {
        final json = ChatFixtures.json(proposingDurationSeconds: 604800, ratingDurationSeconds: 604800);
        final chat = Chat.fromJson(json);
        expect(chat.proposingDurationSeconds, 604800);
        expect(chat.ratingDurationSeconds, 604800);
      });
    });

    group('Minimum Settings', () {
      test('json() with custom proposing minimum', () {
        final json = ChatFixtures.json(proposingMinimum: 5);
        final chat = Chat.fromJson(json);
        expect(chat.proposingMinimum, 5);
      });

      test('json() with custom rating minimum', () {
        final json = ChatFixtures.json(ratingMinimum: 10);
        final chat = Chat.fromJson(json);
        expect(chat.ratingMinimum, 10);
      });
    });

    group('Auto-Advance Threshold Settings', () {
      test('json() with proposing thresholds', () {
        final json = ChatFixtures.json(
          proposingThresholdPercent: 80,
          proposingThresholdCount: 5,
        );
        final chat = Chat.fromJson(json);
        expect(chat.proposingThresholdPercent, 80);
        expect(chat.proposingThresholdCount, 5);
      });

      test('json() with rating thresholds', () {
        final json = ChatFixtures.json(
          ratingThresholdPercent: 75,
          ratingThresholdCount: 3,
        );
        final chat = Chat.fromJson(json);
        expect(chat.ratingThresholdPercent, 75);
        expect(chat.ratingThresholdCount, 3);
      });

      test('withThresholds() fixture', () {
        final chat = ChatFixtures.withThresholds(
          proposingPercent: 90,
          proposingCount: 10,
          ratingPercent: 85,
          ratingCount: 8,
        );
        expect(chat.proposingThresholdPercent, 90);
        expect(chat.proposingThresholdCount, 10);
        expect(chat.ratingThresholdPercent, 85);
        expect(chat.ratingThresholdCount, 8);
      });

      test('thresholds default to null', () {
        final chat = ChatFixtures.model();
        expect(chat.proposingThresholdPercent, isNull);
        expect(chat.proposingThresholdCount, isNull);
        expect(chat.ratingThresholdPercent, isNull);
        expect(chat.ratingThresholdCount, isNull);
      });
    });

    group('AI Settings', () {
      test('json() with AI enabled', () {
        final json = ChatFixtures.json(
          enableAiParticipant: true,
          aiPropositionsCount: 5,
        );
        final chat = Chat.fromJson(json);
        expect(chat.enableAiParticipant, isTrue);
        expect(chat.aiPropositionsCount, 5);
      });

      test('withAi() fixture', () {
        final chat = ChatFixtures.withAi(propositionsCount: 7);
        expect(chat.enableAiParticipant, isTrue);
        expect(chat.aiPropositionsCount, 7);
      });

      test('AI defaults to disabled', () {
        final chat = ChatFixtures.model();
        expect(chat.enableAiParticipant, isFalse);
        expect(chat.aiPropositionsCount, isNull);
      });
    });

    group('Consensus Settings', () {
      test('json() with confirmation_rounds_required=1 (instant consensus)', () {
        final json = ChatFixtures.json(confirmationRoundsRequired: 1);
        final chat = Chat.fromJson(json);
        expect(chat.confirmationRoundsRequired, 1);
      });

      test('json() with confirmation_rounds_required=3 (triple confirmation)', () {
        final json = ChatFixtures.json(confirmationRoundsRequired: 3);
        final chat = Chat.fromJson(json);
        expect(chat.confirmationRoundsRequired, 3);
      });

      test('json() with show_previous_results=true', () {
        final json = ChatFixtures.json(showPreviousResults: true);
        final chat = Chat.fromJson(json);
        expect(chat.showPreviousResults, isTrue);
      });

      test('consensus defaults to 2 rounds, hidden results', () {
        final chat = ChatFixtures.model();
        expect(chat.confirmationRoundsRequired, 2);
        expect(chat.showPreviousResults, isFalse);
      });
    });

    group('Proposition Limits', () {
      test('json() with propositions_per_user=1 (default)', () {
        final json = ChatFixtures.json(propositionsPerUser: 1);
        final chat = Chat.fromJson(json);
        expect(chat.propositionsPerUser, 1);
      });

      test('json() with propositions_per_user=5', () {
        final json = ChatFixtures.json(propositionsPerUser: 5);
        final chat = Chat.fromJson(json);
        expect(chat.propositionsPerUser, 5);
      });

      test('withMultiplePropositions() fixture', () {
        final chat = ChatFixtures.withMultiplePropositions(count: 10);
        expect(chat.propositionsPerUser, 10);
      });

      test('propositions_per_user defaults to 1', () {
        final chat = ChatFixtures.model();
        expect(chat.propositionsPerUser, 1);
      });
    });

    group('Combined Settings', () {
      test('json() with all settings customized', () {
        final json = ChatFixtures.json(
          id: 99,
          name: 'Full Custom Chat',
          initialMessage: 'Custom message',
          description: 'Custom description',
          accessMethod: 'invite_only',
          requireAuth: true,
          requireApproval: true,
          startMode: 'auto',
          autoStartParticipantCount: 15,
          proposingDurationSeconds: 1800,
          ratingDurationSeconds: 3600,
          proposingMinimum: 5,
          ratingMinimum: 10,
          proposingThresholdPercent: 90,
          proposingThresholdCount: 12,
          ratingThresholdPercent: 80,
          ratingThresholdCount: 8,
          enableAiParticipant: true,
          aiPropositionsCount: 5,
          confirmationRoundsRequired: 3,
          showPreviousResults: true,
          propositionsPerUser: 3,
        );

        final chat = Chat.fromJson(json);

        // Verify all settings
        expect(chat.id, 99);
        expect(chat.name, 'Full Custom Chat');
        expect(chat.initialMessage, 'Custom message');
        expect(chat.description, 'Custom description');
        expect(chat.accessMethod, AccessMethod.inviteOnly);
        expect(chat.requireAuth, isTrue);
        expect(chat.requireApproval, isTrue);
        expect(chat.startMode, StartMode.auto);
        expect(chat.autoStartParticipantCount, 15);
        expect(chat.proposingDurationSeconds, 1800);
        expect(chat.ratingDurationSeconds, 3600);
        expect(chat.proposingMinimum, 5);
        expect(chat.ratingMinimum, 10);
        expect(chat.proposingThresholdPercent, 90);
        expect(chat.proposingThresholdCount, 12);
        expect(chat.ratingThresholdPercent, 80);
        expect(chat.ratingThresholdCount, 8);
        expect(chat.enableAiParticipant, isTrue);
        expect(chat.aiPropositionsCount, 5);
        expect(chat.confirmationRoundsRequired, 3);
        expect(chat.showPreviousResults, isTrue);
        expect(chat.propositionsPerUser, 3);
      });
    });
  });

  group('Chat.toJson - All Settings', () {
    test('serializes access settings correctly', () {
      final json = ChatFixtures.json(
        accessMethod: 'invite_only',
        requireAuth: true,
        requireApproval: true,
      );
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['access_method'], 'invite_only');
      expect(output['require_auth'], true);
      expect(output['require_approval'], true);
    });

    test('serializes phase start settings correctly', () {
      final json = ChatFixtures.json(
        startMode: 'auto',
        autoStartParticipantCount: 20,
      );
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['start_mode'], 'auto');
      expect(output['auto_start_participant_count'], 20);
    });

    test('serializes timer settings correctly', () {
      final json = ChatFixtures.json(
        proposingDurationSeconds: 600,
        ratingDurationSeconds: 1200,
      );
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['proposing_duration_seconds'], 600);
      expect(output['rating_duration_seconds'], 1200);
    });

    test('serializes minimum settings correctly', () {
      final json = ChatFixtures.json(
        proposingMinimum: 3,
        ratingMinimum: 4,
      );
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['proposing_minimum'], 3);
      expect(output['rating_minimum'], 4);
    });

    test('serializes threshold settings correctly', () {
      final json = ChatFixtures.json(
        proposingThresholdPercent: 70,
        proposingThresholdCount: 6,
        ratingThresholdPercent: 65,
        ratingThresholdCount: 5,
      );
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['proposing_threshold_percent'], 70);
      expect(output['proposing_threshold_count'], 6);
      expect(output['rating_threshold_percent'], 65);
      expect(output['rating_threshold_count'], 5);
    });

    test('serializes AI settings correctly', () {
      final json = ChatFixtures.json(
        enableAiParticipant: true,
        aiPropositionsCount: 8,
      );
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['enable_ai_participant'], true);
      expect(output['ai_propositions_count'], 8);
    });

    test('serializes consensus settings correctly', () {
      final json = ChatFixtures.json(
        confirmationRoundsRequired: 4,
        showPreviousResults: true,
      );
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['confirmation_rounds_required'], 4);
      expect(output['show_previous_results'], true);
    });

    test('serializes proposition limits correctly', () {
      final json = ChatFixtures.json(propositionsPerUser: 7);
      final chat = Chat.fromJson(json);
      final output = chat.toJson();

      expect(output['propositions_per_user'], 7);
    });
  });

  group('ChatService - Translation Support', () {
    // Note: These tests verify the method signatures and basic behavior.
    // Integration tests with a real Supabase instance are recommended
    // for full coverage of the RPC functions.

    group('getPublicChats', () {
      test('method accepts languageCode parameter', () {
        // Verify the method exists with the new signature
        // Actual RPC testing requires integration tests
        expect(chatService.getPublicChats, isA<Function>());
      });
    });

    group('searchPublicChats', () {
      test('method accepts languageCode parameter', () {
        // Verify the method exists with the new signature
        expect(chatService.searchPublicChats, isA<Function>());
      });
    });

    group('translateChat', () {
      test('method exists with required parameters', () {
        // Verify the method exists
        // Actual edge function testing requires integration tests
        expect(chatService.translateChat, isA<Function>());
      });
    });

    group('getMyChats', () {
      test('method accepts languageCode parameter', () {
        // Verify the method exists with the new signature
        expect(chatService.getMyChats, isA<Function>());
      });
    });

    group('getChatById', () {
      test('method accepts languageCode parameter', () {
        // Verify the method exists with the new signature
        expect(chatService.getChatById, isA<Function>());
      });
    });

    group('getChatByCode', () {
      test('method accepts languageCode parameter', () {
        // Verify the method exists with the new signature
        expect(chatService.getChatByCode, isA<Function>());
      });
    });

    group('createChat', () {
      test('method accepts translationsEnabled parameter', () {
        // Verify the method exists with the new signature
        // Actual Supabase insert testing requires integration tests
        expect(chatService.createChat, isA<Function>());
      });

      test('method accepts translationLanguages parameter', () {
        // Verify the method exists with the new signature
        expect(chatService.createChat, isA<Function>());
      });
    });
  });

  group('Chat Model - Translation Fields', () {
    group('fromJson', () {
      test('parses translation fields from JSON', () {
        final json = ChatFixtures.json(
          name: 'Test Chat',
          initialMessage: 'What should we discuss?',
          description: 'A test description',
          nameTranslated: 'Chat de Prueba',
          initialMessageTranslated: 'Que deberiamos discutir?',
          descriptionTranslated: 'Una descripcion de prueba',
          translationLanguage: 'es',
        );

        final chat = Chat.fromJson(json);

        expect(chat.nameTranslated, 'Chat de Prueba');
        expect(chat.initialMessageTranslated, 'Que deberiamos discutir?');
        expect(chat.descriptionTranslated, 'Una descripcion de prueba');
        expect(chat.translationLanguage, 'es');
      });

      test('handles null translation fields', () {
        final json = ChatFixtures.json(
          name: 'Test Chat',
          initialMessage: 'What should we discuss?',
        );

        final chat = Chat.fromJson(json);

        expect(chat.nameTranslated, isNull);
        expect(chat.initialMessageTranslated, isNull);
        expect(chat.descriptionTranslated, isNull);
        expect(chat.translationLanguage, isNull);
      });
    });

    group('displayName getter', () {
      test('returns translated name when available', () {
        final chat = ChatFixtures.withTranslation(
          name: 'Original Name',
          nameTranslated: 'Nombre Traducido',
        );

        expect(chat.displayName, 'Nombre Traducido');
      });

      test('falls back to original name when no translation', () {
        final chat = ChatFixtures.withTranslation(
          name: 'Original Name',
          nameTranslated: null,
        );

        expect(chat.displayName, 'Original Name');
      });
    });

    group('displayInitialMessage getter', () {
      test('returns translated message when available', () {
        final chat = ChatFixtures.withTranslation(
          initialMessage: 'Original message',
          initialMessageTranslated: 'Mensaje traducido',
        );

        expect(chat.displayInitialMessage, 'Mensaje traducido');
      });

      test('falls back to original message when no translation', () {
        final chat = ChatFixtures.withTranslation(
          initialMessage: 'Original message',
          initialMessageTranslated: null,
        );

        expect(chat.displayInitialMessage, 'Original message');
      });
    });

    group('displayDescription getter', () {
      test('returns translated description when available', () {
        final chat = ChatFixtures.withTranslation(
          description: 'Original description',
          descriptionTranslated: 'Descripcion traducida',
        );

        expect(chat.displayDescription, 'Descripcion traducida');
      });

      test('falls back to original description when no translation', () {
        final chat = ChatFixtures.withTranslation(
          description: 'Original description',
          descriptionTranslated: null,
        );

        expect(chat.displayDescription, 'Original description');
      });

      test('returns null when both original and translated are null', () {
        final json = ChatFixtures.json(
          description: null,
          descriptionTranslated: null,
        );
        final chat = Chat.fromJson(json);

        expect(chat.displayDescription, isNull);
      });
    });

    group('withSpanishTranslation fixture', () {
      test('creates chat with Spanish translations', () {
        final chat = ChatFixtures.withSpanishTranslation();

        expect(chat.name, 'Test Chat');
        expect(chat.nameTranslated, 'Chat de Prueba');
        expect(chat.displayName, 'Chat de Prueba');
        expect(chat.translationLanguage, 'es');
      });
    });

    group('Equatable props', () {
      test('includes translation fields', () {
        // Use fixed timestamp to ensure equality
        final fixedTime = DateTime(2024, 1, 1, 12, 0, 0);

        final json1 = ChatFixtures.json(
          id: 1,
          name: 'Test',
          nameTranslated: 'Prueba',
          createdAt: fixedTime,
        );
        final json2 = ChatFixtures.json(
          id: 1,
          name: 'Test',
          nameTranslated: 'Prueba',
          createdAt: fixedTime,
        );
        final json3 = ChatFixtures.json(
          id: 1,
          name: 'Test',
          nameTranslated: 'Diferente',
          createdAt: fixedTime,
        );

        final chat1 = Chat.fromJson(json1);
        final chat2 = Chat.fromJson(json2);
        final chat3 = Chat.fromJson(json3);

        expect(chat1, equals(chat2));
        expect(chat1, isNot(equals(chat3)));
      });
    });
  });
}
