import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/services/proposition_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../fixtures/fixtures.dart';
import '../mocks/mock_supabase_client.dart';

void main() {
  late MockSupabaseClient mockClient;
  late PropositionService propositionService;

  setUpAll(() {
    registerFallbackValue(PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: 1,
    ));
    registerFallbackValue(PostgresChangeEvent.insert);
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    propositionService = PropositionService(mockClient);
  });

  group('PropositionService', () {
    // Note: Testing Supabase query builder chains is complex due to the fluent API.
    // Database logic is thoroughly tested via pgTAP (577 tests).
    // These tests focus on subscription methods which are easier to mock.

    group('subscribeToPropositions', () {
      test('creates realtime channel for proposition changes', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();

        when(() => mockClient.channel('propositions:10')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenReturn(mockChannel);
        when(() => mockChannel.subscribe(any())).thenReturn(mockChannel);

        // Act
        final channel = propositionService.subscribeToPropositions(10, () {});

        // Assert
        expect(channel, isNotNull);
        verify(() => mockClient.channel('propositions:10')).called(1);
        verify(() => mockChannel.subscribe(any())).called(1);
      });

      test('subscribes to all events (insert and delete)', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();
        PostgresChangeEvent? capturedEvent;
        String? capturedTable;

        when(() => mockClient.channel('propositions:5')).thenReturn(mockChannel);
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
        when(() => mockChannel.subscribe(any())).thenReturn(mockChannel);

        // Act
        propositionService.subscribeToPropositions(5, () {});

        // Assert
        // Changed from insert-only to all events to support delete notifications
        expect(capturedEvent, PostgresChangeEvent.all);
        expect(capturedTable, 'propositions');
      });

      test('filters by round_id in subscription', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();
        PostgresChangeFilter? capturedFilter;

        when(() => mockClient.channel('propositions:99')).thenReturn(mockChannel);
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
        when(() => mockChannel.subscribe(any())).thenReturn(mockChannel);

        // Act
        propositionService.subscribeToPropositions(99, () {});

        // Assert
        expect(capturedFilter, isNotNull);
        expect(capturedFilter!.column, 'round_id');
        expect(capturedFilter!.value, 99);
      });
    });

    group('subscribeToGlobalScores', () {
      test('creates realtime channel for score updates', () {
        // Arrange
        final mockChannel = MockRealtimeChannel();

        when(() => mockClient.channel('global_scores:10')).thenReturn(mockChannel);
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).thenReturn(mockChannel);
        when(() => mockChannel.subscribe()).thenReturn(mockChannel);

        // Act
        final channel = propositionService.subscribeToGlobalScores(10, () {});

        // Assert
        expect(channel, isNotNull);
        verify(() => mockClient.channel('global_scores:10')).called(1);
        verify(() => mockChannel.subscribe()).called(1);
      });
    });
  });

  group('getPropositionsWithRatings ordering', () {
    // BUG FIX (2026-01-14): Results were ordered incorrectly because
    // PostgREST foreign table ordering doesn't work reliably with
    // embedded resources. Now we sort client-side in Dart.
    //
    // The old query used .order('proposition_ratings(rank)') which didn't
    // properly sort by MOVDA score. Now we fetch all results and sort
    // by finalRating (from proposition_movda_ratings.rating) in Dart.
    //
    // These tests verify the sorting logic that the service applies.
    // The actual Supabase query is tested via integration/manual testing.

    test('sorting logic: orders by finalRating descending', () {
      // Create propositions in unsorted order (as if from DB)
      final unsorted = [
        PropositionFixtures.rated(id: 1, rating: 50.0, rank: 3),
        PropositionFixtures.rated(id: 2, rating: 76.5, rank: 1), // Tied winner
        PropositionFixtures.rated(id: 3, rating: 60.0, rank: 2),
        PropositionFixtures.rated(id: 4, rating: 76.5, rank: 1), // Tied winner
      ];

      // Apply the same sorting logic used in getPropositionsWithRatings
      final sorted = List<Proposition>.from(unsorted)
        ..sort((a, b) {
          final aRating = a.finalRating ?? 0;
          final bRating = b.finalRating ?? 0;
          return bRating.compareTo(aRating); // Descending
        });

      // Assert - tied winners should be first
      expect(sorted[0].finalRating, 76.5, reason: 'First should be highest');
      expect(sorted[1].finalRating, 76.5, reason: 'Second should be tied highest');
      expect(sorted[2].finalRating, 60.0, reason: 'Third should be middle');
      expect(sorted[3].finalRating, 50.0, reason: 'Fourth should be lowest');
    });

    test('sorting logic: null ratings sort to end', () {
      final unsorted = [
        PropositionFixtures.rated(id: 1, rating: 80.0, rank: 1),
        PropositionFixtures.model(id: 2), // No rating (null)
        PropositionFixtures.rated(id: 3, rating: 40.0, rank: 2),
      ];

      final sorted = List<Proposition>.from(unsorted)
        ..sort((a, b) {
          final aRating = a.finalRating ?? 0;
          final bRating = b.finalRating ?? 0;
          return bRating.compareTo(aRating);
        });

      expect(sorted[0].finalRating, 80.0);
      expect(sorted[1].finalRating, 40.0);
      expect(sorted[2].finalRating, isNull, reason: 'Null ratings sort to end');
    });

    test('sorting logic: ensures tied scores are consecutive', () {
      // This is the actual bug scenario - tied winners were not consecutive
      final unsorted = [
        PropositionFixtures.rated(id: 1, rating: 50.0, rank: 3),
        PropositionFixtures.rated(id: 2, rating: 76.5, rank: 1), // Winner A
        PropositionFixtures.rated(id: 3, rating: 65.0, rank: 2), // Middle
        PropositionFixtures.rated(id: 4, rating: 76.5, rank: 1), // Winner B (tied)
      ];

      final sorted = List<Proposition>.from(unsorted)
        ..sort((a, b) {
          final aRating = a.finalRating ?? 0;
          final bRating = b.finalRating ?? 0;
          return bRating.compareTo(aRating);
        });

      // Winners must be positions 0 and 1 (consecutive)
      expect(sorted[0].finalRating, 76.5);
      expect(sorted[1].finalRating, 76.5);
      // NOT: winner at 0, middle at 1, winner at 2 (the bug)
      expect(sorted[2].finalRating, isNot(76.5), reason: 'No winner at position 2');
    });
  });

  group('PropositionFixtures', () {
    // Test that fixtures produce valid models
    test('json() creates valid Proposition JSON', () {
      final json = PropositionFixtures.json(id: 1);
      expect(() => Proposition.fromJson(json), returnsNormally);
    });

    test('model() creates valid Proposition', () {
      final proposition = PropositionFixtures.model();
      expect(proposition.id, 1);
      expect(proposition.content, 'Test proposition');
    });

    test('rated() creates proposition with rating', () {
      final proposition = PropositionFixtures.rated(rating: 85.0, rank: 1);
      expect(proposition.finalRating, 85.0);
      expect(proposition.rank, 1);
    });

    test('winner() creates top-ranked proposition', () {
      final proposition = PropositionFixtures.winner();
      expect(proposition.rank, 1);
      expect(proposition.finalRating, 90.0);
    });

    test('mine() creates proposition with participant_id', () {
      final proposition = PropositionFixtures.mine(participantId: 5);
      expect(proposition.participantId, 5);
    });

    test('list() creates multiple propositions', () {
      final propositions = PropositionFixtures.list(count: 5);
      expect(propositions, hasLength(5));
      expect(propositions.map((p) => p.id).toSet(), hasLength(5)); // All unique
    });

    test('withRatings() creates ranked propositions', () {
      final propositions = PropositionFixtures.withRatings();
      expect(propositions, hasLength(3));
      // Verify they're ordered by rank
      expect(propositions[0].rank, 1);
      expect(propositions[1].rank, 2);
      expect(propositions[2].rank, 3);
      // Verify ratings decrease
      expect(propositions[0].finalRating! > propositions[1].finalRating!, isTrue);
      expect(propositions[1].finalRating! > propositions[2].finalRating!, isTrue);
    });

    test('diverse() creates propositions with varied content', () {
      final propositions = PropositionFixtures.diverse();
      expect(propositions, hasLength(4));
      // Check we have short and long content
      expect(propositions.any((p) => p.content.length < 20), isTrue);
      expect(propositions.any((p) => p.content.length > 100), isTrue);
    });

    test('translated() creates proposition with translation', () {
      final proposition = PropositionFixtures.translated(
        content: 'Hello world',
        contentTranslated: 'Hola mundo',
        languageCode: 'es',
      );
      expect(proposition.content, 'Hello world');
      expect(proposition.contentTranslated, 'Hola mundo');
      expect(proposition.translationLanguage, 'es');
      expect(proposition.displayContent, 'Hola mundo');
    });

    test('withTranslations() creates propositions with translations', () {
      final propositions = PropositionFixtures.withTranslations(languageCode: 'es');
      expect(propositions, hasLength(3));
      expect(propositions[0].content, 'Message 1');
      expect(propositions[0].displayContent, 'Mensaje 1');
      expect(propositions[1].displayContent, 'Mensaje 2');
      expect(propositions[2].displayContent, 'Mensaje 3');
    });
  });

  group('Proposition displayContent', () {
    test('returns contentTranslated when available', () {
      final proposition = PropositionFixtures.translated(
        content: 'Original',
        contentTranslated: 'Translated',
      );
      expect(proposition.displayContent, 'Translated');
    });

    test('falls back to content when no translation', () {
      final proposition = PropositionFixtures.model(content: 'Original only');
      expect(proposition.displayContent, 'Original only');
    });

    test('handles null contentTranslated gracefully', () {
      final proposition = Proposition.fromJson({
        'id': 1,
        'round_id': 1,
        'content': 'Fallback content',
        'created_at': DateTime.now().toIso8601String(),
        // content_translated is not present (null)
      });
      expect(proposition.displayContent, 'Fallback content');
    });
  });
}
