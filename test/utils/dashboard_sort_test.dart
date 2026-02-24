import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/utils/dashboard_sort.dart';
import '../fixtures/chat_fixtures.dart';
import '../fixtures/chat_dashboard_info_fixtures.dart';

void main() {
  group('sortByUrgency', () {
    test('active + timed chats come first, sorted by soonest timer', () {
      final soonTimer = ChatDashboardInfoFixtures.proposingTimed(
        id: 1,
        name: 'Soon',
        timerRemaining: const Duration(minutes: 1),
      );
      final laterTimer = ChatDashboardInfoFixtures.ratingTimed(
        id: 2,
        name: 'Later',
        timerRemaining: const Duration(minutes: 10),
      );
      final idle = ChatDashboardInfoFixtures.idle(id: 3, name: 'Idle');

      final sorted = sortByUrgency([laterTimer, idle, soonTimer]);

      expect(sorted[0].chat.name, 'Soon');
      expect(sorted[1].chat.name, 'Later');
      expect(sorted[2].chat.name, 'Idle');
    });

    test('active + no timer comes after timed, before paused', () {
      final timed = ChatDashboardInfoFixtures.proposingTimed(
        id: 1,
        name: 'Timed',
      );
      final manual = ChatDashboardInfoFixtures.proposingManual(
        id: 2,
        name: 'Manual',
      );
      final paused = ChatDashboardInfoFixtures.paused(
        id: 3,
        name: 'Paused',
      );

      final sorted = sortByUrgency([paused, manual, timed]);

      expect(sorted[0].chat.name, 'Timed');
      expect(sorted[1].chat.name, 'Manual');
      expect(sorted[2].chat.name, 'Paused');
    });

    test('paused comes before idle', () {
      final paused = ChatDashboardInfoFixtures.paused(id: 1, name: 'Paused');
      final idle = ChatDashboardInfoFixtures.idle(id: 2, name: 'Idle');

      final sorted = sortByUrgency([idle, paused]);

      expect(sorted[0].chat.name, 'Paused');
      expect(sorted[1].chat.name, 'Idle');
    });

    test('idle chats sort by lastActivityAt DESC', () {
      final older = ChatDashboardInfo(
        chat: Chat.fromJson(ChatFixtures.json(
          id: 1,
          name: 'Older',
          lastActivityAt: DateTime(2024, 1, 1),
        )),
        participantCount: 2,
      );
      final newer = ChatDashboardInfo(
        chat: Chat.fromJson(ChatFixtures.json(
          id: 2,
          name: 'Newer',
          lastActivityAt: DateTime(2024, 6, 1),
        )),
        participantCount: 2,
      );

      final sorted = sortByUrgency([older, newer]);

      expect(sorted[0].chat.name, 'Newer');
      expect(sorted[1].chat.name, 'Older');
    });

    test('empty list returns empty', () {
      expect(sortByUrgency([]), isEmpty);
    });

    test('single item returns same list', () {
      final single = ChatDashboardInfoFixtures.idle(id: 1);
      final sorted = sortByUrgency([single]);
      expect(sorted.length, 1);
      expect(sorted[0], single);
    });

    test('full urgency ordering: timed > manual > paused > idle', () {
      final timed = ChatDashboardInfoFixtures.proposingTimed(id: 1, name: 'Timed');
      final manual = ChatDashboardInfoFixtures.proposingManual(id: 2, name: 'Manual');
      final paused = ChatDashboardInfoFixtures.paused(id: 3, name: 'Paused');
      final idle = ChatDashboardInfoFixtures.idle(id: 4, name: 'Idle');

      final sorted = sortByUrgency([idle, paused, timed, manual]);

      expect(sorted[0].chat.name, 'Timed');
      expect(sorted[1].chat.name, 'Manual');
      expect(sorted[2].chat.name, 'Paused');
      expect(sorted[3].chat.name, 'Idle');
    });
  });
}
