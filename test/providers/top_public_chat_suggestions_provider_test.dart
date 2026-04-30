import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/providers/notifiers/public_chats_notifier.dart';

import '../fixtures/chat_dashboard_info_fixtures.dart';

PublicChatSummary _summary({
  required int id,
  String name = 'Public',
  int participantCount = 1,
  String? currentRoundPhase,
  bool schedulePaused = false,
  bool hostPaused = false,
}) {
  return PublicChatSummary(
    id: id,
    name: name,
    initialMessage: 'Q',
    participantCount: participantCount,
    createdAt: DateTime(2026, 1, 1),
    currentRoundPhase: currentRoundPhase,
    schedulePaused: schedulePaused,
    hostPaused: hostPaused,
  );
}

/// Minimal notifier test-double so we can seed both providers without
/// reaching into Supabase. The provider under test is a plain `Provider`,
/// so the overrides only need to produce the `AsyncValue` it reads.
class _FakePublicChatsNotifier
    extends StateNotifier<AsyncValue<PublicChatsState>>
    implements PublicChatsNotifier {
  _FakePublicChatsNotifier(AsyncValue<PublicChatsState> initial)
      : super(initial);

  // Everything below is unused by the provider — throwing keeps tests honest
  // if they accidentally exercise real loading paths.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not used in this test');
}

class _FakeMyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    implements MyChatsNotifier {
  _FakeMyChatsNotifier(AsyncValue<MyChatsState> initial) : super(initial);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not used in this test');
}

ProviderContainer _container({
  required AsyncValue<PublicChatsState> publicState,
  required AsyncValue<MyChatsState> myChatsState,
}) {
  return ProviderContainer(
    overrides: [
      publicChatsProvider
          .overrideWith((ref) => _FakePublicChatsNotifier(publicState)),
      myChatsProvider
          .overrideWith((ref) => _FakeMyChatsNotifier(myChatsState)),
    ],
  );
}

