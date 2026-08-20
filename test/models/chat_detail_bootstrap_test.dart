import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/chat_detail_bootstrap.dart';

import '../fixtures/chat_fixtures.dart';
import '../fixtures/cycle_fixtures.dart';
import '../fixtures/participant_fixtures.dart';
import '../fixtures/round_fixtures.dart';

/// Unit tests for `ChatDetailBootstrap.fromJson`. The bootstrap RPC returns
/// one large JSONB; this layer is the seam where it crosses into typed
/// Flutter models. Each parser branch needs to round-trip cleanly.
void main() {
  group('ChatDetailBootstrap.fromJson', () {
    test('parses an empty (no-cycle) payload', () {
      final json = _baseJson(chat: ChatFixtures.json());
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.chat, isNotNull);
      expect(boot.currentCycle, isNull);
      expect(boot.currentRound, isNull);
      expect(boot.consensusItems, isEmpty);
      expect(boot.participants, isEmpty);
      expect(boot.myParticipant, isNull);
      expect(boot.pendingJoinRequests, isEmpty);
      expect(boot.previousRoundWinners, isEmpty);
      expect(boot.previousRoundResults, isEmpty);
      expect(boot.propositions, isEmpty);
      expect(boot.myPropositions, isEmpty);
      expect(boot.hasRated, isFalse);
      expect(boot.hasStartedRating, isFalse);
      expect(boot.skipCount, 0);
      expect(boot.hasSkipped, isFalse);
      expect(boot.affirmationCount, 0);
      expect(boot.hasAffirmed, isFalse);
      expect(boot.minRatingsPerProp, 0);
      expect(boot.myCurrentRoundRatingCount, 0);
      expect(boot.isMyParticipantFunded, isTrue);
      expect(boot.allowedCategories, isEmpty);
    });

    test('parses chat-only path (no participants, no cycle)', () {
      final json = _baseJson(chat: ChatFixtures.json(name: 'Solo'));
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.chat?.name, 'Solo');
    });

    test('parses cycle and round when present', () {
      final cycleJson = CycleFixtures.json(id: 7);
      final roundJson = RoundFixtures.json(id: 9, cycleId: 7);
      final json = _baseJson(
        chat: ChatFixtures.json(),
        currentCycle: cycleJson,
        currentRound: roundJson,
      );
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.currentCycle?.id, 7);
      expect(boot.currentRound?.id, 9);
    });

    test('parses participants with stable ordering', () {
      final p1 = ParticipantFixtures.json(id: 1, displayName: 'Alice');
      final p2 = ParticipantFixtures.json(id: 2, displayName: 'Bob');
      final json = _baseJson(
        chat: ChatFixtures.json(),
        participants: [p1, p2],
        myParticipant: p1,
      );
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.participants.map((p) => p.displayName).toList(),
          ['Alice', 'Bob']);
      expect(boot.myParticipant?.displayName, 'Alice');
    });

    test('parses rating_progress flags onto hasRated/hasStartedRating', () {
      final json = _baseJson(
        chat: ChatFixtures.json(),
        ratingProgress: {
          'rated': 4,
          'total': 4,
          'completed': true,
          'started': true,
        },
      );
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.hasRated, isTrue);
      expect(boot.hasStartedRating, isTrue);
    });

    test('parses skip / affirm counters and flags', () {
      final json = _baseJson(
        chat: ChatFixtures.json(),
        skipCount: 3,
        hasSkipped: true,
        ratingSkipCount: 1,
        hasSkippedRating: true,
        affirmationCount: 5,
        hasAffirmed: true,
        participantsWhoSkippedProposing: [1, 2, 3],
        participantsWhoSkippedRating: [4],
        participantsWhoAffirmed: [5, 6],
        participantsWhoRated: [1, 2],
      );
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.skipCount, 3);
      expect(boot.hasSkipped, isTrue);
      expect(boot.ratingSkipCount, 1);
      expect(boot.hasSkippedRating, isTrue);
      expect(boot.affirmationCount, 5);
      expect(boot.hasAffirmed, isTrue);
      expect(boot.participantsWhoSkippedProposing, {1, 2, 3});
      expect(boot.participantsWhoSkippedRating, {4});
      expect(boot.participantsWhoAffirmed, {5, 6});
      expect(boot.participantsWhoRated, {1, 2});
    });

    test('parses allowed_categories as List<String>', () {
      final json = _baseJson(
        chat: ChatFixtures.json(),
        allowedCategories: ['food', 'travel'],
      );
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.allowedCategories, ['food', 'travel']);
    });

    test('treats missing booleans as defaults', () {
      // Drop affirm/skip/funding flags entirely; defaults must apply.
      final json = <String, dynamic>{
        'chat': ChatFixtures.json(),
        'participants': const [],
        'consensus_items': const [],
        'pending_join_requests': const [],
        'previous_round_winners': const [],
        'previous_round_results': const [],
        'propositions': const [],
        'my_propositions': const [],
        'allowed_categories': const [],
      };
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.isSoleWinner, isFalse);
      expect(boot.hasSkipped, isFalse);
      expect(boot.hasSkippedRating, isFalse);
      expect(boot.hasAffirmed, isFalse);
      expect(boot.isMyParticipantFunded, isTrue);
      expect(boot.consecutiveSoleWins, 0);
      expect(boot.previousRoundId, isNull);
    });

    test('coerces numeric IDs from JSON num to int', () {
      final json = _baseJson(
        chat: ChatFixtures.json(),
        previousRoundId: 42,
        primaryWinnerId: 99,
        consecutiveSoleWins: 2,
        skipCount: 7,
      );
      final boot = ChatDetailBootstrap.fromJson(json);
      expect(boot.previousRoundId, 42);
      expect(boot.primaryWinnerId, 99);
      expect(boot.consecutiveSoleWins, 2);
      expect(boot.skipCount, 7);
    });
  });
}

