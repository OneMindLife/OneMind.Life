import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/utils/dashboard_sort.dart';
import '../fixtures/chat_fixtures.dart';
import '../fixtures/chat_dashboard_info_fixtures.dart';

void main() {
  group('sortByUrgency', () {
    test('not participated + timed comes before participated + timed', () {
      final notParticipated = ChatDashboardInfoFixtures.proposingTimed(
        id: 1,
        name: 'NeedAttention',
        hasParticipated: false,
        timerRemaining: const Duration(minutes: 5),
      );
      final participated = ChatDashboardInfoFixtures.proposingTimed(
        id: 2,
        name: 'Done',
        hasParticipated: true,
        timerRemaining: const Duration(minutes: 1),
      );

      final sorted = sortByUrgency([participated, notParticipated]);

      expect(sorted[0].chat.name, 'NeedAttention');
      expect(sorted[1].chat.name, 'Done');
    });

    test('not participated chats sorted by soonest timer', () {
      final soon = ChatDashboardInfoFixtures.proposingTimed(
        id: 1,
        name: 'Soon',
        hasParticipated: false,
        timerRemaining: const Duration(minutes: 1),
      );
      final later = ChatDashboardInfoFixtures.ratingTimed(
        id: 2,
        name: 'Later',
        hasParticipated: false,
        timerRemaining: const Duration(minutes: 10),
      );

      final sorted = sortByUrgency([later, soon]);

      expect(sorted[0].chat.name, 'Soon');
      expect(sorted[1].chat.name, 'Later');
    });

    test('participated + timed sorted by soonest timer', () {
      final soon = ChatDashboardInfoFixtures.proposingTimed(
        id: 1,
        name: 'Soon',
        timerRemaining: const Duration(minutes: 1),
      );
      final later = ChatDashboardInfoFixtures.ratingTimed(
        id: 2,
        name: 'Later',
        timerRemaining: const Duration(minutes: 10),
      );

      final sorted = sortByUrgency([later, soon]);

      expect(sorted[0].chat.name, 'Soon');
      expect(sorted[1].chat.name, 'Later');
    });

    test('not participated + manual comes before participated + manual', () {
      final notParticipated = ChatDashboardInfoFixtures.proposingManual(
        id: 1,
        name: 'NeedAttention',
        hasParticipated: false,
      );
      final participated = ChatDashboardInfoFixtures.proposingManual(
        id: 2,
        name: 'Done',
        hasParticipated: true,
      );

      final sorted = sortByUrgency([participated, notParticipated]);

      expect(sorted[0].chat.name, 'NeedAttention');
      expect(sorted[1].chat.name, 'Done');
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

    test('full urgency ordering: all 6 groups', () {
      final notParticipatedTimed = ChatDashboardInfoFixtures.proposingTimed(
        id: 1, name: 'NotParticipated+Timed', hasParticipated: false,
      );
      final notParticipatedManual = ChatDashboardInfoFixtures.proposingManual(
        id: 2, name: 'NotParticipated+Manual', hasParticipated: false,
      );
      final participatedTimed = ChatDashboardInfoFixtures.proposingTimed(
        id: 3, name: 'Participated+Timed',
      );
      final participatedManual = ChatDashboardInfoFixtures.proposingManual(
        id: 4, name: 'Participated+Manual',
      );
      final paused = ChatDashboardInfoFixtures.paused(id: 5, name: 'Paused');
      final idle = ChatDashboardInfoFixtures.idle(id: 6, name: 'Idle');

      final sorted = sortByUrgency([
        idle, paused, participatedTimed, notParticipatedManual,
        participatedManual, notParticipatedTimed,
      ]);

      expect(sorted[0].chat.name, 'NotParticipated+Timed');
      expect(sorted[1].chat.name, 'NotParticipated+Manual');
      expect(sorted[2].chat.name, 'Participated+Timed');
      expect(sorted[3].chat.name, 'Participated+Manual');
      expect(sorted[4].chat.name, 'Paused');
      expect(sorted[5].chat.name, 'Idle');
    });

    test('hasParticipated defaults to true for idle chats', () {
      final idle = ChatDashboardInfoFixtures.idle(id: 1, name: 'Idle');
      expect(idle.hasParticipated, true);
    });

    test('ChatDashboardInfo.fromJson parses has_participated', () {
      final json = ChatDashboardInfoFixtures.json(
        hasParticipated: false,
        currentRoundPhase: 'proposing',
      );
      final info = ChatDashboardInfo.fromJson(json);
      expect(info.hasParticipated, false);
    });

    test('ChatDashboardInfo.fromJson defaults has_participated to true', () {
      final json = ChatDashboardInfoFixtures.json();
      json.remove('has_participated');
      final info = ChatDashboardInfo.fromJson(json);
      expect(info.hasParticipated, true);
    });
  });

  group('partitionByAttention', () {
    test('proposing + not participated -> nextUp', () {
      final chat = ChatDashboardInfoFixtures.proposingTimed(
        id: 1,
        name: 'Needs prop',
        hasParticipated: false,
      );
      final p = partitionByAttention([chat]);
      expect(p.nextUp.map((c) => c.chat.name), ['Needs prop']);
      expect(p.wrappingUp, isEmpty);
      expect(p.inactive, isEmpty);
    });

    test('rating + not participated -> nextUp', () {
      final chat = ChatDashboardInfoFixtures.ratingTimed(
        id: 2,
        name: 'Needs rating',
        hasParticipated: false,
      );
      final p = partitionByAttention([chat]);
      expect(p.nextUp.map((c) => c.chat.name), ['Needs rating']);
      expect(p.wrappingUp, isEmpty);
      expect(p.inactive, isEmpty);
    });

    test('proposing + participated -> wrappingUp', () {
      final chat = ChatDashboardInfoFixtures.proposingTimed(
        id: 3,
        name: 'Submitted',
        hasParticipated: true,
      );
      final p = partitionByAttention([chat]);
      expect(p.nextUp, isEmpty);
      expect(p.wrappingUp.map((c) => c.chat.name), ['Submitted']);
      expect(p.inactive, isEmpty);
    });

    test('rating + participated -> wrappingUp', () {
      final chat = ChatDashboardInfoFixtures.ratingTimed(
        id: 4,
        name: 'Rated',
        hasParticipated: true,
      );
      final p = partitionByAttention([chat]);
      expect(p.wrappingUp.map((c) => c.chat.name), ['Rated']);
    });

    test('paused -> inactive (regardless of participation)', () {
      final unparticipatedPaused =
          ChatDashboardInfoFixtures.paused(id: 5, name: 'Paused-unparticipated',
                                           hasParticipated: false);
      final participatedPaused =
          ChatDashboardInfoFixtures.paused(id: 6, name: 'Paused-done',
                                           hasParticipated: true);
      final p = partitionByAttention(
          [unparticipatedPaused, participatedPaused]);
      expect(p.nextUp, isEmpty);
      expect(p.wrappingUp, isEmpty);
      expect(p.inactive.map((c) => c.chat.name),
          containsAll(['Paused-unparticipated', 'Paused-done']));
    });

    test('no active round -> inactive', () {
      final chat = ChatDashboardInfoFixtures.idle(id: 7, name: 'No round');
      final p = partitionByAttention([chat]);
      expect(p.inactive.map((c) => c.chat.name), ['No round']);
    });

    test('waiting phase -> inactive (round not yet open for action)', () {
      final chat = ChatDashboardInfoFixtures.waiting(id: 8, name: 'Pending');
      final p = partitionByAttention([chat]);
      expect(p.nextUp, isEmpty);
      expect(p.wrappingUp, isEmpty);
      expect(p.inactive.map((c) => c.chat.name), ['Pending']);
    });

    test('preserves input order within each bucket', () {
      final a = ChatDashboardInfoFixtures.proposingTimed(
          id: 10, name: 'A', hasParticipated: false);
      final b = ChatDashboardInfoFixtures.ratingTimed(
          id: 11, name: 'B', hasParticipated: false);
      final c = ChatDashboardInfoFixtures.proposingTimed(
          id: 12, name: 'C', hasParticipated: true);
      final d = ChatDashboardInfoFixtures.idle(id: 13, name: 'D');
      final e = ChatDashboardInfoFixtures.paused(id: 14, name: 'E');

      final p = partitionByAttention([a, b, c, d, e]);
      expect(p.nextUp.map((c) => c.chat.name), ['A', 'B']);
      expect(p.wrappingUp.map((c) => c.chat.name), ['C']);
      expect(p.inactive.map((c) => c.chat.name), ['D', 'E']);
    });

    test('empty input produces three empty buckets', () {
      final p = partitionByAttention([]);
      expect(p.nextUp, isEmpty);
      expect(p.wrappingUp, isEmpty);
      expect(p.inactive, isEmpty);
    });

    test('paused + rating + not participated still goes to inactive '
         '(pause dominates)', () {
      // This is the subtle case where a user would otherwise need to act,
      // but the host has paused — don't pull it into Next up.
      final chat = ChatDashboardInfoFixtures.paused(
          id: 15, name: 'Paused-rating', hasParticipated: false);
      final p = partitionByAttention([chat]);
      expect(p.nextUp, isEmpty);
      expect(p.inactive.map((c) => c.chat.name), ['Paused-rating']);
    });
  });
}
