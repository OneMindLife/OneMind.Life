import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/widgets/round_winner_item.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );
  }

  group('RoundWinnerItem', () {
    testWidgets('displays winner text and label', (tester) async {
      await tester.pumpWidget(createTestWidget(
        RoundWinnerItem(
          winnerTexts: const ['Community Garden'],
          label: 'Round 1 Winner',
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Community Garden'), findsOneWidget);
      expect(find.text('Round 1 Winner'), findsOneWidget);
    });

    testWidgets('shows chevrons for multiple winners', (tester) async {
      await tester.pumpWidget(createTestWidget(
        RoundWinnerItem(
          winnerTexts: const ['Winner A', 'Winner B'],
          label: 'Round 1 Winner',
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('Winner A'), findsOneWidget);
    });

    testWidgets('chevrons cycle through winners', (tester) async {
      await tester.pumpWidget(createTestWidget(
        RoundWinnerItem(
          winnerTexts: const ['First', 'Second'],
          label: 'Round 1 Winner',
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('First'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text('Second'), findsOneWidget);

      // Loop back
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('no chevrons for single winner', (tester) async {
      await tester.pumpWidget(createTestWidget(
        RoundWinnerItem(
          winnerTexts: const ['Solo'],
          label: 'Round 1 Winner',
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(createTestWidget(
        RoundWinnerItem(
          winnerTexts: const ['Tappable'],
          label: 'Round 1 Winner',
          onTap: () => tapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tappable'));
      expect(tapped, isTrue);
    });

    testWidgets('uses primary border when isConvergence is true', (tester) async {
      await tester.pumpWidget(createTestWidget(
        RoundWinnerItem(
          winnerTexts: const ['Convergence'],
          label: 'Round 3 Winner',
          isConvergence: true,
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(RoundWinnerItem),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.width, 2.0);
    });

    testWidgets('uses consensus border when isConvergence is false', (tester) async {
      await tester.pumpWidget(createTestWidget(
        RoundWinnerItem(
          winnerTexts: const ['Non-convergence'],
          label: 'Round 1 Winner',
          isConvergence: false,
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(RoundWinnerItem),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.width, 1.0);
    });
  });
}
