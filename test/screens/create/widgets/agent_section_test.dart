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
      expect(find.text('Customize agents?'), findsNothing);
    });

    testWidgets('shows agent settings when enabled', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Should agents also rate?'), findsOneWidget);
      expect(find.text('How many agents?'), findsOneWidget);
      expect(find.text('Customize agents?'), findsOneWidget);
    });

    testWidgets('does not show shared instructions when customizeAgents is off',
        (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      // customizeAgents defaults to false, so no instructions field
      expect(
        find.byKey(const Key('agent_shared_instructions')),
        findsNothing,
      );
      expect(find.text('Customize each agent separately?'), findsNothing);
    });

    testWidgets('shows shared instructions when customizeAgents is on',
        (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            customizeAgents: true,
          ),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Customize each agent separately?'), findsOneWidget);
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
            customizeAgents: true,
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

    testWidgets('shows correct question order when enabled',
        (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      // Find all Switches (no longer using SwitchListTile)
      final switches = find.byType(Switch);
      // Enable, Agents also rate, Customize agents = 3 switches
      expect(switches, findsNWidgets(3));

      // Verify question texts exist in correct order
      expect(find.text('Start with AI agents?'), findsOneWidget);
      expect(find.text('Should agents also rate?'), findsOneWidget);
      expect(find.text('Customize agents?'), findsOneWidget);
    });

    testWidgets('toggling customizeAgents off resets customizeIndividually',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            customizeAgents: true,
            customizeIndividually: true,
          ),
          onChanged: (v) => updated = v,
        ),
      ));

      // Tap the "Customize agents?" toggle to turn it off
      // Find the Switch that corresponds to "Customize agents?"
      final switches = find.byType(Switch);
      // Order: Use AI agents?, Should agents also rate?, Customize agents?, Customize each agent separately?
      await tester.tap(switches.at(2));
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.customizeAgents, isFalse);
      expect(updated!.customizeIndividually, isFalse);
    });

    testWidgets('calls onChanged when toggling customizeAgents',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (v) => updated = v,
        ),
      ));

      // "Customize agents?" is the 3rd switch (index 2)
      final switches = find.byType(Switch);
      await tester.tap(switches.at(2));
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.customizeAgents, isTrue);
    });

    testWidgets('calls onChanged when toggling customizeIndividually',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            customizeAgents: true,
          ),
          onChanged: (v) => updated = v,
        ),
      ));

      // "Customize each agent separately?" is the 4th switch (index 3)
      final switches = find.byType(Switch);
      await tester.tap(switches.at(3));
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.customizeIndividually, isTrue);
    });
  });
}
