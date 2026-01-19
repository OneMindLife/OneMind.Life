import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/consensus_section.dart';

void main() {
  group('ConsensusSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: ConsensusSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Consensus Settings'), findsOneWidget);
    });

    testWidgets('displays confirmation rounds input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: ConsensusSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Confirmation rounds'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // Default value
    });

    testWidgets('displays helper text for confirmation rounds = 1',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: const ConsensusSettings(
                confirmationRoundsRequired: 1,
                showPreviousResults: false,
                propositionsPerUser: 1,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('First winner reaches consensus immediately'),
        findsOneWidget,
      );
    });

    testWidgets('displays helper text for confirmation rounds > 1',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: const ConsensusSettings(
                confirmationRoundsRequired: 3,
                showPreviousResults: false,
                propositionsPerUser: 1,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Same proposition must win 3 rounds in a row'),
        findsOneWidget,
      );
    });

    testWidgets('displays show results switch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: ConsensusSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Show full results from past rounds'), findsOneWidget);
    });

    testWidgets('displays correct subtitle when results hidden',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: const ConsensusSettings(
                confirmationRoundsRequired: 2,
                showPreviousResults: false,
                propositionsPerUser: 1,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Users only see the winning proposition'),
        findsOneWidget,
      );
    });

    testWidgets('displays correct subtitle when results shown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: const ConsensusSettings(
                confirmationRoundsRequired: 2,
                showPreviousResults: true,
                propositionsPerUser: 1,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Users see all propositions and ratings'),
        findsOneWidget,
      );
    });

    testWidgets('calls onChanged when incrementing confirmation rounds',
        (tester) async {
      ConsensusSettings? updatedSettings;

      // Start with 1 so we can increment to 2 (max is now 2)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: const ConsensusSettings(
                confirmationRoundsRequired: 1,
                showPreviousResults: false,
                propositionsPerUser: 1,
              ),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.confirmationRoundsRequired, 2);
    });

    testWidgets('calls onChanged when toggling show results', (tester) async {
      ConsensusSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: ConsensusSettings.defaults(),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      // Find the switch for "Show full results"
      // Default is now true, so toggling turns it off
      final switches = find.byType(Switch);
      await tester.tap(switches.first);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.showPreviousResults, isFalse);
    });

    testWidgets('respects min limit of 1 for confirmation rounds',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: const ConsensusSettings(
                confirmationRoundsRequired: 1,
                showPreviousResults: false,
                propositionsPerUser: 1,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final decrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(decrementButton.onPressed, isNull);
    });

    testWidgets('respects max limit of 10 for confirmation rounds',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsensusSection(
              settings: const ConsensusSettings(
                confirmationRoundsRequired: 10,
                showPreviousResults: false,
                propositionsPerUser: 1,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final incrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(incrementButton.onPressed, isNull);
    });
  });
}