Map<String, dynamic> _baseJson({
  required Map<String, dynamic> chat,
  Map<String, dynamic>? currentCycle,
  Map<String, dynamic>? currentRound,
  List<Map<String, dynamic>> participants = const [],
  Map<String, dynamic>? myParticipant,
  Map<String, dynamic>? ratingProgress,
  int skipCount = 0,
  bool hasSkipped = false,
  int ratingSkipCount = 0,
  bool hasSkippedRating = false,
  int affirmationCount = 0,
  bool hasAffirmed = false,
  List<int> participantsWhoRated = const [],
  List<int> participantsWhoSkippedProposing = const [],
  List<int> participantsWhoSkippedRating = const [],
  List<int> participantsWhoAffirmed = const [],
  int? previousRoundId,
  int? primaryWinnerId,
  int consecutiveSoleWins = 0,
  List<String> allowedCategories = const [],
}) {
  return {
    'chat': chat,
    'current_cycle': currentCycle,
    'current_round': currentRound,
    'consensus_items': const [],
    'participants': participants,
    'my_participant': myParticipant,
    'pending_join_requests': const [],
    'chat_credits': null,
    'previous_round_winners': const [],
    'is_sole_winner': false,
    'consecutive_sole_wins': consecutiveSoleWins,
    'previous_round_id': previousRoundId,
    'primary_winner_id': primaryWinnerId,
    'previous_round_results': const [],
    'propositions': const [],
    'my_propositions': const [],
    'rating_progress': ratingProgress ??
        {'rated': 0, 'total': 0, 'completed': false, 'started': false},
    'skip_count': skipCount,
    'has_skipped': hasSkipped,
    'rating_skip_count': ratingSkipCount,
    'has_skipped_rating': hasSkippedRating,
    'affirmation_count': affirmationCount,
    'has_affirmed': hasAffirmed,
    'participants_who_rated': participantsWhoRated,
    'participants_who_skipped_proposing': participantsWhoSkippedProposing,
    'participants_who_skipped_rating': participantsWhoSkippedRating,
    'participants_who_affirmed': participantsWhoAffirmed,
    'min_ratings_per_prop': 0,
    'my_current_round_rating_count': 0,
    'is_my_participant_funded': true,
    'allowed_categories': allowedCategories,
  };
}
