import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixtures/fixtures.dart';
import '../mocks/mock_supabase_client.dart';

class MockUser extends Mock implements User {}

/// Awaitable fake for the `.single()` tail of the insert chain.
class _FakeSingleBuilder extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>> {
  _FakeSingleBuilder(this._row);
  final Map<String, dynamic> _row;

  @override
  Future<S> then<S>(FutureOr<S> Function(Map<String, dynamic>) onValue,
          {Function? onError}) =>
      Future<Map<String, dynamic>>.value(_row).then(onValue, onError: onError);
}

/// Fake for the `.select()` step of the insert chain.
class _FakeSelectBuilder extends Fake
    implements PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  _FakeSelectBuilder(this._row);
  final Map<String, dynamic> _row;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() =>
      _FakeSingleBuilder(_row);
}

/// Fake for `from('chats').insert(...)` supporting `.select().single()`.
class _FakeInsertBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  _FakeInsertBuilder(this._row);
  final Map<String, dynamic> _row;

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> select(
          [String columns = '*']) =>
      _FakeSelectBuilder(_row);
}

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late MockSupabaseQueryBuilder mockChats;
  late ChatService chatService;
  late Map<String, dynamic> capturedInsert;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    mockChats = MockSupabaseQueryBuilder();
    final user = MockUser();
    when(() => user.id).thenReturn('user-1');
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(user);
    // SupabaseQueryBuilder implements Future, so thenAnswer (not thenReturn).
    when(() => mockClient.from('chats')).thenAnswer((_) => mockChats);
    when(() => mockChats.insert(any())).thenAnswer((invocation) {
      capturedInsert =
          invocation.positionalArguments[0] as Map<String, dynamic>;
      return _FakeInsertBuilder(ChatFixtures.json());
    });
    chatService = ChatService(mockClient);
  });

  Future<Chat> createChat({
    DateTime? cadenceAnchorAt,
    String? scheduleTimezone,
  }) {
    return chatService.createChat(
      name: 'Test Chat',
      accessMethod: AccessMethod.code,
      requireAuth: false,
      requireApproval: false,
      startMode: StartMode.auto,
      hostDisplayName: 'Host',
      proposingDurationSeconds: 43200,
      ratingDurationSeconds: 43200,
      proposingMinimum: 2,
      ratingMinimum: 2,
      enableAiParticipant: false,
      confirmationRoundsRequired: 1,
      showPreviousResults: false,
      propositionsPerUser: 1,
      cadenceAnchorAt: cadenceAnchorAt,
      scheduleTimezone: scheduleTimezone,
    );
  }

  group('createChat payload — cadence anchor', () {
    test(
        'includes cadence_anchor_at (UTC ISO) and schedule_timezone when set',
        () async {
      final anchor = DateTime.utc(2026, 7, 2, 19, 0);
      await createChat(
        cadenceAnchorAt: anchor,
        scheduleTimezone: 'America/New_York',
      );

      expect(capturedInsert['cadence_anchor_at'],
          anchor.toUtc().toIso8601String());
      expect(capturedInsert['schedule_timezone'], 'America/New_York');
    });

    test('converts a local anchor to UTC', () async {
      final localAnchor = DateTime(2026, 7, 2, 15, 0); // local wall time
      await createChat(
        cadenceAnchorAt: localAnchor,
        scheduleTimezone: 'America/New_York',
      );

      expect(capturedInsert['cadence_anchor_at'],
          localAnchor.toUtc().toIso8601String());
    });

    test('OMITS cadence_anchor_at when no anchor is set (column keeps its '
        'NULL default)', () async {
      await createChat(scheduleTimezone: 'America/New_York');

      expect(capturedInsert.containsKey('cadence_anchor_at'), isFalse);
      // Always-Active chats still send the detected timezone.
      expect(capturedInsert['schedule_timezone'], 'America/New_York');
    });

    test('never sends the deprecated clock_aligned key', () async {
      await createChat(
        cadenceAnchorAt: DateTime.utc(2026, 7, 2, 19, 0),
        scheduleTimezone: 'America/New_York',
      );

      expect(capturedInsert.containsKey('clock_aligned'), isFalse);
    });

    test('omits schedule_timezone when none was detected and no schedule set',
        () async {
      await createChat();

      expect(capturedInsert.containsKey('schedule_timezone'), isFalse);
      expect(capturedInsert.containsKey('cadence_anchor_at'), isFalse);
    });
  });
}
