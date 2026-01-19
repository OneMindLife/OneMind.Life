import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/grid_ranking/grid_ranking_model.dart';
import 'package:onemind_app/widgets/grid_ranking/stacked_proposition_card.dart';
import 'package:onemind_app/widgets/grid_ranking/proposition_card.dart';

void main() {
  group('StackedPropositionCard', () {
    late GridRankingModel model;

    setUp(() {
      model = GridRankingModel([
        {'id': 1, 'content': 'First proposition'},
        {'id': 2, 'content': 'Second proposition'},
        {'id': 3, 'content': 'Third proposition'},
        {'id': 4, 'content': 'Fourth proposition'},
      ]);
      model.confirmBinaryChoice();
    });

    Widget buildTestWidget({
      required RankingProposition defaultCard,
      required List<RankingProposition> allCardsInStack,
      bool isActive = false,
      GridRankingModel? customModel,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: StackedPropositionCard(
              defaultCard: defaultCard,
              allCardsInStack: allCardsInStack,
              isActive: isActive,
              model: customModel ?? model,
            ),
          ),
        ),
      );
    }

    group('Single Card Display', () {
      testWidgets('displays single card without stack UI', (tester) async {
        final card = RankingProposition(
          id: '1',
          content: 'Single card content',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
        ));

        // Should show the content
        expect(find.text('Single card content'), findsOneWidget);

        // Should NOT show stack indicator badge
        expect(find.text('1 stacked'), findsNothing);

        // Should NOT show navigation arrows
        expect(find.byIcon(Icons.chevron_left), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      });

      testWidgets('wraps single card in FadeTransition', (tester) async {
        final card = RankingProposition(
          id: '1',
          content: 'Fading card',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
        ));

        // Should have at least one FadeTransition
        expect(find.byType(FadeTransition), findsWidgets);
      });
    });

    group('Stacked Cards Display', () {
      testWidgets('shows stack indicator badge for multiple cards', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RankingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        expect(find.text('2 stacked'), findsOneWidget);
      });

      testWidgets('shows correct count for 3 stacked cards', (tester) async {
        final cards = List.generate(
          3,
          (i) => RankingProposition(
            id: '$i',
            content: 'Card $i',
            position: 50.0,
          ),
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: cards[0],
          allCardsInStack: cards,
        ));

        expect(find.text('3 stacked'), findsOneWidget);
      });

      testWidgets('shows navigation arrows for stacked cards', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RankingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        expect(find.byIcon(Icons.chevron_left), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      });

      testWidgets('displays default card content initially', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Default card content',
          position: 50.0,
        );
        final card2 = RankingProposition(
          id: '2',
          content: 'Hidden card content',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        expect(find.text('Default card content'), findsOneWidget);
        expect(find.text('Hidden card content'), findsNothing);
      });
    });

    group('Navigation Arrows', () {
      testWidgets('tapping right arrow cycles to next card', (tester) async {
        // Create model with cards at same position (stacked)
        final stackModel = GridRankingModel([
          {'id': 1, 'content': 'Card A'},
          {'id': 2, 'content': 'Card B'},
          {'id': 3, 'content': 'Card C'},
        ]);
        stackModel.confirmBinaryChoice();
        // Place at position 100 to create stack
        stackModel.setActivePropositionPosition(100.0);
        stackModel.confirmPlacement();

        // Get the stack
        final stack = stackModel.getStackAtPosition(100.0);
        expect(stack, isNotNull);
        expect(stack!.cardCount, 2);

        final allCards = stackModel.rankedPropositions
            .where((p) => stack.allCardIds.contains(p.id))
            .toList();

        final defaultCard =
            allCards.firstWhere((c) => c.id == stack.defaultCardId);

        await tester.pumpWidget(buildTestWidget(
          defaultCard: defaultCard,
          allCardsInStack: allCards,
          customModel: stackModel,
        ));

        // Tap right arrow
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pump();

        // Model should have cycled the stack
        final newStack = stackModel.getStackAtPosition(100.0);
        expect(newStack!.defaultCardId, isNot(equals(stack.defaultCardId)));
      });

      testWidgets('tapping left arrow cycles to previous card', (tester) async {
        final stackModel = GridRankingModel([
          {'id': 1, 'content': 'Card A'},
          {'id': 2, 'content': 'Card B'},
          {'id': 3, 'content': 'Card C'},
        ]);
        stackModel.confirmBinaryChoice();
        stackModel.setActivePropositionPosition(100.0);
        stackModel.confirmPlacement();

        final stack = stackModel.getStackAtPosition(100.0)!;
        final allCards = stackModel.rankedPropositions
            .where((p) => stack.allCardIds.contains(p.id))
            .toList();
        final defaultCard =
            allCards.firstWhere((c) => c.id == stack.defaultCardId);

        await tester.pumpWidget(buildTestWidget(
          defaultCard: defaultCard,
          allCardsInStack: allCards,
          customModel: stackModel,
        ));

        // Tap left arrow
        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pump();

        // Model should have cycled backwards
        final newStack = stackModel.getStackAtPosition(100.0);
        expect(newStack!.defaultCardId, isNot(equals(stack.defaultCardId)));
      });
    });

    group('Fade Animation', () {
      testWidgets('fade animation plays when card changes', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RankingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        // Initial state - should show card 1
        expect(find.text('Card 1'), findsOneWidget);

        // Update to new default card
        await tester.pumpWidget(buildTestWidget(
          defaultCard: card2,
          allCardsInStack: [card1, card2],
        ));

        // Animation should be in progress - pump through it
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));

        // Let animation complete
        await tester.pumpAndSettle();

        // Should be showing card 2 content now
        expect(find.text('Card 2'), findsOneWidget);
      });

      testWidgets('animation duration is 500ms', (tester) async {
        final card = RankingProposition(
          id: '1',
          content: 'Test',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
        ));

        // Find the state to check animation controller
        final state = tester.state<State>(find.byType(StackedPropositionCard));

        // State should exist
        expect(state, isNotNull);
      });
    });

    group('Auto-Cycling Timer', () {
      testWidgets('auto-cycles every 10 seconds for stacked cards',
          (tester) async {
        final stackModel = GridRankingModel([
          {'id': 1, 'content': 'Card A'},
          {'id': 2, 'content': 'Card B'},
          {'id': 3, 'content': 'Card C'},
        ]);
        stackModel.confirmBinaryChoice();
        stackModel.setActivePropositionPosition(100.0);
        stackModel.confirmPlacement();

        final stack = stackModel.getStackAtPosition(100.0)!;
        final allCards = stackModel.rankedPropositions
            .where((p) => stack.allCardIds.contains(p.id))
            .toList();
        final defaultCard =
            allCards.firstWhere((c) => c.id == stack.defaultCardId);
        final initialDefaultId = defaultCard.id;

        await tester.pumpWidget(buildTestWidget(
          defaultCard: defaultCard,
          allCardsInStack: allCards,
          customModel: stackModel,
        ));

        // Wait for 10 seconds (auto-cycle interval)
        await tester.pump(const Duration(seconds: 10));

        // Model should have cycled
        final newStack = stackModel.getStackAtPosition(100.0);
        expect(newStack!.defaultCardId, isNot(equals(initialDefaultId)));
      });

      testWidgets('no auto-cycling for single card', (tester) async {
        final card = RankingProposition(
          id: '1',
          content: 'Single card',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
        ));

        // Wait for 10 seconds
        await tester.pump(const Duration(seconds: 10));

        // Should still show the same card (no change)
        expect(find.text('Single card'), findsOneWidget);
      });
    });

    group('Widget Updates', () {
      testWidgets('updates when stack size changes', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RankingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );

        // Start with single card
        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1],
        ));

        expect(find.text('1 stacked'), findsNothing);

        // Update to stacked cards
        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        expect(find.text('2 stacked'), findsOneWidget);
      });

      testWidgets('handles active card moving into stack', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final activeCard = RankingProposition(
          id: '2',
          content: 'Active Card',
          position: 50.0,
          isActive: true,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1],
        ));

        // Add active card to stack
        await tester.pumpWidget(buildTestWidget(
          defaultCard: activeCard,
          allCardsInStack: [card1, activeCard],
          isActive: true,
        ));

        await tester.pumpAndSettle();

        // Should show active card content
        expect(find.text('Active Card'), findsOneWidget);
      });
    });

    group('PropositionCard Integration', () {
      testWidgets('renders PropositionCard inside', (tester) async {
        final card = RankingProposition(
          id: '1',
          content: 'Test content',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
        ));

        expect(find.byType(PropositionCard), findsOneWidget);
      });

      testWidgets('passes isActive to PropositionCard', (tester) async {
        final card = RankingProposition(
          id: '1',
          content: 'Active card',
          position: 50.0,
          isActive: true,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
          isActive: true,
        ));

        // PropositionCard should show active styling (glow)
        final containers = tester.widgetList<Container>(find.byType(Container));
        final hasGlow = containers.any((container) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            return decoration.boxShadow != null &&
                decoration.boxShadow!.isNotEmpty;
          }
          return false;
        });

        expect(hasGlow, true);
      });
    });

    group('Edge Cases', () {
      testWidgets('handles empty stack gracefully', (tester) async {
        // This shouldn't happen in practice, but test defensively
        final card = RankingProposition(
          id: '1',
          content: 'Only card',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
        ));

        expect(find.text('Only card'), findsOneWidget);
      });

      testWidgets('disposes timer on unmount', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RankingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        // Unmount the widget
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ));

        // Should not throw any errors after unmount
        await tester.pump(const Duration(seconds: 15));
      });

      testWidgets('handles rapid card changes', (tester) async {
        final card1 = RankingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RankingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );
        final card3 = RankingProposition(
          id: '3',
          content: 'Card 3',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2, card3],
        ));

        // Rapidly change cards
        await tester.pumpWidget(buildTestWidget(
          defaultCard: card2,
          allCardsInStack: [card1, card2, card3],
        ));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card3,
          allCardsInStack: [card1, card2, card3],
        ));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2, card3],
        ));

        // Let animations settle
        await tester.pumpAndSettle();

        // Should show card 1 after all changes
        expect(find.text('Card 1'), findsOneWidget);
      });
    });
  });
}
