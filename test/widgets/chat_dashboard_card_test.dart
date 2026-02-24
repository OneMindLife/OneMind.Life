import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/round.dart';
import 'package:onemind_app/widgets/chat_dashboard_card.dart';

void main() {
  Widget buildCard({
    String name = 'Test Chat',
    String initialMessage = 'What should we discuss?',
    VoidCallback? onTap,
    int participantCount = 5,
    RoundPhase? phase,
    bool isPaused = false,
    Duration? timeRemaining,
    List<String> translationLanguages = const ['en'],
    Color? phaseBarColorOverride,
    Widget? trailing,
    String? semanticLabel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChatDashboardCard(
          name: name,
          initialMessage: initialMessage,
          onTap: onTap ?? () {},
          participantCount: participantCount,
          phase: phase,
          isPaused: isPaused,
          timeRemaining: timeRemaining,
          translationLanguages: translationLanguages,
          phaseBarColorOverride: phaseBarColorOverride,
          trailing: trailing,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }

  group('ChatDashboardCard', () {
    testWidgets('renders name and initial message', (tester) async {
      await tester.pumpWidget(buildCard(
        name: 'My Chat',
        initialMessage: 'Important question',
      ));
      expect(find.text('My Chat'), findsOneWidget);
      expect(find.text('Important question'), findsOneWidget);
    });

    testWidgets('renders participant count', (tester) async {
      await tester.pumpWidget(buildCard(participantCount: 42));
      expect(find.text('42'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('renders phase badge for proposing', (tester) async {
      await tester.pumpWidget(buildCard(phase: RoundPhase.proposing));
      expect(find.text('Proposing'), findsOneWidget);
    });

    testWidgets('renders phase badge for rating', (tester) async {
      await tester.pumpWidget(buildCard(phase: RoundPhase.rating));
      expect(find.text('Rating'), findsOneWidget);
    });

    testWidgets('renders Idle when no phase', (tester) async {
      await tester.pumpWidget(buildCard(phase: null));
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('renders Paused when isPaused', (tester) async {
      await tester.pumpWidget(
          buildCard(phase: RoundPhase.proposing, isPaused: true));
      expect(find.text('Paused'), findsOneWidget);
    });

    testWidgets('renders countdown when timeRemaining is set', (tester) async {
      await tester.pumpWidget(buildCard(
        phase: RoundPhase.proposing,
        timeRemaining: const Duration(minutes: 3, seconds: 42),
      ));
      expect(find.text('3m 42s'), findsOneWidget);
    });

    testWidgets('does not render countdown when no timer', (tester) async {
      await tester.pumpWidget(buildCard(
        phase: RoundPhase.proposing,
        timeRemaining: null,
      ));
      expect(find.text('3m 42s'), findsNothing);
    });

    testWidgets('renders trailing widget', (tester) async {
      await tester.pumpWidget(buildCard(
        trailing: const Chip(label: Text('Joined')),
      ));
      expect(find.text('Joined'), findsOneWidget);
    });

    testWidgets('invokes onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildCard(onTap: () => tapped = true));
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('renders language label', (tester) async {
      await tester.pumpWidget(buildCard(
        translationLanguages: ['en', 'es'],
      ));
      // LanguageUtils.shortLabel returns comma-separated native names
      expect(find.textContaining('English'), findsOneWidget);
    });
  });

  group('ChatDashboardCard.phaseBarColor', () {
    testWidgets('returns override when provided', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Builder(
        builder: (context) {
          final color = ChatDashboardCard.phaseBarColor(
            context,
            override: Colors.red,
          );
          expect(color, Colors.red);
          return const SizedBox();
        },
      )));
    });
  });
}
