import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/agent_section.dart';

Widget _wrapWidget(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('AgentSection', () {
    testWidgets('displays first question', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults(),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Start with AI agents?'), findsOneWidget);
    });

    testWidgets('displays enable toggle', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults(),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Start with AI agents?'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('hides agent settings when disabled', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults(),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('How many agents?'), findsNothing);
      expect(find.text('Customize each agent separately?'), findsNothing);
    });

    testWidgets('shows agent settings when enabled', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('How many agents?'), findsOneWidget);
      expect(find.text('Customize each agent separately?'), findsOneWidget);
      expect(find.text('Should agents also rate?'), findsOneWidget);
    });

    testWidgets('shows shared instructions field by default', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      expect(
        find.byKey(const Key('agent_shared_instructions')),
        findsOneWidget,
      );
    });

    testWidgets('shows per-agent fields when customizeIndividually is on',
        (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            customizeIndividually: true,
          ),
          onChanged: (_) {},
        ),
      ));

      // Should show per-agent name and personality fields (2 agents default)
      expect(find.text('Agent 1 name'), findsOneWidget);
      expect(find.text('Agent 2 name'), findsOneWidget);
      expect(find.text('Personality (optional)'), findsNWidgets(2));

      // Should NOT show shared instructions field
      expect(
        find.byKey(const Key('agent_shared_instructions')),
        findsNothing,
      );
    });

    testWidgets('calls onChanged when toggling enabled', (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults(),
          onChanged: (v) => updated = v,
        ),
      ));

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.enabled, isTrue);
    });

    testWidgets('calls onChanged when incrementing agent count',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (v) => updated = v,
        ),
      ));

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.agentCount, 3);
      expect(updated!.agents.length, 3);
    });

    testWidgets('calls onChanged when decrementing agent count',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true).withCount(4),
          onChanged: (v) => updated = v,
        ),
      ));

      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.agentCount, 3);
      expect(updated!.agents.length, 3);
    });

    testWidgets('respects min of 2 for agent count', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      final decrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove).first,
      );
      expect(decrementButton.onPressed, isNull);
    });

    testWidgets('respects max of 5 for agent count', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
          ).withCount(5),
          onChanged: (_) {},
        ),
      ));

      final incrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add).first,
      );
      expect(incrementButton.onPressed, isNull);
    });

    testWidgets('shows agents also rate toggle when enabled',
        (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Should agents also rate?'), findsOneWidget);
      expect(
        find.text('Yes, agents rate alongside humans'),
        findsOneWidget,
      );
    });

    testWidgets('toggling agentsAlsoRate calls onChanged correctly',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            agentsAlsoRate: true,
          ),
          onChanged: (v) => updated = v,
        ),
      ));

      // "Should agents also rate?" is the 2nd switch (index 1)
      final switches = find.byType(Switch);
      await tester.tap(switches.at(1));
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.agentsAlsoRate, isFalse);
    });

    testWidgets('calls onChanged when toggling customizeIndividually',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (v) => updated = v,
        ),
      ));

      // "Customize each agent separately?" is the 3rd switch (index 2)
      final switches = find.byType(Switch);
      await tester.tap(switches.at(2));
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.customizeIndividually, isTrue);
    });
  });
}
