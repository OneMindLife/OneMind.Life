import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/proposition_content_card.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('PropositionContentCard', () {
    testWidgets('displays content text', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(content: 'Test proposition'),
      ));

      expect(find.text('Test proposition'), findsOneWidget);
    });

    testWidgets('displays label above content when provided', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(
          content: 'The content',
          label: 'Initial Message',
        ),
      ));

      expect(find.text('Initial Message'), findsOneWidget);
      expect(find.text('The content'), findsOneWidget);

      // Label should appear before content vertically
      final labelOffset = tester.getCenter(find.text('Initial Message'));
      final contentOffset = tester.getCenter(find.text('The content'));
      expect(labelOffset.dy, lessThan(contentOffset.dy));
    });

    testWidgets('does not show label when not provided', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(content: 'Just content'),
      ));

      expect(find.text('Just content'), findsOneWidget);
      // Only one Text widget (the content)
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('uses custom border color when provided', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(
          content: 'Custom border',
          borderColor: Colors.red,
          borderWidth: 2,
        ),
      ));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, Colors.red);
      expect(border.top.width, 2.0);
    });

    testWidgets('has 12px border radius', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(content: 'Rounded'),
      ));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('contentOpacity defaults to 1.0', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(content: 'Visible', label: 'Label'),
      ));

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 1.0);
    });

    testWidgets('contentOpacity 0.0 hides text but preserves layout', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(
          content: 'Hidden',
          label: 'Label',
          contentOpacity: 0.0,
        ),
      ));

      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0.0);
      // Text is still in the tree (for layout) just invisible
      expect(find.text('Hidden'), findsOneWidget);
      expect(find.text('Label'), findsOneWidget);
    });

    testWidgets('unbounded (default) does not wrap in SingleChildScrollView',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(content: 'Full text no scroll'),
      ));

      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('bounded=true wraps content in SingleChildScrollView',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        const PropositionContentCard(
          content: 'Scrollable text',
          bounded: true,
        ),
      ));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets(
      'unbounded grows beyond maxHeight to fit long content',
      (tester) async {
        final longText = List.generate(50, (i) => 'Line $i').join('\n');
        await tester.pumpWidget(createTestWidget(
          SizedBox(
            width: 300,
            child: PropositionContentCard(content: longText),
          ),
        ));

        final cardSize = tester.getSize(find.byType(PropositionContentCard));
        // 50 lines of text should exceed the old 150px maxHeight.
        expect(cardSize.height, greaterThan(150));
      },
    );

    testWidgets(
      'bounded=true caps card height at maxHeight',
      (tester) async {
        final longText = List.generate(50, (i) => 'Line $i').join('\n');
        await tester.pumpWidget(createTestWidget(
          SizedBox(
            width: 300,
            child: PropositionContentCard(
              content: longText,
              bounded: true,
              maxHeight: 120,
            ),
          ),
        ));

        final cardSize = tester.getSize(find.byType(PropositionContentCard));
        // Card padding adds ~24px, but overall height should stay near the cap.
        expect(cardSize.height, lessThanOrEqualTo(120 + 48));
      },
    );
  });
}
