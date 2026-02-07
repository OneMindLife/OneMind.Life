import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/consensus_section.dart';

void main() {
  group('ConsensusSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
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

    // Confirmation rounds input is hidden from UI - defaults to 2

    testWidgets('displays show results switch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
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

    testWidgets('calls onChanged when toggling show results', (tester) async {
      ConsensusSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
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
  });
}
