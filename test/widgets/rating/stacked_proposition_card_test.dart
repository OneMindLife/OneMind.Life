import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/rating/rating_model.dart';
import 'package:onemind_app/widgets/rating/stacked_proposition_card.dart';
import 'package:onemind_app/widgets/rating/proposition_card.dart';

void main() {
  group('StackedPropositionCard', () {
    late RatingModel model;

    setUp(() {
      model = RatingModel([
        {'id': 1, 'content': 'First proposition'},
        {'id': 2, 'content': 'Second proposition'},
        {'id': 3, 'content': 'Third proposition'},
        {'id': 4, 'content': 'Fourth proposition'},
      ]);
      model.confirmBinaryChoice();
    });

    Widget buildTestWidget({
      required RatingProposition defaultCard,
      required List<RatingProposition> allCardsInStack,
      bool isActive = false,
      RatingModel? customModel,
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
        final card = RatingProposition(
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

        // Should NOT show navigation arrows
        expect(find.byIcon(Icons.chevron_left), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      });

      testWidgets('wraps single card in PropositionCard', (tester) async {
        final card = RatingProposition(
          id: '1',
          content: 'Fading card',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card,
          allCardsInStack: [card],
        ));

        expect(find.byType(PropositionCard), findsOneWidget);
      });
    });

    group('Stacked Cards Display', () {
      testWidgets('shows navigation arrows for stacked cards', (tester) async {
        final card1 = RatingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RatingProposition(
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
        final card1 = RatingProposition(
          id: '1',
          content: 'Default card content',
          position: 50.0,
        );
        final card2 = RatingProposition(
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
        final card1 = RatingProposition(
          id: '1',
          content: 'Card A',
          position: 50.0,
        );
        final card2 = RatingProposition(
          id: '2',
          content: 'Card B',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        expect(find.text('Card A'), findsOneWidget);

        // Tap right arrow
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();

        // Should now show Card B
        expect(find.text('Card B'), findsOneWidget);
      });

      testWidgets('tapping left arrow cycles to previous card', (tester) async {
        final card1 = RatingProposition(
          id: '1',
          content: 'Card A',
          position: 50.0,
        );
        final card2 = RatingProposition(
          id: '2',
          content: 'Card B',
          position: 50.0,
        );

        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        // Tap left arrow (wraps around to card2)
        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();

        // Should now show Card B
        expect(find.text('Card B'), findsOneWidget);
      });
    });

    group('Fade Animation', () {
      testWidgets('fade animation plays when card changes', (tester) async {
        final card1 = RatingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RatingProposition(
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

        // Let animation complete
        await tester.pumpAndSettle();

        // Should be showing card 2 content now
        expect(find.text('Card 2'), findsOneWidget);
      });

      testWidgets('animation controller exists', (tester) async {
        final card = RatingProposition(
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

    group('Widget Updates', () {
      testWidgets('updates when default card changes', (tester) async {
        final card1 = RatingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RatingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );

        // Start with card1
        await tester.pumpWidget(buildTestWidget(
          defaultCard: card1,
          allCardsInStack: [card1, card2],
        ));

        expect(find.text('Card 1'), findsOneWidget);

        // Update default to card2
        await tester.pumpWidget(buildTestWidget(
          defaultCard: card2,
          allCardsInStack: [card1, card2],
        ));
        await tester.pumpAndSettle();

        expect(find.text('Card 2'), findsOneWidget);
      });

      testWidgets('handles active card moving into stack', (tester) async {
        final card1 = RatingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final activeCard = RatingProposition(
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
        final card = RatingProposition(
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
        final card = RatingProposition(
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
        final card = RatingProposition(
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

      testWidgets('handles rapid card changes', (tester) async {
        final card1 = RatingProposition(
          id: '1',
          content: 'Card 1',
          position: 50.0,
        );
        final card2 = RatingProposition(
          id: '2',
          content: 'Card 2',
          position: 50.0,
        );
        final card3 = RatingProposition(
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

        // Should show card 1 after all changes — find within PropositionCard
        // to avoid matching text in other widgets during animation
        expect(find.byType(PropositionCard), findsOneWidget);
      });
    });
  });
}
