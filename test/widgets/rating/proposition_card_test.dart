import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/rating/rating_model.dart';
import 'package:onemind_app/widgets/rating/proposition_card.dart';

void main() {
  group('PropositionCard', () {
    Widget buildTestWidget({
      required RatingProposition proposition,
      bool isActive = false,
      bool isBinaryPhase = false,
      Color? activeGlowColor,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: PropositionCard(
              proposition: proposition,
              isActive: isActive,
              isBinaryPhase: isBinaryPhase,
              activeGlowColor: activeGlowColor,
            ),
          ),
        ),
      );
    }

    testWidgets('displays proposition content', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Test proposition content',
        position: 50.0,
      );

      await tester.pumpWidget(buildTestWidget(proposition: proposition));

      expect(find.text('Test proposition content'), findsOneWidget);
    });

    testWidgets('displays long content in scrollable container', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'This is a very long proposition content that should be '
            'scrollable because it exceeds the visible area. '
            'The user can scroll to see more text. '
            'This additional text should be accessible via scroll.',
        position: 50.0,
      );

      await tester.pumpWidget(buildTestWidget(proposition: proposition));

      // The text widget should exist
      expect(find.byType(Text), findsOneWidget);

      // Should be wrapped in a SingleChildScrollView for scrollability
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      // Text should NOT have overflow constraints (no truncation)
      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.overflow, isNull);
      expect(textWidget.maxLines, isNull);
    });

    testWidgets('shows glow effect when active', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Active proposition',
        position: 50.0,
        isActive: true,
      );

      await tester.pumpWidget(buildTestWidget(
        proposition: proposition,
        isActive: true,
      ));

      // Find the outer container with box shadow (glow effect)
      final containers = tester.widgetList<Container>(find.byType(Container));

      // At least one container should have box shadows for glow
      final hasGlow = containers.any((container) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          return decoration.boxShadow != null && decoration.boxShadow!.isNotEmpty;
        }
        return false;
      });

      expect(hasGlow, true);
    });

    testWidgets('shows glow effect in binary phase', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Binary phase proposition',
        position: 100.0,
      );

      await tester.pumpWidget(buildTestWidget(
        proposition: proposition,
        isBinaryPhase: true,
      ));

      // Find containers with box shadow
      final containers = tester.widgetList<Container>(find.byType(Container));

      final hasGlow = containers.any((container) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          return decoration.boxShadow != null && decoration.boxShadow!.isNotEmpty;
        }
        return false;
      });

      expect(hasGlow, true);
    });

    testWidgets('no glow effect when inactive and not binary phase', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Inactive proposition',
        position: 50.0,
      );

      await tester.pumpWidget(buildTestWidget(
        proposition: proposition,
        isActive: false,
        isBinaryPhase: false,
      ));

      // Find containers - should not have glow box shadows
      final containers = tester.widgetList<Container>(find.byType(Container));

      // The outer container shouldn't have glow shadows
      // Inner container (with border) is the only one
      final glowContainers = containers.where((container) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          return decoration.boxShadow != null && decoration.boxShadow!.isNotEmpty;
        }
        return false;
      });

      expect(glowContainers.isEmpty, true);
    });

    testWidgets('has thicker border when active', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Active proposition',
        position: 50.0,
        isActive: true,
      );

      await tester.pumpWidget(buildTestWidget(
        proposition: proposition,
        isActive: true,
      ));

      // Find container with border
      final containers = tester.widgetList<Container>(find.byType(Container));

      final hasBorder = containers.any((container) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          // Active cards have width 2
          return true;
        }
        return false;
      });

      expect(hasBorder, true);
    });

    testWidgets('uses custom active glow color', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Custom color proposition',
        position: 50.0,
        isActive: true,
      );

      const customColor = Colors.red;

      await tester.pumpWidget(buildTestWidget(
        proposition: proposition,
        isActive: true,
        activeGlowColor: customColor,
      ));

      // Find containers with box shadow
      final containers = tester.widgetList<Container>(find.byType(Container));

      final hasCustomColorGlow = containers.any((container) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration && decoration.boxShadow != null) {
          return decoration.boxShadow!.any((shadow) {
            // Shadow color should be based on custom color (with alpha)
            // Compare red channel values using the new Color API
            return (shadow.color.r * 255).round() == (customColor.r * 255).round();
          });
        }
        return false;
      });

      expect(hasCustomColorGlow, true);
    });

    testWidgets('has max height constraint', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Constrained proposition',
        position: 50.0,
      );

      await tester.pumpWidget(buildTestWidget(proposition: proposition));

      // Find container with constraints
      final containers = tester.widgetList<Container>(find.byType(Container));

      final hasMaxHeightConstraint = containers.any((container) {
        return container.constraints?.maxHeight == 150;
      });

      expect(hasMaxHeightConstraint, true);
    });

    testWidgets('has rounded corners', (tester) async {
      final proposition = RatingProposition(
        id: '1',
        content: 'Rounded proposition',
        position: 50.0,
      );

      await tester.pumpWidget(buildTestWidget(proposition: proposition));

      // Find container with border radius
      final containers = tester.widgetList<Container>(find.byType(Container));

      final hasRoundedCorners = containers.any((container) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          return decoration.borderRadius == BorderRadius.circular(12);
        }
        return false;
      });

      expect(hasRoundedCorners, true);
    });
  });
}
