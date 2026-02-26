import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/leaderboard/user_leaderboard_grid.dart';
import 'package:onemind_app/widgets/leaderboard/user_rank_card.dart';

import '../../fixtures/user_round_rank_fixtures.dart';
import '../../helpers/pump_app.dart';
import '../../mocks/mocks.dart';

void main() {
  late MockPropositionService mockPropositionService;

  setUp(() {
    mockPropositionService = MockPropositionService();
  });

  group('UserLeaderboardGrid', () {
    testWidgets('shows loading indicator while fetching data', (tester) async {
      // Setup mock to delay response
      mockPropositionService.setupGetUserRoundRanks(
        UserRoundRankFixtures.list(),
      );

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      // Initially shows loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays user rank cards after loading', (tester) async {
      final ranks = [
        UserRoundRankFixtures.model(
          id: 1,
          participantId: 1,
          rank: 75.0,
          displayName: 'Current User',
        ),
      ];
      mockPropositionService.setupGetUserRoundRanks(ranks);

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      // Wait for async loading
      await tester.pumpAndSettle();

      // Should display the user rank card
      expect(find.byType(UserRankCard), findsOneWidget);
      expect(find.text('Current User'), findsOneWidget);
    });

    testWidgets('shows current user and top-ranked user when different', (tester) async {
      final ranks = [
        UserRoundRankFixtures.model(
          id: 1,
          participantId: 1,
          rank: 65.0,
          displayName: 'Me',
        ),
        UserRoundRankFixtures.model(
          id: 2,
          participantId: 2,
          rank: 95.0,
          displayName: 'Top Scorer',
        ),
      ];
      mockPropositionService.setupGetUserRoundRanks(ranks);

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      await tester.pumpAndSettle();

      // Should display both cards
      expect(find.byType(UserRankCard), findsNWidgets(2));
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Top Scorer'), findsOneWidget);
    });

    testWidgets('shows empty state when no leaderboard data', (tester) async {
      mockPropositionService.setupGetUserRoundRanks([]);

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      await tester.pumpAndSettle();

      // Should show empty state message
      expect(find.text('No leaderboard data available'), findsOneWidget);
    });

    testWidgets('shows error state with retry button on failure', (tester) async {
      mockPropositionService.setupGetUserRoundRanksError(Exception('Network error'));

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      await tester.pumpAndSettle();

      // Should show error and retry button (compact ErrorView uses icon-only)
      expect(find.textContaining('Error'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows single card with trophy when current user is top-ranked', (tester) async {
      final ranks = [
        UserRoundRankFixtures.model(
          id: 1,
          participantId: 1,
          rank: 92.0,
          displayName: 'Champion',
        ),
      ];
      mockPropositionService.setupGetUserRoundRanks(ranks);

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      await tester.pumpAndSettle();

      // Should display single card with both indicators (current user + winner)
      expect(find.byType(UserRankCard), findsOneWidget);
      expect(find.text('Champion'), findsOneWidget);
      // Trophy icon should be present since they're the top-ranked
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('shows all users in leaderboard', (tester) async {
      final ranks = [
        UserRoundRankFixtures.model(
          id: 1,
          participantId: 1,
          rank: 80.0,
          displayName: 'Me',
        ),
        UserRoundRankFixtures.model(
          id: 2,
          participantId: 2,
          rank: 95.0,
          displayName: 'First Place',
        ),
        UserRoundRankFixtures.model(
          id: 3,
          participantId: 3,
          rank: 50.0,
          displayName: 'Third Place',
        ),
        UserRoundRankFixtures.model(
          id: 4,
          participantId: 4,
          rank: 25.0,
          displayName: 'Fourth Place',
        ),
      ];
      mockPropositionService.setupGetUserRoundRanks(ranks);

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      await tester.pumpAndSettle();

      // Should display all 4 user cards
      expect(find.byType(UserRankCard), findsNWidgets(4));
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('First Place'), findsOneWidget);
      expect(find.text('Third Place'), findsOneWidget);
      expect(find.text('Fourth Place'), findsOneWidget);
    });

    testWidgets('has zoom controls', (tester) async {
      final ranks = [
        UserRoundRankFixtures.model(
          id: 1,
          participantId: 1,
          rank: 75.0,
          displayName: 'User',
        ),
      ];
      mockPropositionService.setupGetUserRoundRanks(ranks);

      await tester.pumpApp(
        const UserLeaderboardGrid(
          roundId: 1,
          myParticipantId: 1,
        ),
        propositionService: mockPropositionService,
      );

      await tester.pumpAndSettle();

      // Should have zoom in and zoom out icons
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    });
  });
}
