import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/providers/notifiers/rating_notifier.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/rating/rating_screen.dart';
import 'package:onemind_app/services/proposition_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../fixtures/proposition_fixtures.dart';
import '../../mocks/mock_services.dart';

class _FakeLocaleNotifier extends StateNotifier<Locale>
    implements LocaleNotifier {
  _FakeLocaleNotifier({String code = 'en'}) : super(Locale(code));

  @override
  String get currentLanguageCode => state.languageCode;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setLocale(String languageCode) async {
    state = Locale(languageCode);
  }

  @override
  // ignore: invalid_use_of_protected_member
  LanguageService get _languageService => throw UnimplementedError();
}

/// Verifies the per-user rating cap (kMaxRatingsPerUser) is enforced as a
/// hard UI cap: once the user has placed `cap` ratings, the notifier reports
/// isComplete=true and refuses to fetch more, even when the round contains
/// further unrated propositions.
void main() {
  late MockPropositionService propositionService;
  ProviderContainer? container;

  const roundId = 42;
  const participantId = 7;
  final cap = PropositionService.kMaxRatingsPerUser;

  setUp(() {
    propositionService = MockPropositionService();
    container = null;
  });

  tearDown(() {
    container?.dispose();
  });

  ProviderContainer makeContainer({String languageCode = 'en'}) {
    return ProviderContainer(overrides: [
      propositionServiceProvider.overrideWithValue(propositionService),
      localeProvider
          .overrideWith((ref) => _FakeLocaleNotifier(code: languageCode)),
    ]);
  }

  Future<RatingState> waitForData(ProviderContainer c, GridRankingParams p) async {
    final completer = Completer<RatingState>();
    final sub = c.listen<AsyncValue<RatingState>>(
      ratingProvider(p),
      (prev, next) {
        if (!next.isLoading && !completer.isCompleted) {
          if (next.hasValue) completer.complete(next.value!);
          if (next.hasError) completer.completeError(next.error!);
        }
      },
      fireImmediately: true,
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } finally {
      sub.close();
    }
  }

  group('rating cap', () {
    test('exposes a cap of 7 (matches DB trigger constant)', () {
      expect(cap, 7);
    });

    test('totalKnown clamps to cap when chat has more than cap propositions',
        () async {
      // Mock: chat has 50 props, user authored 1 → 49 rateable. Cap should
      // make UI display 7 / 7, not 49 / 49.
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 47); // 49 rateable - 2 already fetched

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);

      final state = await waitForData(container!, params);

      expect(state.totalKnown, cap,
          reason: 'totalKnown must be clamped to the cap');
      expect(state.fetchedIds.length, 2);
      expect(state.isComplete, false,
          reason: 'not yet at cap, can still fetch more');
    });

    test('fetchNextProposition returns null and marks complete at cap',
        () async {
      // Build initial state with 2 props, mock 5 more arriving via fetchNext.
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 100);

      // Each call to getNextPropositionForGridRanking returns a fresh prop
      // — the service has no idea about the cap and would keep going.
      var nextId = 3;
      when(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => PropositionFixtures.model(id: nextId++));

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      await waitForData(container!, params);

      final notifier = container!.read(ratingProvider(params).notifier);

      // Fetch up to the cap: started with 2, fetch 5 more → exactly 7.
      for (var i = 0; i < cap - 2; i++) {
        final next = await notifier.fetchNextProposition();
        expect(next, isNotNull,
            reason: 'fetch $i must succeed (still under cap)');
      }

      final atCap = container!.read(ratingProvider(params)).value!;
      expect(atCap.fetchedIds.length, cap);

      // Next fetch must return null and flip isComplete — even though the
      // service still has propositions queued.
      final overflow = await notifier.fetchNextProposition();
      expect(overflow, isNull,
          reason: 'cap is hard — fetchNext returns null at the threshold');

      final finalState = container!.read(ratingProvider(params)).value!;
      expect(finalState.isComplete, true,
          reason: 'crossing the cap marks the round complete for this user');
      expect(finalState.fetchedIds.length, cap,
          reason: 'no extra prop was fetched past the cap');

      // The service should NOT have been called for an 8th prop.
      verify(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).called(cap - 2); // exactly 5 successful fetches, no 6th
    });

    test('resume at or above cap is immediately complete', () async {
      // User left mid-rating after placing exactly cap (7) ratings, then
      // rejoined. Saved state should boot straight to isComplete=true so
      // the auto-submit path fires without additional grid interaction.
      final saved = List.generate(
        cap,
        (i) => {'id': 100 + i, 'content': 'saved $i', 'position': 50.0 + i},
      );
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => saved);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 30); // many more remain server-side

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);

      final state = await waitForData(container!, params);

      expect(state.isComplete, true,
          reason: 'rejoiner with cap saved ratings is already done');
      expect(state.totalKnown, cap,
          reason: 'totalKnown does not exceed cap on resume');
      expect(state.currentPlacing, cap);
    });

    test('chat with exactly cap rateable props — no clamp surprise', () async {
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 5); // 2 + 5 = 7 = cap exactly

      var nextId = 3;
      when(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => PropositionFixtures.model(id: nextId++));

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      final initial = await waitForData(container!, params);
      expect(initial.totalKnown, cap);

      final notifier = container!.read(ratingProvider(params).notifier);
      for (var i = 0; i < cap - 2; i++) {
        expect(await notifier.fetchNextProposition(), isNotNull,
            reason: 'fetch $i must land — still under cap');
      }
      final blocked = await notifier.fetchNextProposition();
      expect(blocked, isNull);
      final state = container!.read(ratingProvider(params)).value!;
      expect(state.fetchedIds.length, cap);
      expect(state.isComplete, true);
    });

    test('chat with cap + 1 rateable props — the extra prop is never fetched',
        () async {
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 6); // 8 total - 2 fetched

      var nextId = 3;
      when(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => PropositionFixtures.model(id: nextId++));

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      await waitForData(container!, params);
      final notifier = container!.read(ratingProvider(params).notifier);

      for (var i = 0; i < cap - 2; i++) {
        await notifier.fetchNextProposition();
      }
      await notifier.fetchNextProposition(); // would-be 8th — must short-circuit

      verify(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).called(cap - 2);
    });

    test('resume just below cap — fetches one more then completes', () async {
      final saved = List.generate(
        cap - 1,
        (i) => {'id': 100 + i, 'content': 'saved $i', 'position': 50.0 + i},
      );
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => saved);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 5);
      when(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => PropositionFixtures.model(id: 999));

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      final initial = await waitForData(container!, params);

      expect(initial.isComplete, false,
          reason: 'one slot remaining under the cap');
      expect(initial.totalKnown, cap);

      final notifier = container!.read(ratingProvider(params).notifier);
      expect(await notifier.fetchNextProposition(), isNotNull);
      expect(await notifier.fetchNextProposition(), isNull);

      final after = container!.read(ratingProvider(params)).value!;
      expect(after.fetchedIds.length, cap);
      expect(after.isComplete, true);
    });

    test('resume above cap (cap was lowered between sessions)', () async {
      // Edge: 10 ratings saved from before the cap was lowered to 7.
      // Don't truncate visible cards; just block future fetches.
      final saved = List.generate(
        cap + 3,
        (i) => {'id': 200 + i, 'content': 'old $i', 'position': 30.0 + i},
      );
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => saved);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 0);

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      final state = await waitForData(container!, params);

      expect(state.isComplete, true);
      expect(state.fetchedIds.length, cap + 3,
          reason:
              'all saved cards stay visible — cap blocks fetches, not history');
      expect(state.currentPlacing, cap + 3);

      final notifier = container!.read(ratingProvider(params).notifier);
      expect(await notifier.fetchNextProposition(), isNull);
      verifyNever(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          ));
    });

    test('user authored own props — own-prop exclusion + cap interact',
        () async {
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      // Service excludes own props from this count (by participant_id);
      // 10 rateable - 2 fetched = 8.
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 8);

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      final state = await waitForData(container!, params);

      expect(state.totalKnown, cap,
          reason: '10 rateable, but cap clamps display to 7');
    });

    test('concurrent fetchNext calls — second rejected by isFetchingNext',
        () async {
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 5);
      when(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return PropositionFixtures.model(id: 99);
      });

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      await waitForData(container!, params);

      final notifier = container!.read(ratingProvider(params).notifier);
      final futures = await Future.wait([
        notifier.fetchNextProposition(),
        notifier.fetchNextProposition(),
      ]);
      final got = futures.where((f) => f != null).length;
      expect(got, 1,
          reason: 'isFetchingNext guard collapses parallel calls to one');
      verify(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).called(1);
    });

    test('small chat (props < cap) — cap does not bind', () async {
      // Chat with only 4 props → user rates ≤3 (excluding own). Cap=7
      // shouldn't change behaviour: totalKnown matches actual rateable count.
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 1); // 1 more remaining

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);

      final state = await waitForData(container!, params);

      expect(state.totalKnown, 3,
          reason: '2 fetched + 1 remaining = 3, well under cap');
      expect(state.isComplete, false);
    });

    test('threads languageCode through to all service calls', () async {
      // Verify the cap layer doesn't drop or rewrite the language code.
      // Service should see 'es' on every call when locale='es'.
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 5);
      when(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => PropositionFixtures.model(id: 99));

      container = makeContainer(languageCode: 'es');
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      await waitForData(container!, params);

      final notifier = container!.read(ratingProvider(params).notifier);
      await notifier.fetchNextProposition();

      // Existing rankings + initial load + every fetchNext: all must
      // request 'es', not the default 'en'.
      verify(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: 'es',
          )).called(1);
      verify(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: 'es',
          )).called(1);
      verify(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: 'es',
          )).called(1);
    });

    test('service throws mid-fetch — notifier marks complete and returns null',
        () async {
      // Existing fetchNextProposition catches exceptions and flips
      // isComplete=true. Verify the cap layer doesn't break that — a thrown
      // service call must not leave the user stuck mid-rating.
      when(() => propositionService.getExistingGridRankings(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => []);
      when(() => propositionService.getInitialPropositionsForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            languageCode: any(named: 'languageCode'),
          )).thenAnswer((_) async => [
            PropositionFixtures.model(id: 1),
            PropositionFixtures.model(id: 2),
          ]);
      when(() => propositionService.getRemainingPropositionCount(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
          )).thenAnswer((_) async => 5);
      when(() => propositionService.getNextPropositionForGridRanking(
            roundId: any(named: 'roundId'),
            participantId: any(named: 'participantId'),
            excludeIds: any(named: 'excludeIds'),
            languageCode: any(named: 'languageCode'),
          )).thenThrow(Exception('network error'));

      container = makeContainer();
      const params = GridRankingParams(
          roundId: roundId, participantId: participantId);
      await waitForData(container!, params);

      final notifier = container!.read(ratingProvider(params).notifier);
      final result = await notifier.fetchNextProposition();

      expect(result, isNull,
          reason: 'thrown service call returns null, not propagated');
      final state = container!.read(ratingProvider(params)).value!;
      expect(state.isComplete, true,
          reason: 'after error, round is treated as complete from this user');
      expect(state.isFetchingNext, false,
          reason: 'in-flight flag must be cleared even on error');
    });
  });
}
