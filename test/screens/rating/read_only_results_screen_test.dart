import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/screens/rating/matches_results_view.dart';
import 'package:onemind_app/screens/rating/read_only_results_screen.dart';
import 'package:onemind_app/widgets/rating/proposition_card.dart';
import 'package:onemind_app/widgets/rating/rating_widget.dart';
import 'package:onemind_app/widgets/rating/stacked_proposition_card.dart';

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

    testWidgets('matches mode renders the ranked results view, not the grid',
        (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          ReadOnlyResultsScreen(
            // Pre-sorted desc by finalRating (winner first), as the service returns.
            propositions: [
              Proposition(
                id: 1,
                roundId: 1,
                content: 'Winner idea',
                createdAt: DateTime.now(),
                finalRating: 88.0,
              ),
              Proposition(
                id: 2,
                roundId: 1,
                content: 'Runner up',
                createdAt: DateTime.now(),
                finalRating: 60.0,
              ),
              Proposition(
                id: 3,
                roundId: 1,
                content: 'Third idea',
                createdAt: DateTime.now(),
                finalRating: 30.0,
              ),
            ],
            roundNumber: 1,
            ratingMode: 'matches',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The ranked results view, not the 0–100 grid.
      expect(find.byType(MatchesResultsView), findsOneWidget);
      expect(find.byType(RatingWidget), findsNothing);
      // Every idea ranked, with positions shown.
      expect(find.text('Winner idea'), findsOneWidget);
      expect(find.text('Runner up'), findsOneWidget);
      expect(find.text('Third idea'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
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
        'PRODUCTION DATA FLOW (proposition_service sort: winner first): '
        'visible card in near-tie stack is the higher-rated one',
        (tester) async {
          // Mirrors the actual prod flow — proposition_service.dart
          // returns propositions sorted by rating desc (winner first).
          // The original 2026-05-01 NCDD demo bug: this test (with text-
          // findability assertion) used to pass even when the bug was
          // present, because BOTH cards exist in the widget tree (one
          // hidden via opacity 0). Strengthened to inspect the actual
          // visible card via StackedPropositionCard's inner
          // PropositionCard.
          await tester.pumpWidget(
            createTestWidget(
              ReadOnlyResultsScreen(
                propositions: [
                  Proposition(
                    id: 13209,
                    roundId: 2405,
                    content: 'ingrained patterns',
                    createdAt: DateTime.now(),
                    finalRating: 100.0,
                  ),
                  Proposition(
                    id: 13197,
                    roundId: 2405,
                    content: 'DEI question',
                    createdAt: DateTime.now(),
                    finalRating: 99.91,
                  ),
                ],
                roundNumber: 1,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Exactly one StackedPropositionCard for the near-tied pair.
          final stacked = find.byType(StackedPropositionCard);
          expect(stacked, findsOneWidget,
              reason: 'the two near-tied props must render as a single '
                  'stacked card (not two cards painted on top of each '
                  'other)');

          // Inspect the StackedPropositionCard's inner PropositionCard
          // — this is the actually-visible card, distinct from any
          // hidden (opacity-0) PropositionCard sibling.
          final innerVisible = tester.widget<PropositionCard>(
            find.descendant(
              of: stacked,
              matching: find.byType(PropositionCard),
            ),
          );
          expect(innerVisible.proposition.content, 'ingrained patterns',
              reason: 'higher-rated proposition must be the visible card '
                  'inside the stacked card; this is the regression that '
                  'broke at the NCDD demo');

          // Also confirm the StackedPropositionCard.defaultCard prop —
          // belt-and-suspenders, in case the inner-card check ever moves.
          final stackedWidget =
              tester.widget<StackedPropositionCard>(stacked);
          expect(stackedWidget.defaultCard.content, 'ingrained patterns');
        },
      );

      testWidgets(
        'right chevron cycles from winner to runner-up; left cycles back',
        (tester) async {
          // Hidden (opacity-0) sibling cards from non-default
          // iterations sit at nearly the same Y as the visible
          // StackedPropositionCard in near-tie scenarios. Without
          // IgnorePointer wrapping, those siblings intercept taps
          // before they reach the chevrons. Surfaced 2026-05-02:
          // chevron taps did nothing on the read-only results screen.
          await tester.pumpWidget(
            createTestWidget(
              ReadOnlyResultsScreen(
                propositions: [
                  Proposition(
                    id: 1,
                    roundId: 1,
                    content: 'WINNER',
                    createdAt: DateTime.now(),
                    finalRating: 100.0,
                  ),
                  Proposition(
                    id: 2,
                    roundId: 1,
                    content: 'RUNNER_UP',
                    createdAt: DateTime.now(),
                    finalRating: 99.91,
                  ),
                ],
                roundNumber: 1,
              ),
            ),
          );
          await tester.pumpAndSettle();

          PropositionCard innerCard() => tester.widget<PropositionCard>(
                find.descendant(
                  of: find.byType(StackedPropositionCard),
                  matching: find.byType(PropositionCard),
                ),
              );

          expect(innerCard().proposition.content, 'WINNER',
              reason: 'starts on the higher-rated card');

          // Tap right chevron → should cycle to runner-up
          await tester.tap(find.byIcon(Icons.chevron_right));
          await tester.pumpAndSettle();
          expect(innerCard().proposition.content, 'RUNNER_UP',
              reason: 'right chevron must cycle past hidden sibling '
                  'taps to the next card');

          // Tap left chevron → should cycle back to winner
          await tester.tap(find.byIcon(Icons.chevron_left));
          await tester.pumpAndSettle();
          expect(innerCard().proposition.content, 'WINNER',
              reason: 'left chevron must cycle backward');
        },
      );

      testWidgets(
        'visible card holds whether props are passed in either order',
        (tester) async {
          // Reverse insertion order — winner comes second. The
          // visible card must STILL be the winner.
          await tester.pumpWidget(
            createTestWidget(
              ReadOnlyResultsScreen(
                propositions: [
                  Proposition(
                    id: 1,
                    roundId: 1,
                    content: 'lower',
                    createdAt: DateTime.now(),
                    finalRating: 99.91,
                  ),
                  Proposition(
                    id: 2,
                    roundId: 1,
                    content: 'higher',
                    createdAt: DateTime.now(),
                    finalRating: 100.0,
                  ),
                ],
                roundNumber: 1,
              ),
            ),
          );
          await tester.pumpAndSettle();

          final stacked = find.byType(StackedPropositionCard);
          expect(stacked, findsOneWidget);

          final innerVisible = tester.widget<PropositionCard>(
            find.descendant(
              of: stacked,
              matching: find.byType(PropositionCard),
            ),
          );
          expect(innerVisible.proposition.content, 'higher',
              reason: 'insertion order must not influence which card is '
                  'visible — the higher-rated wins regardless');
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
