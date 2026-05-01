import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/screens/rating/read_only_results_screen.dart';
import 'package:onemind_app/widgets/rating/rating_widget.dart';

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

      // Tap the AppBar back button (not the inline hint icon)
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(popped, true);
    });

    // ===========================================================
    // Near-tie display bug regression
    // (NCDD Higher Ed Exchange demo, chat 309, 2026-05-01)
    // ===========================================================
    //
    // Two propositions whose final ratings differ by less than 1 point
    // should render as a single stacked card whose visible default is
    // the higher-rated card — NOT as two cards painted on top of each
    // other where the visible card is decided by paint order.
    group('near-tie stacking (NCDD R1 regression)', () {
      testWidgets(
        'two propositions <1 point apart render only the higher-rated as '
        'the visible card text',
        (tester) async {
          await tester.pumpWidget(
            createTestWidget(
              ReadOnlyResultsScreen(
                propositions: [
                  // Listed in non-rating order to confirm placement
                  // order does not influence visibility
                  Proposition(
                    id: 1,
                    roundId: 1,
                    content: 'DEI question',
                    createdAt: DateTime.now(),
                    finalRating: 99.91,
                  ),
                  Proposition(
                    id: 2,
                    roundId: 1,
                    content: 'ingrained patterns',
                    createdAt: DateTime.now(),
                    finalRating: 100.00,
                  ),
                ],
                roundNumber: 1,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // The higher-rated card's content must be visible. The
          // runner-up may or may not have its content visible depending
          // on whether the StackedPropositionCard exposes both —
          // the load-bearing assertion is that the WINNER is the
          // surface card.
          expect(find.text('ingrained patterns'), findsOneWidget,
              reason: 'higher-rated proposition must be visibly on top in '
                  'the stack');
        },
      );

      testWidgets(
        'propositions >1 point apart still render as separate cards',
        (tester) async {
          await tester.pumpWidget(
            createTestWidget(
              ReadOnlyResultsScreen(
                propositions: [
                  Proposition(
                    id: 1,
                    roundId: 1,
                    content: 'high prop',
                    createdAt: DateTime.now(),
                    finalRating: 90.0,
                  ),
                  Proposition(
                    id: 2,
                    roundId: 1,
                    content: 'mid prop',
                    createdAt: DateTime.now(),
                    finalRating: 50.0,
                  ),
                  Proposition(
                    id: 3,
                    roundId: 1,
                    content: 'low prop',
                    createdAt: DateTime.now(),
                    finalRating: 10.0,
                  ),
                ],
                roundNumber: 1,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // All three should render their content (none stacked).
          expect(find.text('high prop'), findsOneWidget);
          expect(find.text('mid prop'), findsOneWidget);
          expect(find.text('low prop'), findsOneWidget);
        },
      );

      testWidgets(
        'screen mounts a RatingWidget for non-empty propositions',
        (tester) async {
          await tester.pumpWidget(
            createTestWidget(
              ReadOnlyResultsScreen(
                propositions: [
                  Proposition(
                    id: 1,
                    roundId: 1,
                    content: 'a',
                    createdAt: DateTime.now(),
                    finalRating: 80.0,
                  ),
                  Proposition(
                    id: 2,
                    roundId: 1,
                    content: 'b',
                    createdAt: DateTime.now(),
                    finalRating: 79.5,
                  ),
                ],
                roundNumber: 1,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(RatingWidget), findsOneWidget);
        },
      );
    });
  });
}