void main() {
  group('topPublicChatSuggestionsProvider', () {
    test('returns empty list when both providers are loading', () {
      final container = _container(
        publicState: const AsyncLoading(),
        myChatsState: const AsyncLoading(),
      );
      addTearDown(container.dispose);

      expect(container.read(topPublicChatSuggestionsProvider), isEmpty);
    });

    test('sorts by participantCount DESC and caps at 3', () {
      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            _summary(id: 1, name: 'A', participantCount: 2),
            _summary(id: 2, name: 'B', participantCount: 10),
            _summary(id: 3, name: 'C', participantCount: 5),
            _summary(id: 4, name: 'D', participantCount: 7),
            _summary(id: 5, name: 'E', participantCount: 1),
          ],
        )),
        myChatsState: const AsyncData(MyChatsState(dashboardChats: [])),
      );
      addTearDown(container.dispose);

      final result = container.read(topPublicChatSuggestionsProvider);
      expect(result.map((s) => s.name).toList(), ['B', 'D', 'C']);
      expect(result, hasLength(3));
    });

    test('excludes chats the user has already joined', () {
      // Joined chats come from myChatsProvider.dashboardChats. The provider
      // matches by chat.id, so we need the joined id to line up with a
      // PublicChatSummary.id.
      final joined =
          ChatDashboardInfoFixtures.idle(id: 2, name: 'Joined Public');

      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            _summary(id: 1, name: 'A', participantCount: 3),
            _summary(id: 2, name: 'ShouldBeFiltered', participantCount: 99),
            _summary(id: 3, name: 'B', participantCount: 2),
          ],
        )),
        myChatsState: AsyncData(MyChatsState(dashboardChats: [joined])),
      );
      addTearDown(container.dispose);

      final result = container.read(topPublicChatSuggestionsProvider);
      expect(
        result.map((s) => s.name).toList(),
        ['A', 'B'],
        reason: 'joined chat #2 must be excluded even when it has '
            'the highest participant count',
      );
    });

    test('returns empty list when every public chat is joined', () {
      final joinedA = ChatDashboardInfoFixtures.idle(id: 1);
      final joinedB = ChatDashboardInfoFixtures.idle(id: 2);

      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            _summary(id: 1, participantCount: 10),
            _summary(id: 2, participantCount: 5),
          ],
        )),
        myChatsState: AsyncData(
          MyChatsState(dashboardChats: [joinedA, joinedB]),
        ),
      );
      addTearDown(container.dispose);

      expect(container.read(topPublicChatSuggestionsProvider), isEmpty);
    });

    test('returns available suggestions when fewer than 3 candidates exist',
        () {
      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            _summary(id: 1, name: 'Only', participantCount: 3),
          ],
        )),
        myChatsState: const AsyncData(MyChatsState(dashboardChats: [])),
      );
      addTearDown(container.dispose);

      final result = container.read(topPublicChatSuggestionsProvider);
      expect(result.map((s) => s.name).toList(), ['Only']);
    });

    test('active (proposing/rating) ranks above waiting/idle regardless of '
        'participant count', () {
      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            // Tier-1: idle / waiting — huge participant counts, must lose to
            // the tier-0 chats below.
            _summary(id: 1, name: 'IdleBig', participantCount: 50),
            _summary(
              id: 2,
              name: 'WaitingBig',
              participantCount: 40,
              currentRoundPhase: 'waiting',
            ),
            // Tier-0: active — lower counts, but should come first.
            _summary(
              id: 3,
              name: 'Proposing',
              participantCount: 4,
              currentRoundPhase: 'proposing',
            ),
            _summary(
              id: 4,
              name: 'Rating',
              participantCount: 6,
              currentRoundPhase: 'rating',
            ),
          ],
        )),
        myChatsState: const AsyncData(MyChatsState(dashboardChats: [])),
      );
      addTearDown(container.dispose);

      final result = container.read(topPublicChatSuggestionsProvider);
      expect(
        result.map((s) => s.name).toList(),
        ['Rating', 'Proposing', 'IdleBig'],
        reason: 'Active tier first (sorted DESC by participants), then the '
            'top waiting/idle chat fills the remaining slot.',
      );
    });

    test('waiting-phase chats appear when no active chats exist, sorted DESC '
        'by participant count', () {
      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            _summary(
              id: 1,
              name: 'WaitingSmall',
              participantCount: 1,
              currentRoundPhase: 'waiting',
            ),
            _summary(id: 2, name: 'Idle', participantCount: 2),
            _summary(
              id: 3,
              name: 'WaitingBig',
              participantCount: 5,
              currentRoundPhase: 'waiting',
            ),
          ],
        )),
        myChatsState: const AsyncData(MyChatsState(dashboardChats: [])),
      );
      addTearDown(container.dispose);

      final result = container.read(topPublicChatSuggestionsProvider);
      expect(
        result.map((s) => s.name).toList(),
        ['WaitingBig', 'Idle', 'WaitingSmall'],
      );
    });

    test('excludes paused chats (host- or schedule-paused)', () {
      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            _summary(
              id: 1,
              name: 'HostPaused',
              participantCount: 100,
              currentRoundPhase: 'proposing',
              hostPaused: true,
            ),
            _summary(
              id: 2,
              name: 'SchedulePaused',
              participantCount: 100,
              currentRoundPhase: 'rating',
              schedulePaused: true,
            ),
            _summary(
              id: 3,
              name: 'Running',
              participantCount: 3,
              currentRoundPhase: 'proposing',
            ),
          ],
        )),
        myChatsState: const AsyncData(MyChatsState(dashboardChats: [])),
      );
      addTearDown(container.dispose);

      final result = container.read(topPublicChatSuggestionsProvider);
      expect(result.map((s) => s.name).toList(), ['Running']);
    });

    test('ties by participantCount preserve original relative order', () {
      // List.sort is not stable on all platforms, but the expected behavior
      // for the home feeder is "fine as long as both end up in the top 3".
      final container = _container(
        publicState: AsyncData(PublicChatsState(
          chats: [
            _summary(id: 1, name: 'X', participantCount: 5),
            _summary(id: 2, name: 'Y', participantCount: 5),
            _summary(id: 3, name: 'Z', participantCount: 5),
            _summary(id: 4, name: 'W', participantCount: 1),
          ],
        )),
        myChatsState: const AsyncData(MyChatsState(dashboardChats: [])),
      );
      addTearDown(container.dispose);

      final names =
          container.read(topPublicChatSuggestionsProvider).map((s) => s.name);
      expect(names, containsAll(['X', 'Y', 'Z']));
      expect(names, isNot(contains('W')));
    });
  });
}
