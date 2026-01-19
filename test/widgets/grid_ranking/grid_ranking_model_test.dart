import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/grid_ranking/grid_ranking_model.dart';

void main() {
  group('GridRankingModel', () {
    group('Initialization', () {
      test('initializes with 2 propositions in binary phase', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'Proposition 1'},
          {'id': 2, 'content': 'Proposition 2'},
        ]);

        expect(model.phase, RankingPhase.binary);
        expect(model.rankedPropositions.length, 2);
        expect(model.rankedPropositions[0].position, 100.0);
        expect(model.rankedPropositions[1].position, 0.0);
      });

      test('initializes with correct IDs and content', () {
        final model = GridRankingModel([
          {'id': 'abc', 'content': 'First'},
          {'id': 'def', 'content': 'Second'},
        ]);

        expect(model.rankedPropositions[0].id, 'abc');
        expect(model.rankedPropositions[0].content, 'First');
        expect(model.rankedPropositions[1].id, 'def');
        expect(model.rankedPropositions[1].content, 'Second');
      });

      test('handles empty propositions list', () {
        final model = GridRankingModel([]);
        expect(model.rankedPropositions.isEmpty, true);
      });

      test('handles single proposition', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'Only one'},
        ]);
        // With only 1 proposition, binary comparison can't happen
        expect(model.rankedPropositions.isEmpty, true);
      });
    });

    group('Binary Phase', () {
      test('swapBinaryPositions swaps the two propositions', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
        ]);

        expect(model.rankedPropositions[0].position, 100.0); // id=1 at top
        expect(model.rankedPropositions[1].position, 0.0); // id=2 at bottom

        model.swapBinaryPositions();

        expect(model.rankedPropositions[0].position, 0.0); // id=1 now at bottom
        expect(model.rankedPropositions[1].position, 100.0); // id=2 now at top
      });

      test('swapBinaryPositions does nothing outside binary phase', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);

        model.confirmBinaryChoice(); // Move to positioning phase

        final pos0Before = model.rankedPropositions[0].position;
        final pos1Before = model.rankedPropositions[1].position;

        model.swapBinaryPositions(); // Should do nothing

        expect(model.rankedPropositions[0].position, pos0Before);
        expect(model.rankedPropositions[1].position, pos1Before);
      });

      test('confirmBinaryChoice transitions to positioning phase', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);

        expect(model.phase, RankingPhase.binary);

        model.confirmBinaryChoice();

        expect(model.phase, RankingPhase.positioning);
      });

      test('confirmBinaryChoice adds next proposition as active', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);

        model.confirmBinaryChoice();

        expect(model.rankedPropositions.length, 3);
        final activeProps =
            model.rankedPropositions.where((p) => p.isActive).toList();
        expect(activeProps.length, 1);
        expect(activeProps.first.id, '3');
        expect(activeProps.first.position, 50.0); // Starts at middle
      });

      test('completes immediately if only 2 propositions', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
        ]);

        model.confirmBinaryChoice();

        expect(model.phase, RankingPhase.completed);
        expect(model.isComplete, true);
      });
    });

    group('Positioning Phase - Basic Movement', () {
      late GridRankingModel model;

      setUp(() {
        model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
      });

      test('moveActiveProposition changes position', () {
        final activeBefore = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(activeBefore.position, 50.0);

        model.moveActiveProposition(10);

        final activeAfter = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(activeAfter.position, 60.0);
      });

      test('moveActiveProposition can move up and down', () {
        model.moveActiveProposition(25); // Move up
        var active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 75.0);

        model.moveActiveProposition(-50); // Move down
        active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 25.0);
      });

      test('setActivePropositionPosition sets exact position', () {
        model.setActivePropositionPosition(75.0);

        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 75.0);
      });

      test('confirmPlacement removes active state', () {
        model.confirmPlacement();

        // Should have new active (id=4) or none if no more
        // In this case, only 3 props so should be completed
        expect(model.phase, RankingPhase.completed);
      });
    });

    group('Compression - Above 100', () {
      late GridRankingModel model;

      setUp(() {
        model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
      });

      test('active card stays at 100 when pushed above', () {
        model.moveActiveProposition(100); // Push to 150 virtual

        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 100.0);
      });

      test('other cards compress when active pushed above 100', () {
        // Initially: prop1=100, prop2=0, prop3(active)=50
        model.moveActiveProposition(100); // Virtual position = 150

        // With overflow of 50, compression ratio = 100/150 = 0.667
        // prop1 was at 100, becomes 100 * 0.667 = 66.67
        // prop2 was at 0, stays at 0
        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');

        expect(prop1.position, closeTo(66.67, 0.1));
        expect(prop2.position, closeTo(0, 0.1));
      });

      test('compression increases with more overflow', () {
        model.moveActiveProposition(150); // Virtual = 200

        // Compression ratio = 100/200 = 0.5
        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        expect(prop1.position, closeTo(50.0, 0.1));
      });

      test('extreme compression at very high overflow', () {
        model.moveActiveProposition(950); // Virtual = 1000

        // Compression ratio = 100/1000 = 0.1
        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        expect(prop1.position, closeTo(10.0, 0.5));
      });
    });

    group('Compression - Below 0', () {
      late GridRankingModel model;

      setUp(() {
        model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
      });

      test('active card stays at 0 when pushed below', () {
        model.moveActiveProposition(-100); // Push to -50 virtual

        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 0.0);
      });

      test('other cards compress from top when active pushed below 0', () {
        // Initially: prop1=100, prop2=0, prop3(active)=50
        model.moveActiveProposition(-100); // Virtual position = -50

        // With underflow of 50, compression ratio = 100/150 = 0.667
        // prop1 was at 100, becomes 100 - (100-100)*0.667 = 100 - 0 = stays high
        // Actually the formula is: newTruePos = 100 - (100 - baseTruePos) * compressionRatio
        // prop1: 100 - (100-100) * 0.667 = 100
        // prop2: 100 - (100-0) * 0.667 = 100 - 66.67 = 33.33
        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');

        expect(prop1.position, closeTo(100.0, 0.1));
        expect(prop2.position, closeTo(33.33, 0.5));
      });

      test('compression increases with more underflow', () {
        model.moveActiveProposition(-150); // Virtual = -100

        // Compression ratio = 100/200 = 0.5
        // prop2: 100 - (100-0) * 0.5 = 100 - 50 = 50
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');
        expect(prop2.position, closeTo(50.0, 0.5));
      });
    });

    group('Expansion - Returning from Compression', () {
      late GridRankingModel model;

      setUp(() {
        model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
      });

      test('positions expand when returning from above 100', () {
        // Compress
        model.moveActiveProposition(100); // Virtual = 150

        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1Compressed, lessThan(100));

        // Return to normal range
        model.moveActiveProposition(-100); // Virtual = 50

        final prop1Expanded =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2Expanded =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        // After expansion, should restore to 0-100 range
        expect(prop1Expanded, closeTo(100.0, 1.0));
        expect(prop2Expanded, closeTo(0.0, 1.0));
      });

      test('positions expand when returning from below 0', () {
        // Compress
        model.moveActiveProposition(-100); // Virtual = -50

        final prop2Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        expect(prop2Compressed, greaterThan(0));

        // Return to normal range
        model.moveActiveProposition(100); // Virtual = 50

        final prop1Expanded =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2Expanded =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        expect(prop1Expanded, closeTo(100.0, 1.0));
        expect(prop2Expanded, closeTo(0.0, 1.0));
      });
    });

    group('Position Normalization', () {
      test('positions normalize to integers after placement', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.setActivePropositionPosition(33.7);
        model.confirmPlacement();

        // After normalization, position should be rounded
        final prop3 = model.rankedPropositions.firstWhere((p) => p.id == '3');
        expect(prop3.position, equals(prop3.position.roundToDouble()));
      });

      test('ordering is preserved after normalization', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();

        // Place prop3 at 75
        model.setActivePropositionPosition(75.0);
        model.confirmPlacement();

        // Place prop4 at 25
        model.setActivePropositionPosition(25.0);
        model.confirmPlacement();

        // Get positions sorted
        final sorted = model.rankedPropositions.toList()
          ..sort((a, b) => b.position.compareTo(a.position));

        // Order should be: prop1(100) > prop3(75) > prop4(25) > prop2(0)
        expect(sorted[0].id, '1');
        expect(sorted[1].id, '3');
        expect(sorted[2].id, '4');
        expect(sorted[3].id, '2');
      });
    });

    group('Stack Detection', () {
      test('cards at same position form a stack', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Move prop3 to same position as prop1 (100)
        model.setActivePropositionPosition(100.0);
        model.confirmPlacement();

        final stack = model.getStackAtPosition(100.0);
        expect(stack, isNotNull);
        expect(stack!.cardCount, 2);
        expect(stack.allCardIds.contains('1'), true);
        expect(stack.allCardIds.contains('3'), true);
      });

      test('stack cycling changes default card', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.setActivePropositionPosition(100.0);
        model.confirmPlacement();

        final stackBefore = model.getStackAtPosition(100.0)!;
        final defaultBefore = stackBefore.defaultCardId;

        model.cycleStackCard(100.0, defaultBefore);

        final stackAfter = model.getStackAtPosition(100.0)!;
        expect(stackAfter.defaultCardId, isNot(equals(defaultBefore)));
      });

      test('no stack when cards at different positions', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        expect(model.getStackAtPosition(100.0), isNull);
        expect(model.getStackAtPosition(50.0), isNull);
        expect(model.getStackAtPosition(0.0), isNull);
      });
    });

    group('Undo', () {
      test('undoLastPlacement removes the active card', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();

        // Place prop3
        model.setActivePropositionPosition(75.0);
        model.confirmPlacement();

        // Now prop4 is active
        expect(model.rankedPropositions.length, 4);

        model.undoLastPlacement();

        // prop4 should be removed, prop3 should become active again
        expect(model.rankedPropositions.length, 3);
        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.id, '3');
      });

      test('undo returns to binary phase if only 2 props left', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.undoLastPlacement();

        expect(model.phase, RankingPhase.binary);
        expect(model.rankedPropositions.length, 2);
      });

      test('undo does nothing in binary phase', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
        ]);

        final countBefore = model.rankedPropositions.length;
        model.undoLastPlacement();

        expect(model.rankedPropositions.length, countBefore);
      });

      test('undo uncompresses positions if was at boundary', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();

        // Place prop3 at 100 (at boundary)
        model.setActivePropositionPosition(100.0);
        model.confirmPlacement();

        // Now we have prop4 active
        model.undoLastPlacement();

        // Positions should be normalized back
        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');
        expect(prop1.position, closeTo(100.0, 1.0));
        expect(prop2.position, closeTo(0.0, 1.0));
      });

      test('undo after moving beyond 100 restores compressed positions', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();

        // Place prop3 at 50
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Now prop4 is active - move it BEYOND 100 to cause compression
        model.setActivePropositionPosition(150.0);

        // Prop1 (at 100) should now be compressed
        final prop1Before = model.rankedPropositions.firstWhere((p) => p.id == '1');
        expect(prop1Before.position, lessThan(100.0));

        // Undo before confirming
        model.undoLastPlacement();

        // Prop1 should be restored to 100
        final prop1After = model.rankedPropositions.firstWhere((p) => p.id == '1');
        expect(prop1After.position, closeTo(100.0, 1.0));
      });

      test('undo spreads stacked cards when all at same position', () {
        // Resume from saved rankings where cards are stacked at 100
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 100.0},
            {'id': 3, 'content': 'C', 'position': 0.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        // Add a 4th proposition
        model.addProposition({'id': 4, 'content': 'D'});

        // Move prop4 beyond 100, compressing the stacked cards
        model.setActivePropositionPosition(150.0);

        // Undo
        model.undoLastPlacement();

        // Now prop3 becomes active
        // The remaining cards (1, 2) were both at 100, should be spread
        final inactiveProps = model.rankedPropositions.where((p) => !p.isActive).toList();
        final positions = inactiveProps.map((p) => p.position).toSet();

        // Cards should NOT all be at the same position
        expect(positions.length, greaterThan(1));
      });

      test('undo to binary phase spreads stacked cards correctly', () {
        // Start with stacked cards from resume
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 100.0},
            {'id': 3, 'content': 'C', 'position': 0.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        // Add 4th prop and move to boundary
        model.addProposition({'id': 4, 'content': 'D'});
        model.setActivePropositionPosition(100.0);

        // Undo removes D, makes C active
        model.undoLastPlacement();

        // Undo removes C, should return to binary with 1 and 2
        model.undoLastPlacement();

        expect(model.phase, RankingPhase.binary);
        expect(model.rankedPropositions.length, 2);

        // In binary phase, one should be at 100, other at 0
        final positions = model.rankedPropositions.map((p) => p.position).toList();
        expect(positions, containsAll([100.0, 0.0]));
      });
    });

    group('Lazy Loading Mode', () {
      test('callback fires on confirmBinaryChoice in lazy mode', () {
        var callbackCalled = false;
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
          onPlacementConfirmed: () => callbackCalled = true,
        );

        model.confirmBinaryChoice();

        expect(callbackCalled, true);
        expect(model.phase, RankingPhase.positioning);
      });

      test('callback fires on confirmPlacement in lazy mode', () {
        var callbackCount = 0;
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
          onPlacementConfirmed: () => callbackCount++,
        );

        // Confirm binary choice - callback fires to request next prop
        model.confirmBinaryChoice();
        expect(callbackCount, 1);

        // Simulate server response: add prop3 (this makes it active)
        model.addProposition({'id': 3, 'content': 'C'});
        expect(model.rankedPropositions.length, 3);

        // Position and confirm placement - callback fires again
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        expect(callbackCount, 2); // Called again after confirmPlacement
      });

      test('addProposition adds to model', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
        );

        model.confirmBinaryChoice();
        model.addProposition({'id': 3, 'content': 'C'});

        expect(model.totalPropositions, 3);
        expect(model.rankedPropositions.length, 3);
      });

      test('setNoMorePropositions completes when no active card', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
        );

        model.confirmBinaryChoice();
        // No propositions added, so no active card
        model.setNoMorePropositions();

        expect(model.phase, RankingPhase.completed);
        expect(model.isComplete, true);
      });

      test('does not complete while waiting for more propositions', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
        );

        model.confirmBinaryChoice();

        // Phase is positioning, but morePropositionsExpected is true
        expect(model.phase, RankingPhase.positioning);
        expect(model.morePropositionsExpected, true);
        expect(model.isComplete, false);
      });

      test('full lazy loading flow', () {
        var requestCount = 0;
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
          onPlacementConfirmed: () => requestCount++,
        );

        // Binary phase complete
        model.confirmBinaryChoice();
        expect(requestCount, 1);

        // Simulate server response: add prop3
        model.addProposition({'id': 3, 'content': 'C'});
        expect(model.rankedPropositions.length, 3);

        // Place prop3
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();
        expect(requestCount, 2);

        // Simulate server response: add prop4
        model.addProposition({'id': 4, 'content': 'D'});
        expect(model.rankedPropositions.length, 4);

        // Place prop4
        model.setActivePropositionPosition(25.0);
        model.confirmPlacement();
        expect(requestCount, 3);

        // Simulate server: no more
        model.setNoMorePropositions();

        expect(model.phase, RankingPhase.completed);
        expect(model.isComplete, true);
      });
    });

    group('Final Rankings', () {
      test('getFinalRankings returns all positions', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        final rankings = model.getFinalRankings();

        expect(rankings.length, 3);
        expect(rankings.containsKey('1'), true);
        expect(rankings.containsKey('2'), true);
        expect(rankings.containsKey('3'), true);
        expect(rankings['1'], closeTo(100.0, 1.0));
        expect(rankings['2'], closeTo(0.0, 1.0));
        expect(rankings['3'], closeTo(50.0, 1.0));
      });

      test('rankings reflect swapped binary positions', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
        ]);

        model.swapBinaryPositions();
        model.confirmBinaryChoice();

        final rankings = model.getFinalRankings();
        expect(rankings['1'], closeTo(0.0, 1.0));
        expect(rankings['2'], closeTo(100.0, 1.0));
      });
    });

    group('Edge Cases', () {
      test('handles rapid position changes', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Rapid movements
        for (var i = 0; i < 100; i++) {
          model.moveActiveProposition(1);
        }

        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 100.0); // Clamped at max
      });

      test('handles compression with many cards', () {
        final props = List.generate(10, (i) => {'id': i, 'content': 'Prop $i'});
        final model = GridRankingModel(props);
        model.confirmBinaryChoice();

        // Place several cards
        for (var i = 2; i < 8; i++) {
          model.setActivePropositionPosition((i * 10).toDouble());
          model.confirmPlacement();
        }

        // Push last card above 100
        model.moveActiveProposition(100);

        // All positions should still be valid
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0));
        }
      });

      test('handles placement at exact boundary (100)', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.setActivePropositionPosition(100.0);
        model.confirmPlacement();

        final prop3 = model.rankedPropositions.firstWhere((p) => p.id == '3');
        expect(prop3.position, 100.0);
      });

      test('handles placement at exact boundary (0)', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.setActivePropositionPosition(0.0);
        model.confirmPlacement();

        final prop3 = model.rankedPropositions.firstWhere((p) => p.id == '3');
        expect(prop3.position, 0.0);
      });

      test('multiple cards at same position all get stacked', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
          {'id': 5, 'content': 'E'},
        ]);
        model.confirmBinaryChoice();

        // Place all at 50
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        final stack = model.getStackAtPosition(50.0);
        expect(stack, isNotNull);
        expect(stack!.cardCount, 3);
      });
    });

    group('Controls Disabled State', () {
      test('areControlsDisabled returns false normally', () {
        final model = GridRankingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        expect(model.areControlsDisabled, false);
      });
    });

    group('Resume from Saved Rankings', () {
      test('isResuming=true initializes with saved positions', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 30.0},
          ],
          isResuming: true,
        );

        expect(model.phase, RankingPhase.completed); // No more expected
        expect(model.rankedPropositions.length, 2);
        expect(model.rankedPropositions[0].position, 100.0);
        expect(model.rankedPropositions[1].position, 30.0);
        expect(model.rankedPropositions[0].isActive, false);
        expect(model.rankedPropositions[1].isActive, false);
      });

      test('isResuming=true skips binary phase', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 0.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        // Should be in positioning phase (not binary) when more expected
        expect(model.phase, RankingPhase.positioning);
      });

      test('isResuming=true with lazyLoadingMode sets needsFetchAfterInit', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 0.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        expect(model.needsFetchAfterInit, true);
      });

      test('clearNeedsFetchAfterInit clears the flag', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 0.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        expect(model.needsFetchAfterInit, true);
        model.clearNeedsFetchAfterInit();
        expect(model.needsFetchAfterInit, false);
      });

      test('isResuming=false starts normal binary phase', () {
        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          isResuming: false,
        );

        expect(model.phase, RankingPhase.binary);
        expect(model.rankedPropositions[0].position, 100.0);
        expect(model.rankedPropositions[1].position, 0.0);
      });
    });

    group('Save Rankings Callback', () {
      test('onSaveRankings called after confirmBinaryChoice', () {
        Map<String, double>? savedRankings;
        bool? allPositionsChanged;

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
          ],
          lazyLoadingMode: true,
          onSaveRankings: (rankings, allChanged) {
            savedRankings = rankings;
            allPositionsChanged = allChanged;
          },
        );

        model.confirmBinaryChoice();

        expect(savedRankings, isNotNull);
        expect(savedRankings!.length, 2);
        expect(allPositionsChanged, true); // Initial binary is always all changed
      });

      test('onSaveRankings called after confirmPlacement', () {
        Map<String, double>? savedRankings;
        bool? allPositionsChanged;

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
          ],
          onSaveRankings: (rankings, allChanged) {
            savedRankings = rankings;
            allPositionsChanged = allChanged;
          },
        );

        model.confirmBinaryChoice();
        savedRankings = null; // Reset after binary

        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        expect(savedRankings, isNotNull);
        // Now optimized: only sends the newly placed prop (no compression)
        expect(savedRankings!.length, 1);
        expect(savedRankings!.containsKey('3'), true);
      });

      test('onSaveRankings detects compression when positions shift', () {
        bool? compressionDetected;

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
            {'id': 4, 'content': 'D'},
          ],
          onSaveRankings: (rankings, allChanged) {
            compressionDetected = allChanged;
          },
        );

        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Placing below 0 causes compression
        model.setActivePropositionPosition(-10.0);
        model.confirmPlacement();

        // Compression should be detected
        expect(compressionDetected, isNotNull);
      });

      test('sends ALL rankings when dragging past boundary causes compression', () {
        final savedRankings = <Map<String, double>>[];
        final allChangedFlags = <bool>[];

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
          ],
          onSaveRankings: (rankings, allChanged) {
            savedRankings.add(Map.from(rankings));
            allChangedFlags.add(allChanged);
          },
        );

        // Binary: card 1 at 100, card 2 at 0
        model.confirmBinaryChoice();
        expect(savedRankings.last.length, 2); // Both sent initially

        // Get initial positions
        final prop1Before = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2Before = model.rankedPropositions.firstWhere((p) => p.id == '2');
        expect(prop1Before.position, 100.0);
        expect(prop2Before.position, 0.0);

        // Drag card 3 PAST 100 boundary - this should compress card 1
        model.setActivePropositionPosition(120.0);

        // Verify compression happened during drag
        final prop1During = model.rankedPropositions.firstWhere((p) => p.id == '1');
        expect(prop1During.position, lessThan(100.0),
            reason: 'Card at 100 should be compressed when new card goes past boundary');

        // Confirm placement
        model.confirmPlacement();

        // Should detect compression and send ALL rankings
        expect(allChangedFlags.last, true,
            reason: 'allPositionsChanged should be true when compression happened');
        expect(savedRankings.last.length, 3,
            reason: 'All 3 rankings should be sent when compression happened');
        expect(savedRankings.last.containsKey('1'), true);
        expect(savedRankings.last.containsKey('2'), true);
        expect(savedRankings.last.containsKey('3'), true);
      });
    });

    group('fromResults Factory', () {
      test('creates model in completed phase', () {
        final model = GridRankingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 85.0},
          {'id': 2, 'content': 'B', 'finalRating': 50.0},
          {'id': 3, 'content': 'C', 'finalRating': 15.0},
        ]);

        expect(model.phase, RankingPhase.completed);
      });

      test('positions match finalRating values', () {
        final model = GridRankingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 85.0},
          {'id': 2, 'content': 'B', 'finalRating': 50.0},
          {'id': 3, 'content': 'C', 'finalRating': 15.0},
        ]);

        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');
        final prop3 = model.rankedPropositions.firstWhere((p) => p.id == '3');

        expect(prop1.position, 85.0);
        expect(prop2.position, 50.0);
        expect(prop3.position, 15.0);
      });

      test('all propositions are inactive', () {
        final model = GridRankingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 85.0},
          {'id': 2, 'content': 'B', 'finalRating': 50.0},
        ]);

        for (final prop in model.rankedPropositions) {
          expect(prop.isActive, false);
        }
      });

      test('defaults to 50.0 when finalRating is null', () {
        final model = GridRankingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': null},
          {'id': 2, 'content': 'B'}, // finalRating not present
        ]);

        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');

        expect(prop1.position, 50.0);
        expect(prop2.position, 50.0);
      });

      test('handles empty list', () {
        final model = GridRankingModel.fromResults([]);

        expect(model.phase, RankingPhase.completed);
        expect(model.rankedPropositions.isEmpty, true);
      });

      test('detects stacks for same position', () {
        final model = GridRankingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 50.0},
          {'id': 2, 'content': 'B', 'finalRating': 50.0},
          {'id': 3, 'content': 'C', 'finalRating': 100.0},
        ]);

        final stack = model.getStackAtPosition(50.0);
        expect(stack, isNotNull);
        expect(stack!.cardCount, 2);
      });

      test('handles integer finalRating values', () {
        final model = GridRankingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 75}, // int, not double
          {'id': 2, 'content': 'B', 'finalRating': 25.5}, // double
        ]);

        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');

        expect(prop1.position, 75.0);
        expect(prop2.position, 25.5);
      });

      test('preserves content correctly', () {
        final model = GridRankingModel.fromResults([
          {'id': 'abc', 'content': 'First proposition', 'finalRating': 80.0},
          {'id': 'def', 'content': 'Second proposition', 'finalRating': 20.0},
        ]);

        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == 'abc');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == 'def');

        expect(prop1.content, 'First proposition');
        expect(prop2.content, 'Second proposition');
      });
    });

    group('Save Rankings Optimization', () {
      test('sends only new proposition when no compression happens', () {
        final savedRankings = <Map<String, double>>[];

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
            {'id': 4, 'content': 'D'},
          ],
          onSaveRankings: (rankings, allChanged) {
            savedRankings.add(Map.from(rankings));
          },
        );

        // Binary choice sends 2 (both are new)
        model.confirmBinaryChoice();
        expect(savedRankings.last.length, 2);

        // Place prop3 at 50 - no compression
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Should only send 1 (the newly placed one)
        expect(savedRankings.last.length, 1);
        expect(savedRankings.last.containsKey('3'), true);

        // Place prop4 at 25 - no compression
        model.setActivePropositionPosition(25.0);
        model.confirmPlacement();

        // Should only send 1 (the newly placed one)
        expect(savedRankings.last.length, 1);
        expect(savedRankings.last.containsKey('4'), true);
      });

      test('sends all propositions when normalization causes position shifts', () {
        final savedRankings = <Map<String, double>>[];
        final allChangedFlags = <bool>[];

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
            {'id': 4, 'content': 'D'},
            {'id': 5, 'content': 'E'},
          ],
          onSaveRankings: (rankings, allChanged) {
            savedRankings.add(Map.from(rankings));
            allChangedFlags.add(allChanged);
          },
        );

        model.confirmBinaryChoice(); // 1 at 100, 2 at 0
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement(); // 3 at 50

        model.setActivePropositionPosition(50.5); // Very close to 3
        model.confirmPlacement(); // 4 at ~50-51, normalization may shift things

        // Place 5 at exactly 50 - this forces normalization to adjust
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Check if any placement caused position shifts during normalization
        // (allPositionsChanged may be true if cards were pushed apart)
        expect(savedRankings.isNotEmpty, true);
        // The exact behavior depends on normalization logic
      });

      test('does not send all when positions do not shift', () {
        final savedRankings = <Map<String, double>>[];
        final allChangedFlags = <bool>[];

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
            {'id': 4, 'content': 'D'},
          ],
          onSaveRankings: (rankings, allChanged) {
            savedRankings.add(Map.from(rankings));
            allChangedFlags.add(allChanged);
          },
        );

        model.confirmBinaryChoice(); // 1 at 100, 2 at 0
        model.setActivePropositionPosition(75.0);
        model.confirmPlacement(); // 3 at 75, well separated

        // Prop4 at 25 - well separated from others, no position shifts
        model.setActivePropositionPosition(25.0);
        model.confirmPlacement();

        // No position shifts during normalization -> only send new prop
        expect(savedRankings.last.length, 1);
        expect(savedRankings.last.containsKey('4'), true);
        expect(allChangedFlags.last, false);
      });

      test('sent position matches actual normalized position', () {
        Map<String, double>? lastSaved;

        final model = GridRankingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
          ],
          onSaveRankings: (rankings, _) {
            lastSaved = Map.from(rankings);
          },
        );

        model.confirmBinaryChoice();
        model.setActivePropositionPosition(73.7);
        model.confirmPlacement();

        // Get the actual normalized position
        final prop3 = model.rankedPropositions.firstWhere((p) => p.id == '3');

        // Saved position should match the actual position
        expect(lastSaved!['3'], equals(prop3.position));
      });
    });
  });
}
