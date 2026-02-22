import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import '../fixtures/proposition_fixtures.dart';

void main() {
  group('ConsensusItem', () {
    test('creates without taskResult', () {
      final item = ConsensusItem(
        cycleId: 1,
        proposition: PropositionFixtures.winner(id: 1, content: 'Test'),
      );

      expect(item.cycleId, 1);
      expect(item.displayContent, 'Test');
      expect(item.taskResult, isNull);
    });

    test('creates with taskResult', () {
      final item = ConsensusItem(
        cycleId: 1,
        proposition: PropositionFixtures.winner(id: 1, content: 'Research task'),
        taskResult: 'Found: result1, result2',
      );

      expect(item.cycleId, 1);
      expect(item.displayContent, 'Research task');
      expect(item.taskResult, 'Found: result1, result2');
    });

    test('equality includes taskResult', () {
      // Use same proposition instance to avoid DateTime.now() differences
      final prop = PropositionFixtures.winner(id: 1, content: 'Test');

      final item1 = ConsensusItem(
        cycleId: 1,
        proposition: prop,
        taskResult: 'results',
      );
      final item2 = ConsensusItem(
        cycleId: 1,
        proposition: prop,
        taskResult: 'results',
      );
      final item3 = ConsensusItem(
        cycleId: 1,
        proposition: prop,
        taskResult: 'different',
      );

      expect(item1, equals(item2));
      expect(item1, isNot(equals(item3)));
    });

    test('equality treats null and non-null taskResult as different', () {
      final prop = PropositionFixtures.winner(id: 1, content: 'Test');

      final withResult = ConsensusItem(
        cycleId: 1,
        proposition: prop,
        taskResult: 'results',
      );
      final withoutResult = ConsensusItem(
        cycleId: 1,
        proposition: prop,
      );

      expect(withResult, isNot(equals(withoutResult)));
    });
  });
}
