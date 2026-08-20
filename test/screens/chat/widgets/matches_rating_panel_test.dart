import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/chat/widgets/matches_rating_panel.dart';
import 'package:onemind_app/services/matches/match_pair_selector.dart';
import 'package:onemind_app/services/proposition_service.dart';

import '../../../fixtures/proposition_fixtures.dart';

class MockPropositionService extends Mock implements PropositionService {}

void main() {
  late MockPropositionService service;

  final p1 = PropositionFixtures.model(id: 1, content: 'Alpha idea');
  final p2 = PropositionFixtures.model(id: 2, content: 'Beta idea');

  setUp(() {
    service = MockPropositionService();
    when(() => service.submitPairwiseComparison(
          roundId: any(named: 'roundId'),
          participantId: any(named: 'participantId'),
          winnerPropositionId: any(named: 'winnerPropositionId'),
          loserPropositionId: any(named: 'loserPropositionId'),
          isTie: any(named: 'isTie'),
        )).thenAnswer((_) async {});
    when(() => service.submitPairwiseSkip(
          roundId: any(named: 'roundId'),
          participantId: any(named: 'participantId'),
          propAId: any(named: 'propAId'),
          propBId: any(named: 'propBId'),
        )).thenAnswer((_) async {});
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<Proposition> rateable,
    List<PriorVote> prior = const [],
    VoidCallback? onSkip,
    VoidCallback? onDone,
    bool allowSkip = true,
    MatchObjective objective = MatchObjective.winnerOnly,
  }) async {
    when(() => service.getPriorPairwiseVotes(
          roundId: any(named: 'roundId'),
          participantId: any(named: 'participantId'),
        )).thenAnswer((_) async => prior);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [propositionServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MatchesRatingPanel(
              roundId: 5,
              participantId: 9,
              rateable: rateable,
              objective: objective,
              onSkip: allowSkip ? (onSkip ?? () {}) : null,
              onDone: onDone ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a bare per-match counter that advances on each vote '
      '(no "of N" — the selector has no fixed total)', (tester) async {
    final p3 = PropositionFixtures.model(id: 3, content: 'Gamma idea');
    final p4 = PropositionFixtures.model(id: 4, content: 'Delta idea');
    await pumpPanel(tester,
        rateable: [p1, p2, p3, p4], objective: MatchObjective.fullRank);

    expect(find.text('Match 1'), findsOneWidget);
    // No total/bar: full_rank terminates early by a path-dependent amount.
    expect(find.textContaining(' of '), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // "Equal" advances deterministically (no need to know which pair shows).
    await tester.tap(find.text('Equal'));
    await tester.pumpAndSettle();
    expect(find.text('Match 2'), findsOneWidget);
  });

  testWidgets('renders both options + Equal + Skip + Done', (tester) async {
    await pumpPanel(tester, rateable: [p1, p2]);
    expect(find.text('Alpha idea'), findsOneWidget);
    expect(find.text('Beta idea'), findsOneWidget);
    expect(find.text('Equal'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget); // per-match
    expect(find.text('Done'), findsOneWidget); // leave phase
  });

  testWidgets('tapping an option submits it as the winner', (tester) async {
    await pumpPanel(tester, rateable: [p1, p2]);
    await tester.tap(find.text('Alpha idea')); // p1 → winner regardless of position
    await tester.pumpAndSettle();
    verify(() => service.submitPairwiseComparison(
          roundId: 5,
          participantId: 9,
          winnerPropositionId: 1,
          loserPropositionId: 2,
          isTie: false,
        )).called(1);
  });

  testWidgets('Equal submits a tie', (tester) async {
    await pumpPanel(tester, rateable: [p1, p2]);
    await tester.tap(find.text('Equal'));
    await tester.pumpAndSettle();
    verify(() => service.submitPairwiseComparison(
          roundId: any(named: 'roundId'),
          participantId: any(named: 'participantId'),
          winnerPropositionId: any(named: 'winnerPropositionId'),
          loserPropositionId: any(named: 'loserPropositionId'),
          isTie: true,
        )).called(1);
  });

  testWidgets('fires onDone + shows done state when no useful pair remains',
      (tester) async {
    var doneCalled = false;
    // p1 already beat p2 → winner_only has a champion → selector returns null.
    await pumpPanel(
      tester,
      rateable: [p1, p2],
      prior: const [PriorVote(winnerId: 1, loserId: 2)],
      onDone: () => doneCalled = true,
    );
    expect(doneCalled, isTrue);
    expect(find.textContaining('Done'), findsOneWidget);
  });

  testWidgets('Skip records a per-match skip (not leaving the phase)',
      (tester) async {
    var left = false;
    await pumpPanel(tester, rateable: [p1, p2], onSkip: () => left = true);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    // Per-match skip → records the pair, does NOT fire the leave-phase callback.
    verify(() => service.submitPairwiseSkip(
          roundId: 5,
          participantId: 9,
          propAId: any(named: 'propAId'),
          propBId: any(named: 'propBId'),
        )).called(1);
    expect(left, isFalse);
  });

  testWidgets('Done confirms before invoking the leave-phase callback',
      (tester) async {
    var left = false;
    await pumpPanel(tester, rateable: [p1, p2], onSkip: () => left = true);
    await tester.tap(find.byKey(const Key('matches-done')));
    await tester.pumpAndSettle();
    // Confirmation dialog shown; phase not left yet.
    expect(find.text('Done rating?'), findsOneWidget);
    expect(left, isFalse);
    // Confirm.
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(left, isTrue);
  });

  testWidgets('Done can be cancelled — stays in the rating phase',
      (tester) async {
    var left = false;
    await pumpPanel(tester, rateable: [p1, p2], onSkip: () => left = true);
    await tester.tap(find.byKey(const Key('matches-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(left, isFalse);
  });

  testWidgets('Skip + Done hidden when skipping is not allowed (onSkip null)',
      (tester) async {
    await pumpPanel(tester, rateable: [p1, p2], allowSkip: false);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Done'), findsNothing);
    // The judgment controls still render.
    expect(find.text('Equal'), findsOneWidget);
  });
}
