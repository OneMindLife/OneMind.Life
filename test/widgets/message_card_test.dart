import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/message_card.dart';
import 'package:onemind_app/widgets/proposition_content_card.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  group('MessageCard', () {
    testWidgets('displays content and label', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const MessageCard(
          label: 'Initial Message',
          content: 'What should we do?',
        ),
      ));

      expect(find.text('Initial Message'), findsOneWidget);
      expect(find.text('What should we do?'), findsOneWidget);
    });

    testWidgets('label appears above content', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const MessageCard(
          label: 'Label',
          content: 'Content text here',
        ),
      ));

      final labelOffset = tester.getCenter(find.text('Label'));
      final contentOffset = tester.getCenter(find.text('Content text here'));
      expect(labelOffset.dy, lessThan(contentOffset.dy));
    });

    testWidgets('uses PropositionContentCard internally', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const MessageCard(
          label: 'Test',
          content: 'Test content',
        ),
      ));

      expect(find.byType(PropositionContentCard), findsOneWidget);
    });

    testWidgets('shrinks to content width (not full-width)', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const MessageCard(
          label: 'Short',
          content: 'Hi',
        ),
      ));

      // The UnconstrainedBox should make the card narrower than screen
      final card = tester.getSize(find.byType(PropositionContentCard));
      final screen = tester.getSize(find.byType(Scaffold));
      expect(card.width, lessThan(screen.width));
    });

    testWidgets('uses primary border for isConsensus', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const MessageCard(
          label: 'Convergence #1',
          content: 'Winner',
          isConsensus: true,
        ),
      ));

      // Should use PropositionContentCard with primary border
      final card = tester.widget<PropositionContentCard>(
        find.byType(PropositionContentCard),
      );
      expect(card.borderColor, isNotNull);
    });

    testWidgets('uses primary border for isPrimary', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const MessageCard(
          label: 'Initial Message',
          content: 'Question',
          isPrimary: true,
        ),
      ));

      final card = tester.widget<PropositionContentCard>(
        find.byType(PropositionContentCard),
      );
      expect(card.borderColor, isNotNull);
    });

    testWidgets('uses default border when neither primary nor consensus', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const MessageCard(
          label: 'Plain',
          content: 'Basic content',
        ),
      ));

      final card = tester.widget<PropositionContentCard>(
        find.byType(PropositionContentCard),
      );
      expect(card.borderColor, isNull);
    });
  });
}
