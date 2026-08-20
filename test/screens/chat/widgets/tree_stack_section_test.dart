import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/screens/chat/widgets/tree_stack_section.dart';
import 'package:onemind_app/widgets/message_card.dart';

import '../../../fixtures/fixtures.dart';
import '../../../helpers/helpers.dart';
import '../../../mocks/mock_services.dart';

/// The glint border animation repeats forever, so pumpAndSettle would time
/// out — settle async fetches with a few fixed pumps instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// C15 TreeStackSection — the walkable inline stack (docs/ONEMIND_CONCEPT.md
/// C15). DEFAULT: entering the chat auto-selects every #1/winner down the
/// spine, landing the user at the leaf; tapping any committed block re-opens
/// that level's ranked options. Proposing is blind at live nodes.
void main() {
  late MockChatService chatService;
  late MockPropositionService propositionService;

  setUp(() {
    chatService = MockChatService();
    propositionService = MockPropositionService();
  });

  /// Ranked rows as get_propositions_with_scores returns them.
  List<Map<String, dynamic>> scored(List<(int, String)> rows) => [
        for (final (id, content) in rows)
          {'proposition_id': id, 'content': content},
      ];

  Map<String, dynamic> bootstrap({
    required int parentId,
    String windowPhase = 'proposing',
    Map<String, dynamic>? node,
  }) =>
      {
        'parent': {'id': parentId, 'content': 'parent $parentId'},
        'chat_id': 1,
        'branching_enabled': true,
        'window_phase': windowPhase,
        'node': node,
      };

  Map<String, dynamic> nodePayload({
    required int roundId,
    required String phase,
    String? completedAt,
    int? winnerId,
    List<Map<String, dynamic>> props = const [],
  }) =>
      {
        'cycle_id': roundId,
        'round': {
          'id': roundId,
          'phase': phase,
          'phase_started_at': '2026-07-12T00:00:00Z',
          'phase_ends_at': '2026-07-12T12:00:00Z',
          'completed_at': completedAt,
          'winning_proposition_id': winnerId,
        },
        'propositions': props,
        'winner': null,
      };

  Widget section({List<TreePosition>? positions, Widget? liveRootPanel}) =>
      Scaffold(
        body: SingleChildScrollView(
          child: TreeStackSection(
            chatId: 1,
            myParticipantId: 77,
            positions:
                positions ?? const [TreePosition(roundId: 100, winnerId: 11)],
            liveRootPanel: liveRootPanel,
          ),
        ),
      );

  /// Common single-position setup: round 100 (winner 11 'p1 winner',
  /// runner-up 12 'p1 alt'); winner's subtree unmaterialized.
  void stubP1() {
    when(() => propositionService.getPropositionsWithScores(100))
        .thenAnswer((_) async => scored([(11, 'p1 winner'), (12, 'p1 alt')]));
    when(() => chatService.getNodeBootstrap(11))
        .thenAnswer((_) async => bootstrap(parentId: 11));
  }

  group('fresh branching chat (root-live mode)', () {
    testWidgets('proposing: feed + composer for the live ROOT round',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(900))
          .thenAnswer((_) async => []);
      when(() => propositionService.getPropositions(900)).thenAnswer(
          (_) async => [PropositionFixtures.model(id: 71, content: 'root take')]);

      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: TreeStackSection(
              chatId: 1,
              myParticipantId: 77,
              positions: const [],
              liveRootRoundId: 900,
              liveRootPhase: 'proposing',
            ),
          ),
        ),
        chatService: chatService,
        propositionService: propositionService,
      );
      await settle(tester);

      expect(find.text('PROPOSITIONS SO FAR'), findsOneWidget);
      expect(find.text('root take'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // Label on top, feed under it, composer — the user's action — at the
      // BOTTOM.
      final composerY = tester.getTopLeft(find.byType(TextField)).dy;
      final labelY = tester.getTopLeft(find.text('PROPOSITIONS SO FAR')).dy;
      final takeY = tester.getTopLeft(find.text('root take')).dy;
      expect(labelY, lessThan(takeY));
      expect(takeY, lessThan(composerY));
      // No focus border — the pill container is the only outline (the theme
      // focusedBorder painted a blue ring before it was overridden).
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.decoration?.focusedBorder, InputBorder.none);
      expect(tf.decoration?.enabledBorder, InputBorder.none);
    });

    testWidgets('proposing feed: latest take at the BOTTOM, next to the composer',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(900))
          .thenAnswer((_) async => []);
      when(() => propositionService.getPropositions(900)).thenAnswer(
          (_) async => [
                PropositionFixtures.model(id: 71, content: 'older take'),
                PropositionFixtures.model(id: 72, content: 'newest take'),
              ]);

      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: TreeStackSection(
              chatId: 1,
              myParticipantId: 77,
              positions: const [],
              liveRootRoundId: 900,
              liveRootPhase: 'proposing',
            ),
          ),
        ),
        chatService: chatService,
        propositionService: propositionService,
      );
      await settle(tester);

      final newestY = tester.getTopLeft(find.text('newest take')).dy;
      final olderY = tester.getTopLeft(find.text('older take')).dy;
      final composerY = tester.getTopLeft(find.byType(TextField)).dy;
      expect(olderY, lessThan(newestY),
          reason: 'latest submission at the bottom');
      expect(newestY, lessThan(composerY),
          reason: 'newest take sits adjacent to the composer');
    });

    testWidgets('typing filters the feed to SIMILAR PROPOSITIONS',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(900))
          .thenAnswer((_) async => []);
      when(() => propositionService.getPropositions(900)).thenAnswer(
          (_) async => [
                PropositionFixtures.model(id: 71, content: 'pizza for dinner'),
                PropositionFixtures.model(id: 72, content: 'go hiking'),
              ]);

      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: TreeStackSection(
              chatId: 1,
              myParticipantId: 77,
              positions: const [],
              liveRootRoundId: 900,
              liveRootPhase: 'proposing',
            ),
          ),
        ),
        chatService: chatService,
        propositionService: propositionService,
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'pizza night');
      await settle(tester);

      expect(find.text('SIMILAR PROPOSITIONS'), findsOneWidget);
      expect(find.text('PROPOSITIONS SO FAR'), findsNothing);
      // The matched card renders as rich text with the matched word split
      // into its own highlighted (bold) span.
      expect(find.text('pizza for dinner'), findsOneWidget);
      final rich = tester.widget<Text>(find.text('pizza for dinner'));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.first.text, 'pizza');
      expect(spans.first.style?.fontWeight, FontWeight.w700);
      expect(find.text('go hiking'), findsNothing);

      // No match → honest empty state; clearing restores the full feed.
      await tester.enterText(find.byType(TextField), 'zqxv');
      await settle(tester);
      expect(find.text('Nothing similar yet — yours is new.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await settle(tester);
      expect(find.text('PROPOSITIONS SO FAR'), findsOneWidget);
      expect(find.text('pizza for dinner'), findsOneWidget);
      expect(find.text('go hiking'), findsOneWidget);
    });

    testWidgets('rating: standings above, inline duel below for the live ROOT round',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(900))
          .thenAnswer((_) async => []);
      when(() => propositionService.getPropositions(900)).thenAnswer(
          (_) async => [
                PropositionFixtures.model(id: 71, content: 'root A'),
                PropositionFixtures.model(id: 72, content: 'root B'),
              ]);
      when(() => propositionService.getPriorPairwiseVotes(
          roundId: 900, participantId: 77)).thenAnswer((_) async => []);
      when(() => propositionService.getRoundPairwiseVotes(900))
          .thenAnswer((_) async => []);

      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: TreeStackSection(
              chatId: 1,
              myParticipantId: 77,
              positions: const [],
              liveRootRoundId: 900,
              liveRootPhase: 'rating',
            ),
          ),
        ),
        chatService: chatService,
        propositionService: propositionService,
      );
      await settle(tester);

      // Current status: standings with rank numbers; user action: the duel
      // at the bottom. Each contender shows twice — once ranked, once as a
      // duel option.
      expect(find.text('CURRENT STANDINGS'), findsOneWidget);
      expect(find.text('VOTE — TAP THE BETTER ONE'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('root A'), findsNWidgets(2));
      expect(find.text('root B'), findsNWidgets(2));
      final standingsY =
          tester.getTopLeft(find.text('CURRENT STANDINGS')).dy;
      final duelY =
          tester.getTopLeft(find.text('VOTE — TAP THE BETTER ONE')).dy;
      expect(standingsY, lessThan(duelY),
          reason: 'status above, action at the bottom');
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('default walk', () {
    testWidgets('auto-selects the winner spine to the leaf on load',
        (tester) async {
      stubP1();

      await tester.pumpApp(section(),
          chatService: chatService, propositionService: propositionService);
      await settle(tester);

      // No option list — the winner is pre-committed…
      expect(find.text('PICK ONE'), findsNothing);
      expect(find.text('p1 alt'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(MessageCard), matching: find.text('p1 winner')),
          findsOneWidget);
      // …and the user is at the leaf.
      expect(find.textContaining('No follow-ups here yet'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('walks multiple positions automatically', (tester) async {
      when(() => propositionService.getPropositionsWithScores(100))
          .thenAnswer((_) async => scored([(11, 'p1 winner'), (12, 'p1 alt')]));
      when(() => propositionService.getPropositionsWithScores(200))
          .thenAnswer((_) async => scored([(21, 'p2 winner'), (22, 'p2 alt')]));
      when(() => chatService.getNodeBootstrap(21))
          .thenAnswer((_) async => bootstrap(parentId: 21));

      await tester.pumpApp(
        section(positions: const [
          TreePosition(roundId: 100, winnerId: 11),
          TreePosition(roundId: 200, winnerId: 21),
        ]),
        chatService: chatService,
        propositionService: propositionService,
      );
      await settle(tester);

      expect(
          find.descendant(
              of: find.byType(MessageCard), matching: find.text('p1 winner')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(MessageCard), matching: find.text('p2 winner')),
          findsOneWidget);
      expect(find.textContaining('No follow-ups here yet'), findsOneWidget);
    });
  });

  group('reopening a level', () {
    testWidgets('tap a committed block → options in ranking order',
        (tester) async {
      stubP1();

      await tester.pumpApp(section(),
          chatService: chatService, propositionService: propositionService);
      await settle(tester);

      await tester.tap(find.descendant(
          of: find.byType(MessageCard), matching: find.text('p1 winner')));
      await settle(tester);

      expect(find.text('PICK ONE'), findsOneWidget);
      final winnerY = tester.getTopLeft(find.text('p1 winner')).dy;
      final altY = tester.getTopLeft(find.text('p1 alt')).dy;
      expect(winnerY, lessThan(altY), reason: 'ranked best-first');
      // Plain cards: no rank badges, no RECOMMENDED tag.
      expect(find.text('#1'), findsNothing);
      expect(find.text('RECOMMENDED'), findsNothing);
      // Frontier UI hidden while the level is open.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('picking the winner again closes the level and returns to the leaf',
        (tester) async {
      stubP1();

      await tester.pumpApp(section(),
          chatService: chatService, propositionService: propositionService);
      await settle(tester);
      await tester.tap(find.descendant(
          of: find.byType(MessageCard), matching: find.text('p1 winner')));
      await settle(tester);

      await tester.tap(find.text('p1 winner').last);
      await settle(tester);

      expect(find.text('PICK ONE'), findsNothing);
      expect(find.textContaining('No follow-ups here yet'), findsOneWidget);
    });

    testWidgets('picking a SIBLING diverges into its subtree', (tester) async {
      stubP1();
      when(() => chatService.getNodeBootstrap(12))
          .thenAnswer((_) async => bootstrap(parentId: 12));

      await tester.pumpApp(
        section(liveRootPanel: const Text('LIVE ROOT PANEL')),
        chatService: chatService,
        propositionService: propositionService,
      );
      await settle(tester);

      // On load: spine tip hosts the live root panel.
      expect(find.text('LIVE ROOT PANEL'), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(MessageCard), matching: find.text('p1 winner')));
      await settle(tester);
      await tester.tap(find.text('p1 alt'));
      await settle(tester);

      // Divergent leaf runs its OWN subround — never the live root panel.
      expect(find.text('LIVE ROOT PANEL'), findsNothing);
      expect(find.textContaining('No follow-ups here yet'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      verify(() => chatService.getNodeBootstrap(12)).called(1);
    });
  });

  group('tree era nodes', () {
    testWidgets('sealed node: winner auto-selected; reopen shows PICK ONE',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(100))
          .thenAnswer((_) async => scored([(11, 'p1 winner')]));
      when(() => chatService.getNodeBootstrap(11)).thenAnswer(
        (_) async => bootstrap(
          parentId: 11,
          node: nodePayload(
            roundId: 500,
            phase: 'rating',
            completedAt: '2026-07-12T12:00:00Z',
            winnerId: 32,
            props: [
              {'id': 31, 'content': 'follow-up A', 'is_agent': false},
              {'id': 32, 'content': 'follow-up B', 'is_agent': false},
            ],
          ),
        ),
      );
      when(() => chatService.getNodeBootstrap(32))
          .thenAnswer((_) async => bootstrap(parentId: 32));

      await tester.pumpApp(section(),
          chatService: chatService, propositionService: propositionService);
      await settle(tester);

      // Node winner auto-committed, walk continued into it.
      expect(
          find.descendant(
              of: find.byType(MessageCard), matching: find.text('follow-up B')),
          findsOneWidget);
      expect(find.text('follow-up A'), findsNothing);

      await tester.tap(find.descendant(
          of: find.byType(MessageCard), matching: find.text('follow-up B')));
      await settle(tester);
      expect(find.text('PICK ONE'), findsOneWidget);
      expect(find.text('follow-up A'), findsOneWidget);
    });

    testWidgets('live voting node renders standings + the INLINE duel',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(100))
          .thenAnswer((_) async => scored([(11, 'p1 winner')]));
      when(() => propositionService.getPriorPairwiseVotes(
          roundId: 500, participantId: 77)).thenAnswer((_) async => []);
      when(() => propositionService.getRoundPairwiseVotes(500))
          .thenAnswer((_) async => []);
      when(() => chatService.getNodeBootstrap(11)).thenAnswer(
        (_) async => bootstrap(
          parentId: 11,
          windowPhase: 'rating',
          node: nodePayload(
            roundId: 500,
            phase: 'rating',
            props: [
              {'id': 31, 'content': 'contender A', 'is_agent': true,
               'created_at': '2026-07-13T00:00:00Z'},
              {'id': 32, 'content': 'contender B', 'is_agent': false,
               'created_at': '2026-07-13T00:01:00Z'},
            ],
          ),
        ),
      );

      await tester.pumpApp(section(),
          chatService: chatService, propositionService: propositionService);
      await settle(tester);

      // Standings (rank numbers) above the inline duel; no push-away button,
      // no composer, no option list. Contenders show twice — ranked + duel.
      expect(find.text('CURRENT STANDINGS'), findsOneWidget);
      expect(find.text('VOTE — TAP THE BETTER ONE'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('contender A'), findsNWidgets(2));
      expect(find.text('contender B'), findsNWidgets(2));
      expect(find.text('Vote on this position'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('live proposing: realtime feed above, composer at the bottom, read-only',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(100))
          .thenAnswer((_) async => scored([(11, 'p1 winner')]));
      when(() => chatService.getNodeBootstrap(11)).thenAnswer(
        (_) async => bootstrap(
          parentId: 11,
          node: nodePayload(
            roundId: 500,
            phase: 'proposing',
            props: [
              {'id': 31, 'content': 'first idea', 'is_agent': true},
              {'id': 32, 'content': 'second idea', 'is_agent': false},
            ],
          ),
        ),
      );

      await tester.pumpApp(section(),
          chatService: chatService, propositionService: propositionService);
      await settle(tester);

      // Feed under the label, newest at the BOTTOM; composer — the user's
      // action — below the feed. Takes visible (awareness) but NOT clickable
      // options — tapping one commits nothing.
      final composerY = tester.getTopLeft(find.byType(TextField)).dy;
      final labelY = tester.getTopLeft(find.text('PROPOSITIONS SO FAR')).dy;
      final secondY = tester.getTopLeft(find.text('second idea')).dy;
      final firstY = tester.getTopLeft(find.text('first idea')).dy;
      expect(labelY, lessThan(firstY));
      expect(firstY, lessThan(secondY),
          reason: 'latest submission at the bottom');
      expect(secondY, lessThan(composerY),
          reason: 'newest take sits adjacent to the composer');
      await tester.tap(find.text('first idea'));
      await settle(tester);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'still at the composer — feed items are read-only');
      expect(find.text('Vote on this position'), findsNothing);
      expect(find.text('PICK ONE'), findsNothing);
    });

    testWidgets('node feed filters to similar takes while typing',
        (tester) async {
      when(() => propositionService.getPropositionsWithScores(100))
          .thenAnswer((_) async => scored([(11, 'p1 winner')]));
      when(() => chatService.getNodeBootstrap(11)).thenAnswer(
        (_) async => bootstrap(
          parentId: 11,
          node: nodePayload(
            roundId: 500,
            phase: 'proposing',
            props: [
              {'id': 31, 'content': 'ban homework', 'is_agent': false},
              {'id': 32, 'content': 'longer recess', 'is_agent': false},
            ],
          ),
        ),
      );

      await tester.pumpApp(section(),
          chatService: chatService, propositionService: propositionService);
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'homework ban');
      await settle(tester);
      expect(find.text('SIMILAR PROPOSITIONS'), findsOneWidget);
      expect(find.text('ban homework'), findsOneWidget);
      expect(find.text('longer recess'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await settle(tester);
      expect(find.text('PROPOSITIONS SO FAR'), findsOneWidget);
      expect(find.text('longer recess'), findsOneWidget);
    });
  });
}
