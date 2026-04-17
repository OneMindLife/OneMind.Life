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
  });
}
