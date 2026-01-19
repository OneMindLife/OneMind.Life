import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/chat/widgets/rating_screen_embedded.dart';
import 'package:onemind_app/services/proposition_service.dart';

import '../../../fixtures/round_fixtures.dart';
import '../../../fixtures/participant_fixtures.dart';
import '../../../fixtures/proposition_fixtures.dart';

class MockPropositionService extends Mock implements PropositionService {}

void main() {
  late MockPropositionService mockPropositionService;

  setUp(() {
    mockPropositionService = MockPropositionService();
  });

  Widget createTestWidget({
    required Widget child,
  }) {
    return ProviderScope(
      overrides: [
        propositionServiceProvider.overrideWithValue(mockPropositionService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: child,
      ),
    );
  }

  group('RatingScreenEmbedded', () {
    testWidgets('displays app bar with correct title', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 2);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      expect(find.text('Rate Propositions'), findsOneWidget);
    });

    testWidgets('displays all propositions', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = [
        PropositionFixtures.model(id: 1, content: 'First proposition'),
        PropositionFixtures.model(id: 2, content: 'Second proposition'),
        PropositionFixtures.model(id: 3, content: 'Third proposition'),
      ];

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      expect(find.text('First proposition'), findsOneWidget);
      expect(find.text('Second proposition'), findsOneWidget);
      expect(find.text('Third proposition'), findsOneWidget);
    });

    testWidgets('displays sliders for each proposition', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 2);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      expect(find.byType(Slider), findsNWidgets(2));
    });

    testWidgets('sliders default to 50', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 1);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      // The default rating value should be displayed
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('displays min and max labels', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 1);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      expect(find.text('0'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('displays Submit Ratings button', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 1);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      expect(find.text('Submit Ratings'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('submits ratings when button pressed', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model(id: 5);
      final propositions = [
        PropositionFixtures.model(id: 10, content: 'Prop 1'),
        PropositionFixtures.model(id: 20, content: 'Prop 2'),
      ];
      var completeCalled = false;

      when(() => mockPropositionService.submitRatings(
            propositionIds: any(named: 'propositionIds'),
            ratings: any(named: 'ratings'),
            participantId: any(named: 'participantId'),
          )).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () => completeCalled = true,
        ),
      ));

      await tester.tap(find.text('Submit Ratings'));
      // Use pump instead of pumpAndSettle to avoid timeout with onComplete callback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockPropositionService.submitRatings(
            propositionIds: [10, 20],
            ratings: [50, 50], // Default ratings
            participantId: 5,
          )).called(1);
      expect(completeCalled, isTrue);
    });

    testWidgets('shows loading indicator while submitting', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 1);

      // Use a completer to control the future
      final completer = Completer<void>();
      when(() => mockPropositionService.submitRatings(
            propositionIds: any(named: 'propositionIds'),
            ratings: any(named: 'ratings'),
            participantId: any(named: 'participantId'),
          )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      await tester.tap(find.text('Submit Ratings'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future to avoid pending timer
      completer.complete();
      // Use pump with duration instead of pumpAndSettle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('shows error snackbar on submission failure', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 1);

      when(() => mockPropositionService.submitRatings(
            propositionIds: any(named: 'propositionIds'),
            ratings: any(named: 'ratings'),
            participantId: any(named: 'participantId'),
          )).thenThrow(Exception('Network error'));

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      await tester.tap(find.text('Submit Ratings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to submit ratings'), findsOneWidget);
    });

    testWidgets('disables button while submitting', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      final propositions = PropositionFixtures.list(count: 1);

      // Use a completer to control the future
      final completer = Completer<void>();
      when(() => mockPropositionService.submitRatings(
            propositionIds: any(named: 'propositionIds'),
            ratings: any(named: 'ratings'),
            participantId: any(named: 'participantId'),
          )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      await tester.tap(find.text('Submit Ratings'));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      // Complete the future to avoid pending timer
      completer.complete();
      // Use pump with duration instead of pumpAndSettle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('proposition cards are scrollable', (tester) async {
      final round = RoundFixtures.rating();
      final participant = ParticipantFixtures.model();
      // Create many propositions to test scrolling
      final propositions = PropositionFixtures.list(count: 10);

      await tester.pumpWidget(createTestWidget(
        child: RatingScreenEmbedded(
          round: round,
          participant: participant,
          propositions: propositions,
          onComplete: () {},
        ),
      ));

      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
