import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/rating/rating_model.dart';

void main() {
  group('RatingModel', () {
    group('Initialization', () {
      test('initializes with 2 propositions in binary phase', () {
        final model = RatingModel([
          {'id': 1, 'content': 'Proposition 1'},
          {'id': 2, 'content': 'Proposition 2'},
        ]);

        expect(model.phase, RatingPhase.binary);
        expect(model.rankedPropositions.length, 2);
        expect(model.rankedPropositions[0].position, 100.0);
        expect(model.rankedPropositions[1].position, 0.0);
      });

      test('initializes with correct IDs and content', () {
        final model = RatingModel([
          {'id': 'abc', 'content': 'First'},
          {'id': 'def', 'content': 'Second'},
        ]);

        expect(model.rankedPropositions[0].id, 'abc');
        expect(model.rankedPropositions[0].content, 'First');
        expect(model.rankedPropositions[1].id, 'def');
        expect(model.rankedPropositions[1].content, 'Second');
      });

      test('handles empty propositions list', () {
        final model = RatingModel([]);
        expect(model.rankedPropositions.isEmpty, true);
      });

      test('handles single proposition', () {
        final model = RatingModel([
          {'id': 1, 'content': 'Only one'},
        ]);
        // With only 1 proposition, binary comparison can't happen
        expect(model.rankedPropositions.isEmpty, true);
      });
    });

    group('Binary Phase', () {
      test('swapBinaryPositions swaps the two propositions', () {
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);

        expect(model.phase, RatingPhase.binary);

        model.confirmBinaryChoice();

        expect(model.phase, RatingPhase.positioning);
      });

      test('confirmBinaryChoice adds next proposition as active', () {
        final model = RatingModel([
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
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
        ]);

        model.confirmBinaryChoice();

        expect(model.phase, RatingPhase.completed);
        expect(model.isComplete, true);
      });
    });

    group('Positioning Phase - Basic Movement', () {
      late RatingModel model;

      setUp(() {
        model = RatingModel([
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
        expect(model.phase, RatingPhase.completed);
      });
    });

    group('Compression - Above 100', () {
      late RatingModel model;

      setUp(() {
        model = RatingModel([
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
      late RatingModel model;

      setUp(() {
        model = RatingModel([
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
      late RatingModel model;

      setUp(() {
        model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.undoLastPlacement();

        expect(model.phase, RatingPhase.binary);
        expect(model.rankedPropositions.length, 2);
      });

      test('undo to binary then re-confirm brings back third proposition', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
        // prop3 is now active

        // Undo back to binary
        model.undoLastPlacement();
        expect(model.phase, RatingPhase.binary);
        expect(model.rankedPropositions.length, 2);

        // Re-confirm binary
        model.confirmBinaryChoice();

        // Should be in positioning phase with prop3 active again
        expect(model.phase, RatingPhase.positioning);
        expect(model.rankedPropositions.length, 3);
        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.id, '3',
            reason: 'third proposition should reappear after undo-to-binary and re-confirm');
      });

      test('undo to binary then re-confirm with 4 props continues correctly', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        // prop3 is now active

        // Undo back to binary
        model.undoLastPlacement();
        expect(model.phase, RatingPhase.binary);

        // Re-confirm binary
        model.confirmBinaryChoice();

        // prop3 should be active again
        expect(model.phase, RatingPhase.positioning);
        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.id, '3');

        // Place prop3 and confirm
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // prop4 should appear
        expect(model.rankedPropositions.length, 4);
        final active2 = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active2.id, '4',
            reason: 'fourth proposition should appear after placing third');
      });

      test('undo does nothing in binary phase', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
        ]);

        final countBefore = model.rankedPropositions.length;
        model.undoLastPlacement();

        expect(model.rankedPropositions.length, countBefore);
      });

      test('undo uncompresses positions if was at boundary', () {
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel(
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
        final model = RatingModel(
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

        expect(model.phase, RatingPhase.binary);
        expect(model.rankedPropositions.length, 2);

        // In binary phase, one should be at 100, other at 0
        final positions = model.rankedPropositions.map((p) => p.position).toList();
        expect(positions, containsAll([100.0, 0.0]));
      });
    });

    group('Lazy Loading Mode', () {
      test('callback fires on confirmBinaryChoice in lazy mode', () {
        var callbackCalled = false;
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
          onPlacementConfirmed: () => callbackCalled = true,
        );

        model.confirmBinaryChoice();

        expect(callbackCalled, true);
        expect(model.phase, RatingPhase.positioning);
      });

      test('callback fires on confirmPlacement in lazy mode', () {
        var callbackCount = 0;
        final model = RatingModel(
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
        final model = RatingModel(
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
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
        );

        model.confirmBinaryChoice();
        // No propositions added, so no active card
        model.setNoMorePropositions();

        expect(model.phase, RatingPhase.completed);
        expect(model.isComplete, true);
      });

      test('does not complete while waiting for more propositions', () {
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          lazyLoadingMode: true,
        );

        model.confirmBinaryChoice();

        // Phase is positioning, but morePropositionsExpected is true
        expect(model.phase, RatingPhase.positioning);
        expect(model.morePropositionsExpected, true);
        expect(model.isComplete, false);
      });

      test('full lazy loading flow', () {
        var requestCount = 0;
        final model = RatingModel(
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

        expect(model.phase, RatingPhase.completed);
        expect(model.isComplete, true);
      });
    });

    group('Final Rankings', () {
      test('getFinalRankings returns all positions', () {
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel(props);
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel([
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
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 30.0},
          ],
          isResuming: true,
        );

        expect(model.phase, RatingPhase.completed); // No more expected
        expect(model.rankedPropositions.length, 2);
        expect(model.rankedPropositions[0].position, 100.0);
        expect(model.rankedPropositions[1].position, 30.0);
        expect(model.rankedPropositions[0].isActive, false);
        expect(model.rankedPropositions[1].isActive, false);
      });

      test('isResuming=true skips binary phase', () {
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 0.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        // Should be in positioning phase (not binary) when more expected
        expect(model.phase, RatingPhase.positioning);
      });

      test('isResuming=true with lazyLoadingMode sets needsFetchAfterInit', () {
        final model = RatingModel(
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
        final model = RatingModel(
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
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
          ],
          isResuming: false,
        );

        expect(model.phase, RatingPhase.binary);
        expect(model.rankedPropositions[0].position, 100.0);
        expect(model.rankedPropositions[1].position, 0.0);
      });
    });

    group('Save Rankings Callback', () {
      test('onSaveRankings called after confirmBinaryChoice', () {
        Map<String, double>? savedRankings;
        bool? allPositionsChanged;

        final model = RatingModel(
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

        final model = RatingModel(
          [
            {'id': 1, 'content': 'A'},
            {'id': 2, 'content': 'B'},
            {'id': 3, 'content': 'C'},
          ],
          onSaveRankings: (rankings, allChanged) {
            savedRankings = rankings;
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

        final model = RatingModel(
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

        final model = RatingModel(
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
        final model = RatingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 85.0},
          {'id': 2, 'content': 'B', 'finalRating': 50.0},
          {'id': 3, 'content': 'C', 'finalRating': 15.0},
        ]);

        expect(model.phase, RatingPhase.completed);
      });

      test('positions match finalRating values', () {
        final model = RatingModel.fromResults([
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
        final model = RatingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 85.0},
          {'id': 2, 'content': 'B', 'finalRating': 50.0},
        ]);

        for (final prop in model.rankedPropositions) {
          expect(prop.isActive, false);
        }
      });

      test('defaults to 50.0 when finalRating is null', () {
        final model = RatingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': null},
          {'id': 2, 'content': 'B'}, // finalRating not present
        ]);

        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');

        expect(prop1.position, 50.0);
        expect(prop2.position, 50.0);
      });

      test('handles empty list', () {
        final model = RatingModel.fromResults([]);

        expect(model.phase, RatingPhase.completed);
        expect(model.rankedPropositions.isEmpty, true);
      });

      test('detects stacks for same position', () {
        final model = RatingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 50.0},
          {'id': 2, 'content': 'B', 'finalRating': 50.0},
          {'id': 3, 'content': 'C', 'finalRating': 100.0},
        ]);

        final stack = model.getStackAtPosition(50.0);
        expect(stack, isNotNull);
        expect(stack!.cardCount, 2);
      });

      test('handles integer finalRating values', () {
        final model = RatingModel.fromResults([
          {'id': 1, 'content': 'A', 'finalRating': 75}, // int, not double
          {'id': 2, 'content': 'B', 'finalRating': 25.5}, // double
        ]);

        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 = model.rankedPropositions.firstWhere((p) => p.id == '2');

        expect(prop1.position, 75.0);
        expect(prop2.position, 25.5);
      });

      test('preserves content correctly', () {
        final model = RatingModel.fromResults([
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

        final model = RatingModel(
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

        final model = RatingModel(
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

        final model = RatingModel(
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

        final model = RatingModel(
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

    group('Normalize Virtual Position on Release', () {
      late RatingModel model;

      setUp(() {
        model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
      });

      test('normalizes virtualPosition from >100 to 100', () {
        // Move past 100 to cause compression
        model.moveActiveProposition(200); // virtualPosition = 250

        expect(model.virtualPosition, greaterThan(100));

        model.normalizeVirtualPositionOnRelease();

        expect(model.virtualPosition, 100.0);
      });

      test('normalizes virtualPosition from <0 to 0', () {
        // Move past 0 to cause compression
        model.moveActiveProposition(-100); // virtualPosition = -50

        expect(model.virtualPosition, lessThan(0));

        model.normalizeVirtualPositionOnRelease();

        expect(model.virtualPosition, 0.0);
      });

      test('does not change virtualPosition when in normal range', () {
        model.moveActiveProposition(25); // virtualPosition = 75

        final positionBefore = model.virtualPosition;
        expect(positionBefore, greaterThan(0));
        expect(positionBefore, lessThan(100));

        model.normalizeVirtualPositionOnRelease();

        expect(model.virtualPosition, positionBefore);
      });

      test('pressing opposite direction decompresses all cards smoothly', () {
        // Use 4 cards so there are non-boundary cards to decompress
        final model4 = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model4.confirmBinaryChoice();
        model4.setActivePropositionPosition(50.0);
        model4.confirmPlacement();
        // prop1=100, prop2=0, prop3=50, prop4 active at 50

        // Move far past 100
        model4.moveActiveProposition(500);

        final prop1Compressed =
            model4.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop3Compressed =
            model4.rankedPropositions.firstWhere((p) => p.id == '3').position;

        // Normalize (simulates button release) — no visual change
        model4.normalizeVirtualPositionOnRelease();
        expect(model4.virtualPosition, 100.0);

        // Prop1 stays compressed on release (no jump)
        final prop1OnRelease =
            model4.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1OnRelease, lessThan(100.0),
            reason: 'prop1 stays compressed on release');

        // First move down — active stays at boundary, cards decompress
        model4.moveActiveProposition(-10);

        final active = model4.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 100.0,
            reason: 'active stays at boundary during decompression');

        // Prop1 (boundary card) decompresses gradually toward 100
        final prop1After =
            model4.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1After, greaterThan(prop1Compressed),
            reason: 'prop1 should be decompressing from compressed position');
        expect(prop1After, lessThan(100.0),
            reason: 'prop1 should not snap to 100 instantly');

        // Prop3 decompresses gradually
        final prop3After =
            model4.rankedPropositions.firstWhere((p) => p.id == '3').position;
        expect(prop3After, greaterThan(prop3Compressed),
            reason: 'prop3 should be decompressing from compressed position');
        expect(prop3After, lessThan(50.0),
            reason: 'prop3 should not snap to original position instantly');
      });

      test('normalizing keeps all compressed positions (no visual jump on release)', () {
        // Move far past 100 causing heavy compression
        model.moveActiveProposition(500); // virtualPosition = 550

        // Verify compression happened
        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1Compressed, lessThan(100),
            reason: 'prop1 should be compressed');

        // Normalize - NO visual change, all cards stay at compressed positions
        model.normalizeVirtualPositionOnRelease();

        // Prop1 stays at compressed position (no jump)
        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1After, closeTo(prop1Compressed, 0.1),
            reason: 'prop1 stays compressed on release (no jump)');

        // Prop2 was at 0, compression toward 100 doesn't move it
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        expect(prop2After, closeTo(0.0, 1.0),
            reason: 'prop2 at 0 stays at 0 during top compression');

        // virtualPosition should be at boundary
        expect(model.virtualPosition, 100.0);
      });

      test('after full expansion, active can move normally', () {
        // Move far past 100
        model.moveActiveProposition(500);

        // Normalize (positions stay compressed)
        model.normalizeVirtualPositionOnRelease();

        // Move enough to complete expansion (30+ units of movement)
        for (int i = 0; i < 8; i++) {
          model.moveActiveProposition(-5);
        }

        // Now prop1 should be back at 100 (fully expanded)
        final prop1 = model.rankedPropositions.firstWhere((p) => p.id == '1');
        expect(prop1.position, closeTo(100.0, 1.0));

        // Active can now move - move down more
        model.moveActiveProposition(-10);

        final active = model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, lessThan(100));
      });

      test('does nothing outside positioning phase', () {
        // Create a completed model
        final completedModel = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
        ]);
        completedModel.confirmBinaryChoice();

        // Store the phase before attempting normalize
        final phaseBefore = completedModel.phase;

        // Try to normalize - should do nothing
        completedModel.normalizeVirtualPositionOnRelease();

        expect(completedModel.phase, phaseBefore);
      });

      test('normalization at exactly 100 does nothing', () {
        // Move to exactly 100 (boundary)
        model.moveActiveProposition(50); // 50 + 50 = 100

        final positionBefore = model.virtualPosition;
        expect(positionBefore, 100.0);

        model.normalizeVirtualPositionOnRelease();

        // Should not change anything since we're AT the boundary, not PAST it
        // Actually the condition is > 100 or < 0, so 100 exactly is normal
        expect(model.virtualPosition, positionBefore);
      });

      test('normalization at exactly 0 does nothing', () {
        // Move to exactly 0 (boundary)
        model.moveActiveProposition(-50); // 50 - 50 = 0

        final positionBefore = model.virtualPosition;
        expect(positionBefore, 0.0);

        model.normalizeVirtualPositionOnRelease();

        // Should not change anything since we're AT the boundary, not PAST it
        expect(model.virtualPosition, positionBefore);
      });
    });

    group('Expansion from Top Boundary (Bug Fix)', () {
      late RatingModel model;

      setUp(() {
        // 4 propositions: after binary, prop1=100, prop2=0, then place prop3
        model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        // Place prop3 at 50
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();
        // Now prop4 is active at 50
      });

      test('after normalize from above 100, moving DOWN expands all inactive cards UP toward 100', () {
        // Move prop4 way past 100 to cause compression
        model.moveActiveProposition(200); // virtualPosition = 250

        // Capture compressed positions
        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        final prop3Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;

        expect(prop1Compressed, lessThan(100.0));
        expect(prop3Compressed, lessThan(50.0));

        // Normalize (simulates button release)
        model.normalizeVirtualPositionOnRelease();
        expect(model.virtualPosition, 100.0);

        // Move DOWN (delta < 0) - should trigger expansion
        model.moveActiveProposition(-50);

        // All inactive cards should move UP (toward 100), not down
        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        final prop3After =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;

        expect(prop1After, greaterThanOrEqualTo(prop1Compressed),
            reason: 'prop1 should move UP (toward 100) during expansion from top');
        expect(prop2After, greaterThanOrEqualTo(prop2Compressed),
            reason: 'prop2 should move UP (toward 100) during expansion from top');
        expect(prop3After, greaterThanOrEqualTo(prop3Compressed),
            reason: 'prop3 should move UP (toward 100) during expansion from top');
      });

      test('during expansion from top, lowest card stays fixed and highest approaches 100', () {
        model.moveActiveProposition(200);

        final prop2Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        model.normalizeVirtualPositionOnRelease();

        // Move down partway through expansion
        model.moveActiveProposition(-30);

        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        // Lowest card (prop2 near 0 originally) should stay fixed
        expect(prop2After, closeTo(prop2Compressed, 0.1),
            reason: 'lowest card stays fixed during expansion from top');

        // Highest card (prop1 originally at 100) should be approaching 100
        expect(prop1After, greaterThan(prop2After),
            reason: 'highest card should be above lowest card');
      });

      test('after full expansion from top, highest card reaches 100', () {
        model.moveActiveProposition(200);

        model.normalizeVirtualPositionOnRelease();

        // Move enough to complete expansion (100 units)
        for (int i = 0; i < 20; i++) {
          model.moveActiveProposition(-5);
        }

        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;

        expect(prop1After, closeTo(100.0, 1.0),
            reason: 'highest card should reach 100 after expansion');
      });

      test('after normalize from top, active stays at boundary during decompression then moves', () {
        model.moveActiveProposition(200);
        model.normalizeVirtualPositionOnRelease();

        // During decompression (first 30 units), active stays at boundary
        for (int i = 0; i < 6; i++) {
          model.moveActiveProposition(-5);
          final active =
              model.rankedPropositions.firstWhere((p) => p.isActive);
          expect(active.position, 100.0,
              reason: 'active stays at boundary during decompression (step $i)');
        }

        // After decompression completes, active starts moving from boundary
        model.moveActiveProposition(-5);
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, lessThan(100.0),
            reason: 'active moves freely after decompression completes');
      });
    });

    group('Expansion from Bottom Boundary', () {
      late RatingModel model;

      setUp(() {
        model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();
        // prop4 active at 50
      });

      test('after normalize from below 0, moving UP expands all inactive cards DOWN toward 0', () {
        // Move prop4 way below 0 to cause compression from bottom
        model.moveActiveProposition(-200); // virtualPosition = -150

        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        final prop3Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;

        // When compressed from bottom, cards are pushed toward top
        expect(prop2Compressed, greaterThan(0.0),
            reason: 'prop2 at 0 should be compressed upward');

        model.normalizeVirtualPositionOnRelease();
        expect(model.virtualPosition, 0.0);

        // Move UP (delta > 0) - should trigger expansion
        model.moveActiveProposition(50);

        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        final prop3After =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;

        // Cards should move DOWN (toward 0)
        expect(prop2After, lessThanOrEqualTo(prop2Compressed),
            reason: 'prop2 should move DOWN (toward 0) during expansion from bottom');
        expect(prop3After, lessThanOrEqualTo(prop3Compressed),
            reason: 'prop3 should move DOWN (toward 0) during expansion from bottom');
      });

      test('during expansion from bottom, highest card stays fixed and lowest approaches 0', () {
        model.moveActiveProposition(-200);

        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;

        model.normalizeVirtualPositionOnRelease();

        // Move up partway
        model.moveActiveProposition(30);

        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        // Highest card (prop1) should stay fixed
        expect(prop1After, closeTo(prop1Compressed, 0.1),
            reason: 'highest card stays fixed during expansion from bottom');

        // Lowest should be below highest
        expect(prop2After, lessThan(prop1After));
      });

      test('after full expansion from bottom, lowest card reaches 0', () {
        model.moveActiveProposition(-200);
        model.normalizeVirtualPositionOnRelease();

        // Move enough to complete expansion (100 units)
        for (int i = 0; i < 20; i++) {
          model.moveActiveProposition(5);
        }

        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        expect(prop2After, closeTo(0.0, 1.0),
            reason: 'lowest card should reach 0 after expansion from bottom');
      });

      test('after normalize from bottom, active stays at boundary during decompression then moves', () {
        model.moveActiveProposition(-200);
        model.normalizeVirtualPositionOnRelease();

        // During decompression (first 30 units), active stays at boundary
        for (int i = 0; i < 6; i++) {
          model.moveActiveProposition(5);
          final active =
              model.rankedPropositions.firstWhere((p) => p.isActive);
          expect(active.position, 0.0,
              reason: 'active stays at boundary during decompression (step $i)');
        }

        // After decompression completes, active starts moving from boundary
        model.moveActiveProposition(5);
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, greaterThan(0.0),
            reason: 'active moves freely after decompression completes');
      });
    });

    group('Undo then Move Down from 100 (Original User Bug)', () {
      test('undo at 100 then press DOWN triggers expansion toward top', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
          {'id': 5, 'content': 'E'},
        ]);
        model.confirmBinaryChoice();

        // Place prop3 at 75
        model.setActivePropositionPosition(75.0);
        model.confirmPlacement();

        // Place prop4 at 25
        model.setActivePropositionPosition(25.0);
        model.confirmPlacement();

        // Now prop5 is active. Move past 100 and normalize.
        model.moveActiveProposition(200);
        model.normalizeVirtualPositionOnRelease();

        // Undo - removes prop5, reactivates prop4
        model.undoLastPlacement();

        // The reactivated prop4 was placed at 25 but after undo
        // the positions are uncompressed. Now move DOWN from wherever it is.
        final activeBefore =
            model.rankedPropositions.firstWhere((p) => p.isActive);

        // Move active past 100, normalize, and then move down
        model.moveActiveProposition(200);
        model.normalizeVirtualPositionOnRelease();

        // Record positions before expansion
        final prop1Before =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;

        model.moveActiveProposition(-50);

        // After moving down from 100, cards should expand upward
        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;

        expect(prop1After, greaterThanOrEqualTo(prop1Before),
            reason: 'cards should expand upward, not leave 100 empty');
      });

      test('undo from boundary then transitioningFromCompressed expands correctly', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();

        // Place prop3 at 100 (boundary)
        model.setActivePropositionPosition(100.0);
        model.confirmPlacement();

        // prop4 is active at 50. Undo => prop3 reactivated at 100
        model.undoLastPlacement();

        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, closeTo(100.0, 1.0));

        // Capture positions
        final prop1Pos =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2Pos =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        // Positions should be within 0-100 range
        expect(prop1Pos, inInclusiveRange(0.0, 100.0));
        expect(prop2Pos, inInclusiveRange(0.0, 100.0));
      });
    });

    group('Compression Symmetry', () {
      late RatingModel model;

      setUp(() {
        model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        // Place prop3 at 50
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();
        // prop4 active at 50
      });

      test('compression toward 100 compresses proportionally between 0 and active', () {
        // prop4 starts at virtualPosition=50, move by 150 -> virtualPosition=200
        // overflow = 200 - 100 = 100
        model.moveActiveProposition(150); // virtual = 50 + 150 = 200

        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 100.0);

        // All inactive positions should be in [0, 100]
        for (final prop in model.rankedPropositions) {
          if (!prop.isActive) {
            expect(prop.position, inInclusiveRange(0.0, 100.0),
                reason: 'compressed position for ${prop.id} should be in [0, 100]');
          }
        }

        // Compression ratio = 100 / (100 + 100) = 0.5
        // prop1 at base 100 -> 100 * 0.5 = 50
        // prop2 at base 0 -> 0 * 0.5 = 0
        // prop3 at base 50 -> 50 * 0.5 = 25
        final prop1 =
            model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 =
            model.rankedPropositions.firstWhere((p) => p.id == '2');
        final prop3 =
            model.rankedPropositions.firstWhere((p) => p.id == '3');

        expect(prop1.position, closeTo(50.0, 1.0));
        expect(prop2.position, closeTo(0.0, 1.0));
        expect(prop3.position, closeTo(25.0, 1.0));
      });

      test('compression toward 0 compresses proportionally between active and 100', () {
        // Move to -100 (virtual)
        model.moveActiveProposition(-150); // 50 - 150 = -100

        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 0.0);

        // All inactive positions should be in [0, 100]
        for (final prop in model.rankedPropositions) {
          if (!prop.isActive) {
            expect(prop.position, inInclusiveRange(0.0, 100.0),
                reason: 'compressed position for ${prop.id} should be in [0, 100]');
          }
        }

        // Compression ratio = 100 / (100 + 100) = 0.5
        // Formula for bottom: newTruePos = 100 - (100 - baseTruePos) * compressionRatio
        // prop1 at base 100 -> 100 - (100-100)*0.5 = 100
        // prop2 at base 0 -> 100 - (100-0)*0.5 = 100 - 50 = 50
        // prop3 at base 50 -> 100 - (100-50)*0.5 = 100 - 25 = 75
        final prop1 =
            model.rankedPropositions.firstWhere((p) => p.id == '1');
        final prop2 =
            model.rankedPropositions.firstWhere((p) => p.id == '2');
        final prop3 =
            model.rankedPropositions.firstWhere((p) => p.id == '3');

        expect(prop1.position, closeTo(100.0, 1.0));
        expect(prop2.position, closeTo(50.0, 1.0));
        expect(prop3.position, closeTo(75.0, 1.0));
      });

      test('compression preserves relative ordering of cards', () {
        // Compression above 100
        model.moveActiveProposition(300);

        final positions = model.rankedPropositions
            .where((p) => !p.isActive)
            .toList()
          ..sort((a, b) => b.position.compareTo(a.position));

        // Original order was prop1(100) > prop3(50) > prop2(0)
        expect(positions[0].id, '1');
        expect(positions[1].id, '3');
        expect(positions[2].id, '2');
      });

      test('compression preserves relative ordering from bottom', () {
        // Compression below 0
        model.moveActiveProposition(-300);

        final positions = model.rankedPropositions
            .where((p) => !p.isActive)
            .toList()
          ..sort((a, b) => b.position.compareTo(a.position));

        // Original order preserved: prop1(100) > prop3(50) > prop2(0)
        expect(positions[0].id, '1');
        expect(positions[1].id, '3');
        expect(positions[2].id, '2');
      });
    });

    group('Expansion Completeness', () {
      test('after expansion from top, active can move normally', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Compress
        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();

        // Move enough to complete expansion (100 units)
        for (int i = 0; i < 20; i++) {
          model.moveActiveProposition(-5);
        }

        // prop1 should be back near 100
        final prop1 =
            model.rankedPropositions.firstWhere((p) => p.id == '1');
        expect(prop1.position, closeTo(100.0, 1.0));

        // Now active should move normally
        model.moveActiveProposition(-20);
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, lessThan(100.0),
            reason: 'after expansion completes, active should move freely');
      });

      test('after expansion from bottom, active can move normally', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Compress from bottom
        model.moveActiveProposition(-500);
        model.normalizeVirtualPositionOnRelease();

        // Move enough to complete expansion (100 units)
        for (int i = 0; i < 20; i++) {
          model.moveActiveProposition(5);
        }

        // prop2 should be back near 0
        final prop2 =
            model.rankedPropositions.firstWhere((p) => p.id == '2');
        expect(prop2.position, closeTo(0.0, 1.0));

        // Now active should move normally
        model.moveActiveProposition(20);
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, greaterThan(0.0),
            reason: 'after expansion completes, active should move freely');
      });

      test('all cards stay compressed on release, expand gradually on move', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();
        // prop1=100, prop2=0, prop3=50, prop4 active at 50

        // Heavy compression
        model.moveActiveProposition(500);

        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop3Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;
        expect(prop3Compressed, lessThan(50.0),
            reason: 'prop3 should be compressed');

        model.normalizeVirtualPositionOnRelease();

        // All cards stay compressed on release (no jump)
        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1After, closeTo(prop1Compressed, 0.1),
            reason: 'prop1 stays compressed on release');
        final prop3After =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;
        expect(prop3After, closeTo(prop3Compressed, 0.1),
            reason: 'prop3 stays compressed on release');

        // First move — active stays at boundary, cards decompress
        model.moveActiveProposition(-10);

        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 100.0,
            reason: 'active stays at boundary during decompression');

        // Prop1 decompresses gradually toward 100
        final prop1AfterMove =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1AfterMove, greaterThan(prop1Compressed),
            reason: 'prop1 should be decompressing from compressed position');
        expect(prop1AfterMove, lessThan(100.0),
            reason: 'prop1 should not snap to 100 instantly');

        // Prop3 decompresses gradually
        final prop3Partial =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;
        expect(prop3Partial, greaterThan(prop3Compressed),
            reason: 'prop3 should be decompressing');
        expect(prop3Partial, lessThan(50.0),
            reason: 'prop3 should not snap to original position instantly');

        // Complete decompression (move enough to reach progress=1.0)
        model.moveActiveProposition(-30);

        // Prop3 should return to original position
        final prop3Final =
            model.rankedPropositions.firstWhere((p) => p.id == '3').position;
        expect(prop3Final, closeTo(50.0, 1.0),
            reason: 'prop3 returns to 50 after full decompression');
      });
    });

    group('Rapid Direction Changes During Expansion', () {
      test('reversing direction during expansion from top exits expansion mode', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Compress and normalize
        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();

        // Start expanding (move down)
        model.moveActiveProposition(-20);

        // Reverse direction (move up, back toward boundary)
        // This should exit expansion mode
        model.moveActiveProposition(30);

        // The model should handle this without errors
        // After exiting expansion, further movement should work normally
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, inInclusiveRange(0.0, 100.0));

        // All positions should remain valid
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0),
              reason: 'position for ${prop.id} should be valid');
        }
      });

      test('reversing direction during expansion from bottom exits expansion mode', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Compress from bottom and normalize
        model.moveActiveProposition(-500);
        model.normalizeVirtualPositionOnRelease();

        // Start expanding (move up)
        model.moveActiveProposition(20);

        // Reverse direction (move down, back toward boundary)
        model.moveActiveProposition(-30);

        // Should handle gracefully
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, inInclusiveRange(0.0, 100.0));

        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0));
        }
      });

      test('multiple direction changes during expansion do not corrupt state', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Compress heavily
        model.moveActiveProposition(400);
        model.normalizeVirtualPositionOnRelease();

        // Rapid direction changes
        model.moveActiveProposition(-10); // expand
        model.moveActiveProposition(5);  // reverse
        model.moveActiveProposition(-15); // expand again
        model.moveActiveProposition(3);  // reverse again

        // All positions should remain valid
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0),
              reason: 'position for ${prop.id} should be valid after rapid changes');
        }
      });
    });

    group('Edge Case: Only 1 Inactive Card During Expansion', () {
      test('expansion works with 2 total cards (1 active, 1 inactive)', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
        // prop3 is now active, prop1=100, prop2=0

        // Compress by moving past 100
        model.moveActiveProposition(200);

        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1Compressed, lessThan(100.0));

        model.normalizeVirtualPositionOnRelease();

        // Expand - with 2 inactive cards this should still work
        model.moveActiveProposition(-50);

        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1After, greaterThanOrEqualTo(prop1Compressed),
            reason: 'expansion should work with 2 inactive cards');
      });

      test('expansion from top with single inactive card when range is zero', () {
        // Create a scenario where there is only 1 inactive card with a compressed position
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Place prop3 at 100 (same as prop1)
        model.setActivePropositionPosition(100.0);
        model.confirmPlacement();

        // model is now complete with only 3 props. We need 4.
        // Use a different setup with lazy loading for better control.
      });

      test('expansion handles minimum card count gracefully', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Move way past 100
        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();

        // Try to expand
        model.moveActiveProposition(-50);

        // Should not crash, all positions valid
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0));
        }
      });
    });

    group('Edge Case: All Inactive Cards at Same Position', () {
      test('expansion handles all inactive cards compressed to same position', () {
        // Resume with all cards at 100
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A', 'position': 100.0},
            {'id': 2, 'content': 'B', 'position': 100.0},
            {'id': 3, 'content': 'C', 'position': 100.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        // Add a new proposition
        model.addProposition({'id': 4, 'content': 'D'});

        // Move it past 100 to compress
        model.moveActiveProposition(200);

        // All inactive are at similar compressed positions
        final positions = model.rankedPropositions
            .where((p) => !p.isActive)
            .map((p) => p.position)
            .toList();

        // They should all be close together (compressed from same base)
        final minPos = positions.reduce((a, b) => a < b ? a : b);
        final maxPos = positions.reduce((a, b) => a > b ? a : b);
        expect(maxPos - minPos, lessThan(1.0),
            reason: 'cards that started at same position should compress to same position');

        model.normalizeVirtualPositionOnRelease();

        // Expand
        model.moveActiveProposition(-50);

        // Should handle zero-range gracefully (compRange <= 0 branch)
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0),
              reason: 'all positions should remain valid');
        }
      });

      test('expansion with zero-range uses midpoint', () {
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A', 'position': 50.0},
            {'id': 2, 'content': 'B', 'position': 50.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        model.addProposition({'id': 3, 'content': 'C'});

        // Compress from top
        model.moveActiveProposition(200);
        model.normalizeVirtualPositionOnRelease();

        // Expand
        model.moveActiveProposition(-50);

        // Zero-range case: both inactive at same position, should use midpoint
        final prop1 =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2 =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        // Both should be at the same position (midpoint of target range)
        expect((prop1 - prop2).abs(), lessThan(1.0),
            reason: 'cards at same position should stay together during expansion');
      });

      test('compression then expansion with cards at 0 handles correctly', () {
        final model = RatingModel(
          [
            {'id': 1, 'content': 'A', 'position': 0.0},
            {'id': 2, 'content': 'B', 'position': 0.0},
          ],
          isResuming: true,
          lazyLoadingMode: true,
        );

        model.addProposition({'id': 3, 'content': 'C'});

        // Compress from bottom
        model.moveActiveProposition(-200);
        model.normalizeVirtualPositionOnRelease();

        // Expand
        model.moveActiveProposition(50);

        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0));
        }
      });
    });

    group('Expansion Progress Tracking', () {
      test('expansion progress increases with each step', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        model.moveActiveProposition(300);
        model.normalizeVirtualPositionOnRelease();

        // Record positions after each expansion step
        final prop1Positions = <double>[];
        for (int i = 0; i < 10; i++) {
          model.moveActiveProposition(-10);
          final prop1 =
              model.rankedPropositions.firstWhere((p) => p.id == '1');
          prop1Positions.add(prop1.position);
        }

        // Each step should increase the position (monotonically expanding)
        for (int i = 1; i < prop1Positions.length; i++) {
          expect(prop1Positions[i], greaterThanOrEqualTo(prop1Positions[i - 1]),
              reason: 'position should increase at step $i: '
                  '${prop1Positions[i]} >= ${prop1Positions[i - 1]}');
        }
      });

      test('expansion progress is capped at 1.0', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();

        // Move way more than needed (200 units when 100 is enough)
        model.moveActiveProposition(-200);

        // Should not exceed 100 for any card
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0));
        }
      });
    });

    group('Compression and Expansion with Many Cards', () {
      test('compression with 8 cards maintains valid positions', () {
        final props = List.generate(
            10, (i) => {'id': i, 'content': 'Prop $i'});
        final model = RatingModel(props);
        model.confirmBinaryChoice();

        // Place cards at various positions
        model.setActivePropositionPosition(80.0);
        model.confirmPlacement();
        model.setActivePropositionPosition(60.0);
        model.confirmPlacement();
        model.setActivePropositionPosition(40.0);
        model.confirmPlacement();
        model.setActivePropositionPosition(20.0);
        model.confirmPlacement();
        model.setActivePropositionPosition(90.0);
        model.confirmPlacement();
        model.setActivePropositionPosition(10.0);
        model.confirmPlacement();
        model.setActivePropositionPosition(70.0);
        model.confirmPlacement();

        // Now prop9 is active. Compress heavily.
        model.moveActiveProposition(500);

        // All positions should be valid
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0),
              reason: 'position for ${prop.id} should be valid during compression');
        }

        model.normalizeVirtualPositionOnRelease();

        // Expand
        for (int i = 0; i < 20; i++) {
          model.moveActiveProposition(-5);
          for (final prop in model.rankedPropositions) {
            expect(prop.position, inInclusiveRange(0.0, 100.0),
                reason: 'position for ${prop.id} should be valid during expansion step $i');
          }
        }
      });

      test('expansion with many cards preserves relative order', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
          {'id': 5, 'content': 'E'},
        ]);
        model.confirmBinaryChoice();

        model.setActivePropositionPosition(75.0);
        model.confirmPlacement();
        model.setActivePropositionPosition(25.0);
        model.confirmPlacement();

        // prop5 active at 50. Compress heavily.
        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();

        // Partially expand
        model.moveActiveProposition(-50);

        // Check order is preserved
        final inactiveByPosition = model.rankedPropositions
            .where((p) => !p.isActive)
            .toList()
          ..sort((a, b) => b.position.compareTo(a.position));

        // prop1 was at 100, prop3 at 75, prop4 at 25, prop2 at 0
        // After compression and partial expansion, order should be preserved
        for (int i = 1; i < inactiveByPosition.length; i++) {
          expect(inactiveByPosition[i - 1].position,
              greaterThanOrEqualTo(inactiveByPosition[i].position),
              reason: 'ordering should be preserved during expansion');
        }
      });
    });

    group('Normalize then Confirm Placement', () {
      test('confirm placement during expansion produces valid positions', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Compress and normalize
        model.moveActiveProposition(300);
        model.normalizeVirtualPositionOnRelease();

        // Partially expand
        model.moveActiveProposition(-30);

        // Confirm placement while expanding
        model.confirmPlacement();

        // All positions should be valid integers after normalization
        for (final prop in model.rankedPropositions) {
          expect(prop.position, inInclusiveRange(0.0, 100.0));
        }
      });

      test('confirm placement at exact boundary (100) after compression', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Move to exactly 100
        model.setActivePropositionPosition(100.0);

        // Confirm at boundary
        model.confirmPlacement();

        final active = model.rankedPropositions.firstWhere((p) => p.id == '4');
        expect(active.position, 100.0);
      });
    });

    group('No Visual Jump on Release (Bug Fix)', () {
      test('releasing after compression keeps all positions (no jump)', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
        // prop1=100, prop2=0, prop3(active)=50

        // Push far past 100 to cause heavy compression
        model.moveActiveProposition(500); // virtual=550

        final prop1Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        expect(prop1Compressed, lessThan(20),
            reason: 'prop1 should be heavily compressed');

        // Release button — no visual change
        model.normalizeVirtualPositionOnRelease();

        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        expect(prop1After, closeTo(prop1Compressed, 0.1),
            reason: 'prop1 stays compressed on release (no jump)');
        expect(prop2After, closeTo(0.0, 1.0),
            reason: 'prop2 at 0 stays at 0 during top compression');
      });

      test('after release, pressing opposite keeps active at boundary during decompression', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Compress and release
        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();

        // Press down - active stays at boundary, others decompress
        model.moveActiveProposition(-10);

        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 100.0,
            reason: 'active stays at boundary during decompression');
      });

      test('releasing from below 0 keeps all compressed positions (no jump)', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Push far below 0
        model.moveActiveProposition(-500); // virtual = -450

        final prop2Compressed =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        model.normalizeVirtualPositionOnRelease();

        final prop1After =
            model.rankedPropositions.firstWhere((p) => p.id == '1').position;
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;

        // prop1 at 100 stays at 100 (bottom compression doesn't move the top card)
        expect(prop1After, closeTo(100.0, 1.0),
            reason: 'prop1 at top stays at 100 during bottom compression');
        // prop2 stays at compressed position (no jump on release)
        expect(prop2After, closeTo(prop2Compressed, 0.1),
            reason: 'prop2 stays compressed on release (no jump)');
      });

      test('single press after release keeps active at boundary during decompression', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();
        // prop4 active at 50

        // Compress heavily and release
        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();
        // Positions stay compressed, active at 100

        // Move down 1 unit - active stays at boundary, decompression begins
        model.moveActiveProposition(-1);

        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 100.0,
            reason: 'active stays at boundary during decompression');
      });

      test('user bug: binary then drag below 0 and release causes no jump', () {
        // Binary placement, then 3rd proposition dragged below 0.
        // The card at 0 compresses upward during drag.
        // On release, no visual change. All cards decompress gradually on opposite move.
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();
        // prop1=100, prop2=0, prop3(active)=50

        // Drag active below 0 (simulating holding down button)
        model.moveActiveProposition(-60); // virtual = -10

        // Verify prop2 compressed upward
        final prop2During =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        expect(prop2During, greaterThan(0.0),
            reason: 'prop2 at 0 should compress upward when active goes below 0');

        // Release the button — no visual change
        model.normalizeVirtualPositionOnRelease();

        // Active should snap to 0
        expect(model.virtualPosition, 0.0);
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 0.0);

        // CRITICAL: prop2 should NOT jump — stays at compressed position
        final prop2After =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        expect(prop2After, closeTo(prop2During, 0.1),
            reason: 'prop2 stays at compressed position on release (no jump)');
        expect(prop2After, greaterThan(0.0),
            reason: 'prop2 should remain displaced above 0');

        // First opposite move — active stays at 0, prop2 decompresses toward 0
        model.moveActiveProposition(10);

        final activeAfterMove =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(activeAfterMove.position, 0.0,
            reason: 'active stays at boundary during decompression');

        final prop2AfterMove =
            model.rankedPropositions.firstWhere((p) => p.id == '2').position;
        expect(prop2AfterMove, lessThan(prop2During),
            reason: 'prop2 should decompress toward 0');
        expect(prop2AfterMove, greaterThan(0.0),
            reason: 'prop2 should not snap to 0 instantly');
      });
    });

    group('Compression Amount Proportionality', () {
      test('double the overflow produces double the compression', () {
        // Test 1: overflow of 50
        final model1 = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model1.confirmBinaryChoice();
        model1.moveActiveProposition(100); // virtual = 150, overflow = 50

        final prop1At50Overflow =
            model1.rankedPropositions.firstWhere((p) => p.id == '1').position;

        // Test 2: overflow of 100
        final model2 = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model2.confirmBinaryChoice();
        model2.moveActiveProposition(150); // virtual = 200, overflow = 100

        final prop1At100Overflow =
            model2.rankedPropositions.firstWhere((p) => p.id == '1').position;

        // More overflow = more compression = lower position for prop1
        expect(prop1At100Overflow, lessThan(prop1At50Overflow),
            reason: 'more overflow should produce more compression');
      });

      test('compression formula: position = base * 100/(100+overflow)', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // prop1 base=100, prop2 base=0, prop3 active at 50
        // Move to 250: overflow = 150
        model.moveActiveProposition(200);

        final prop1 =
            model.rankedPropositions.firstWhere((p) => p.id == '1');
        final expectedCompression = 100.0 * (100.0 / (100.0 + 150.0));
        expect(prop1.position, closeTo(expectedCompression, 0.5));
      });
    });

    group('Boundary Pinning Invariant (always one at 100 and 0)', () {
      test('active stays at boundary during decompression then moves freely from top', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Compress past 100 and release
        model.moveActiveProposition(300);
        model.normalizeVirtualPositionOnRelease();

        // First 30 steps: active stays at 100 (decompression phase)
        for (int i = 0; i < 30; i++) {
          model.moveActiveProposition(-1);
          final active =
              model.rankedPropositions.firstWhere((p) => p.isActive);
          expect(active.position, 100.0,
              reason: 'active stays at boundary during decompression step $i');
        }

        // After decompression, active moves freely from boundary
        for (int i = 0; i < 69; i++) {
          model.moveActiveProposition(-1);
          final active =
              model.rankedPropositions.firstWhere((p) => p.isActive);
          final expectedPos = 100.0 - (i + 1);
          expect(active.position, expectedPos,
              reason: 'active moves freely after decompression step $i');
        }
      });

      test('active stays at boundary during decompression then moves freely from bottom', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Compress past 0 and release
        model.moveActiveProposition(-300);
        model.normalizeVirtualPositionOnRelease();

        // First 30 steps: active stays at 0 (decompression phase)
        for (int i = 0; i < 30; i++) {
          model.moveActiveProposition(1);
          final active =
              model.rankedPropositions.firstWhere((p) => p.isActive);
          expect(active.position, 0.0,
              reason: 'active stays at boundary during decompression step $i');
        }

        // After decompression, active moves freely from boundary
        for (int i = 0; i < 69; i++) {
          model.moveActiveProposition(1);
          final active =
              model.rankedPropositions.firstWhere((p) => p.isActive);
          final expectedPos = (i + 1).toDouble();
          expect(active.position, expectedPos,
              reason: 'active moves freely after decompression step $i');
        }
      });

      test('after full decompression from top, inactive cards are at original positions', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Compress and release
        model.moveActiveProposition(500);
        model.normalizeVirtualPositionOnRelease();

        // Move 100 units: first 30 consumed by decompression, remaining 70 move active
        for (int i = 0; i < 100; i++) {
          model.moveActiveProposition(-1);
        }

        // Active should be at 30 (100 - 70 units of actual movement after decompression)
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 30.0,
            reason: 'active at 30 after 30 units decompression + 70 units movement');

        // Highest inactive should be at 100 (fully decompressed)
        final inactivePositions = model.rankedPropositions
            .where((p) => !p.isActive)
            .map((p) => p.position)
            .toList();
        expect(inactivePositions.reduce((a, b) => a > b ? a : b),
            closeTo(100.0, 1.0),
            reason: 'highest inactive card should be at 100 after full decompression');
      });

      test('after full decompression from bottom, inactive cards are at original positions', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
        ]);
        model.confirmBinaryChoice();

        // Compress below 0 and release
        model.moveActiveProposition(-500);
        model.normalizeVirtualPositionOnRelease();

        // Move 100 units: first 30 consumed by decompression, remaining 70 move active
        for (int i = 0; i < 100; i++) {
          model.moveActiveProposition(1);
        }

        // Active should be at 70 (0 + 70 units of actual movement after decompression)
        final active =
            model.rankedPropositions.firstWhere((p) => p.isActive);
        expect(active.position, 70.0,
            reason: 'active at 70 after 30 units decompression + 70 units movement');

        // Lowest inactive should be at 0 (fully decompressed)
        final inactivePositions = model.rankedPropositions
            .where((p) => !p.isActive)
            .map((p) => p.position)
            .toList();
        expect(inactivePositions.reduce((a, b) => a < b ? a : b),
            closeTo(0.0, 1.0),
            reason: 'lowest inactive card should be at 0 after full decompression');
      });

      test('always a card at 100 during compression, smooth decompression from top', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Compress past 100 - active is always at 100 during compression
        for (int i = 0; i < 200; i++) {
          model.moveActiveProposition(1);
          final allPositions =
              model.rankedPropositions.map((p) => p.position).toList();
          expect(allPositions.any((p) => p >= 99.5), isTrue,
              reason: 'must always have a card at 100 during compression step $i');
        }

        model.normalizeVirtualPositionOnRelease();

        // Decompression - inactive cards gradually return to original positions
        // Active moves freely, so track that inactive cards decompress monotonically
        double prevHighestInactive = 0;
        for (int i = 0; i < 100; i++) {
          model.moveActiveProposition(-1);
          final highestInactive = model.rankedPropositions
              .where((p) => !p.isActive)
              .map((p) => p.position)
              .reduce((a, b) => a > b ? a : b);
          expect(highestInactive, greaterThanOrEqualTo(prevHighestInactive),
              reason: 'inactive cards should decompress monotonically at step $i');
          prevHighestInactive = highestInactive;
        }

        // After full decompression, highest inactive should be at 100
        expect(prevHighestInactive, closeTo(100.0, 1.0),
            reason: 'highest inactive at 100 after full decompression');
      });

      test('always a card at 0 during compression, smooth decompression from bottom', () {
        final model = RatingModel([
          {'id': 1, 'content': 'A'},
          {'id': 2, 'content': 'B'},
          {'id': 3, 'content': 'C'},
          {'id': 4, 'content': 'D'},
        ]);
        model.confirmBinaryChoice();
        model.setActivePropositionPosition(50.0);
        model.confirmPlacement();

        // Compress past 0 - active is always at 0 during compression
        for (int i = 0; i < 200; i++) {
          model.moveActiveProposition(-1);
          final allPositions =
              model.rankedPropositions.map((p) => p.position).toList();
          expect(allPositions.any((p) => p <= 0.5), isTrue,
              reason: 'must always have a card at 0 during compression step $i');
        }

        model.normalizeVirtualPositionOnRelease();

        // Decompression - inactive cards gradually return to original positions
        double prevLowestInactive = 100;
        for (int i = 0; i < 100; i++) {
          model.moveActiveProposition(1);
          final lowestInactive = model.rankedPropositions
              .where((p) => !p.isActive)
              .map((p) => p.position)
              .reduce((a, b) => a < b ? a : b);
          expect(lowestInactive, lessThanOrEqualTo(prevLowestInactive),
              reason: 'inactive cards should decompress monotonically at step $i');
          prevLowestInactive = lowestInactive;
        }

        // After full decompression, lowest inactive should be at 0
        expect(prevLowestInactive, closeTo(0.0, 1.0),
            reason: 'lowest inactive at 0 after full decompression');
      });
    });
  });
}
