import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../fixtures/fixtures.dart';

// Mock for testing subscription methods
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockRealtimeChannel extends Mock implements RealtimeChannel {}

void main() {
  late MockSupabaseClient mockClient;
  late ParticipantService participantService;

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
    participantService = ParticipantService(mockClient);
  });

  group('ParticipantService', () {
    // Note: Testing Supabase query builder chains is complex due to the fluent API.
    // These tests focus on subscription methods which are easier to mock.
    // For full service coverage, integration tests with a real Supabase instance
    // are recommended.

    group('subscribeToParticipants', () {
      test('creates realtime channel for participant updates', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();

        when(() => mockClient.channel('participants:10')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenReturn(mockChannel);
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        final channel = participantService.subscribeToParticipants(10, (p) {});

        // Assert
        expect(channel, isNotNull);
        verify(() => mockClient.channel('participants:10')).called(1);
        verify(() => mockChannel.subscribe()).called(1);
      });

      test('subscribes to all events on participants table', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();
        PostgresChangeEvent? capturedEvent;
        String? capturedTable;

        when(() => mockClient.channel('participants:5')).thenReturn(mockChannel);
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
        participantService.subscribeToParticipants(5, (p) {});

        // Assert
        expect(capturedEvent, PostgresChangeEvent.all);
        expect(capturedTable, 'participants');
      });

      test('filters by chat_id in subscription', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();
        PostgresChangeFilter? capturedFilter;

        when(() => mockClient.channel('participants:42')).thenReturn(mockChannel);
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
        participantService.subscribeToParticipants(42, (p) {});

        // Assert
        expect(capturedFilter, isNotNull);
        expect(capturedFilter!.column, 'chat_id');
        expect(capturedFilter!.value, 42);
      });
    });
  });

  group('ParticipantFixtures', () {
    // Test that fixtures produce valid models
    test('json() creates valid Participant JSON', () {
      final json = ParticipantFixtures.json(id: 1);
      expect(() => Participant.fromJson(json), returnsNormally);
    });

    test('model() creates valid Participant', () {
      final participant = ParticipantFixtures.model();
      expect(participant.id, 1);
      expect(participant.displayName, 'Test User');
    });

    test('host() creates host participant', () {
      final participant = ParticipantFixtures.host();
      expect(participant.isHost, isTrue);
    });

    test('authenticated() creates authenticated participant', () {
      final participant = ParticipantFixtures.authenticated();
      expect(participant.isAuthenticated, isTrue);
      expect(participant.userId, isNotNull);
    });

    test('pending() creates pending participant', () {
      final participant = ParticipantFixtures.pending();
      expect(participant.status, ParticipantStatus.pending);
    });

    test('kicked() creates kicked participant', () {
      final participant = ParticipantFixtures.kicked();
      expect(participant.status, ParticipantStatus.kicked);
    });

    test('list() creates multiple participants with host', () {
      final participants = ParticipantFixtures.list(count: 5);
      expect(participants, hasLength(5));
      expect(participants.where((p) => p.isHost), hasLength(1));
    });

    test('list() without host has no host', () {
      final participants = ParticipantFixtures.list(count: 3, includeHost: false);
      expect(participants, hasLength(3));
      expect(participants.where((p) => p.isHost), isEmpty);
    });

    test('mixed() creates variety of participant statuses', () {
      final participants = ParticipantFixtures.mixed();
      expect(participants.any((p) => p.isHost), isTrue);
      expect(participants.any((p) => p.status == ParticipantStatus.pending), isTrue);
      expect(participants.any((p) => p.status == ParticipantStatus.kicked), isTrue);
      expect(participants.any((p) => p.isAuthenticated), isTrue);
    });
  });
}
