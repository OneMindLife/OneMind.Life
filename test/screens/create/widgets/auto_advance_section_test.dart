import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/auto_advance_section.dart';

void main() {
  group('AutoAdvanceSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: AutoAdvanceSection(
              settings: AutoAdvanceSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Updated label: "End Phase Early" instead of "Auto-Advance At"
      expect(find.text('End Phase Early'), findsOneWidget);
    });

    testWidgets('displays helper text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: AutoAdvanceSection(
              settings: AutoAdvanceSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Updated label: "Phase can end early when thresholds are reached"
      expect(
        find.text('Phase can end early when thresholds are reached'),
        findsOneWidget,
      );
    });

    testWidgets('displays both enable switches', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: AutoAdvanceSection(
              settings: AutoAdvanceSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Updated labels for enable switches (mirrored structure)
      expect(find.text('Enable for ideas'), findsOneWidget);
      expect(find.text('Enable for ratings'), findsOneWidget);
    });

    testWidgets('hides proposing options when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: false,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: false,
                  ratingThresholdPercent: 80,
                  ratingThresholdCount: 5,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('When 80% of participants submit'), findsNothing);
    });

    testWidgets('shows proposing options when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: true,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: false,
                  ratingThresholdPercent: 80,
                  ratingThresholdCount: 5,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Simplified: just count input, no percentage slider
      // Updated label: "Ideas needed" (mirrors Required Participation section)
      expect(find.text('Ideas needed'), findsOneWidget);
    });

    testWidgets('shows rating options when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: false,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: true,
                  ratingThresholdPercent: 75,
                  ratingThresholdCount: 10,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Updated label: "Ratings needed" (mirrors Required Participation section)
      expect(find.text('Ratings needed'), findsOneWidget);
    });

    testWidgets('calls onChanged when toggling proposing', (tester) async {
      AutoAdvanceSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                // Start with proposing disabled to test turning it ON
                settings: const AutoAdvanceSettings(
                  enableProposing: false,
                  proposingThresholdPercent: 100,
                  proposingThresholdCount: 3,
                  enableRating: false,
                  ratingThresholdPercent: 100,
                  ratingThresholdCount: 2,
                ),
                onChanged: (v) => updatedSettings = v,
              ),
            ),
          ),
        ),
      );

      // Tap the proposing switch
      final switches = find.byType(Switch);
      await tester.tap(switches.first);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.enableProposing, isTrue);
    });

    testWidgets('calls onChanged when toggling rating', (tester) async {
      AutoAdvanceSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                // Start with rating disabled to test turning it ON
                settings: const AutoAdvanceSettings(
                  enableProposing: false,
                  proposingThresholdPercent: 100,
                  proposingThresholdCount: 3,
                  enableRating: false,
                  ratingThresholdPercent: 100,
                  ratingThresholdCount: 2,
                ),
                onChanged: (v) => updatedSettings = v,
              ),
            ),
          ),
        ),
      );

      // Tap the rating switch (second one)
      final switches = find.byType(Switch);
      await tester.tap(switches.last);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.enableRating, isTrue);
    });

    testWidgets('shows both option sections when both enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: true,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 5,
                  enableRating: true,
                  ratingThresholdPercent: 75,
                  ratingThresholdCount: 10,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Updated labels (mirrors Required Participation section)
      expect(find.text('Ideas needed'), findsOneWidget);
      expect(find.text('Ratings needed'), findsOneWidget);
    });

    testWidgets('shows proposing threshold preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: true,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 4,
                  enableRating: false,
                  ratingThresholdPercent: 80,
                  ratingThresholdCount: 5,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Should show the simplified proposing threshold preview
      // Format: "Phase ends early when 4 ideas are submitted"
      expect(
        find.textContaining('4 ideas are submitted'),
        findsOneWidget,
      );
    });

    testWidgets('shows rating threshold preview with clear text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutoAdvanceSection(
                settings: const AutoAdvanceSettings(
                  enableProposing: false,
                  proposingThresholdPercent: 80,
                  proposingThresholdCount: 4,
                  enableRating: true,
                  ratingThresholdPercent: 80,
                  ratingThresholdCount: 3,
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // Should show the rating threshold preview
      // Format: "Phase ends early when each idea has 3 ratings"
      expect(
        find.textContaining('each idea has 3 ratings'),
        findsOneWidget,
      );
    });
  });
}
