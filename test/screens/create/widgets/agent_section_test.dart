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
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults(),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('AI Agents'), findsOneWidget);
    });

    testWidgets('displays enable toggle', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults(),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Enable AI agents'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('hides agent settings when disabled', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults(),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Number of agents'), findsNothing);
      expect(find.text('Customize agents individually'), findsNothing);
    });

    testWidgets('shows agent settings when enabled', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Number of agents'), findsOneWidget);
      expect(find.text('Customize agents individually'), findsOneWidget);
      expect(find.text('Same agent count for both phases'), findsOneWidget);
    });

    testWidgets('shows shared instructions field by default', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      expect(
        find.text('Instructions for all agents (optional)'),
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

      // Should show per-agent name and personality fields (1 agent default)
      expect(find.text('Agent 1 name'), findsOneWidget);
      expect(find.text('Personality (optional)'), findsNWidgets(1));

      // Should NOT show shared instructions field
      expect(
        find.text('Instructions for all agents (optional)'),
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
      expect(updated!.proposingAgentCount, 2);
      expect(updated!.agents.length, 2);
    });

    testWidgets('calls onChanged when decrementing agent count',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true).withCount(3),
          onChanged: (v) => updated = v,
        ),
      ));

      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.proposingAgentCount, 2);
      expect(updated!.agents.length, 2);
    });

    testWidgets('respects min of 1 for agent count', (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            proposingAgentCount: 1,
            agents: [const AgentConfig(name: 'Agent 1')],
          ),
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
            proposingAgentCount: 5,
            agents: List.generate(
                5, (i) => AgentConfig(name: 'Agent ${i + 1}')),
          ),
          onChanged: (_) {},
        ),
      ));

      final incrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add).first,
      );
      expect(incrementButton.onPressed, isNull);
    });

    testWidgets('hides rating count when useSameCount is true',
        (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(enabled: true),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Rating agents'), findsNothing);
    });

    testWidgets('shows rating count when useSameCount is false',
        (tester) async {
      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            useSameCount: false,
          ),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Rating agents'), findsOneWidget);
    });

    testWidgets('toggling useSameCount calls onChanged correctly',
        (tester) async {
      AgentSettings? updated;

      await tester.pumpWidget(_wrapWidget(
        AgentSection(
          settings: AgentSettings.defaults().copyWith(
            enabled: true,
            useSameCount: true,
          ),
          onChanged: (v) => updated = v,
        ),
      ));

      // Find the "Same agent count for both phases" switch
      final sameCountSwitch = find.widgetWithText(
        SwitchListTile,
        'Same agent count for both phases',
      );
      expect(sameCountSwitch, findsOneWidget);

      // The switch is the last SwitchListTile in the widget
      // Tap the switch within that SwitchListTile
      await tester.tap(sameCountSwitch);
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.useSameCount, isFalse);
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

      final customizeSwitch = find.widgetWithText(
        SwitchListTile,
        'Customize agents individually',
      );
      await tester.tap(customizeSwitch);
      await tester.pump();

      expect(updated, isNotNull);
      expect(updated!.customizeIndividually, isTrue);
    });
  });
}
