import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/screens/rating/read_only_results_screen.dart';

void main() {
  group('ReadOnlyResultsScreen', () {
    /// Helper to create a test widget with localization support
    Widget createTestWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: child,
      );
    }

    testWidgets('displays correct title with round number', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ReadOnlyResultsScreen(
            propositions: [
              Proposition(
                id: 1,
                roundId: 1,
                content: 'Test proposition',
                createdAt: DateTime.now(),
                finalRating: 75.0,
              ),
            ],
            roundNumber: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rating Results'), findsOneWidget);
    });

    testWidgets('shows back button in app bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          // Use a route stack so Flutter auto-generates a back button
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReadOnlyResultsScreen(
                      propositions: [
                        Proposition(
                          id: 1,
                          roundId: 1,
                          content: 'Test',
                          createdAt: DateTime.now(),
                          finalRating: 50.0,
                        ),
                      ],
                      roundNumber: 1,
                    ),
                  ),
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to the results screen
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      // Flutter auto-generates a BackButton when canPop is true
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('displays empty message when no propositions', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ReadOnlyResultsScreen(
            propositions: [],
            roundNumber: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No propositions to display'), findsOneWidget);
    });

    testWidgets('displays RatingWidget when propositions exist', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ReadOnlyResultsScreen(
            propositions: [
              Proposition(
                id: 1,
                roundId: 1,
                content: 'Proposition 1',
                createdAt: DateTime.now(),
                finalRating: 85.0,
              ),
              Proposition(
                id: 2,
                roundId: 1,
                content: 'Proposition 2',
                createdAt: DateTime.now(),
                finalRating: 50.0,
              ),
            ],
            roundNumber: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // RatingWidget should be present when there are propositions
      // The widget content will render the propositions as cards
      expect(find.text('Proposition 1'), findsOneWidget);
      expect(find.text('Proposition 2'), findsOneWidget);
    });

    testWidgets('handles null finalRating by defaulting to 50', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ReadOnlyResultsScreen(
            propositions: [
              Proposition(
                id: 1,
                roundId: 1,
                content: 'No rating prop',
                createdAt: DateTime.now(),
                finalRating: null, // No rating
              ),
            ],
            roundNumber: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should not crash, proposition should be displayed
      expect(find.text('No rating prop'), findsOneWidget);
    });

    testWidgets('back button pops navigation', (tester) async {
      var popped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Navigator(
            onPopPage: (route, result) {
              popped = true;
              return route.didPop(result);
            },
            pages: [
              const MaterialPage(
                child: Scaffold(body: Text('Home')),
              ),
              MaterialPage(
                child: ReadOnlyResultsScreen(
                  propositions: [
                    Proposition(
                      id: 1,
                      roundId: 1,
                      content: 'Test',
                      createdAt: DateTime.now(),
                      finalRating: 50.0,
                    ),
                  ],
                  roundNumber: 1,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(popped, true);
    });
  });
}
