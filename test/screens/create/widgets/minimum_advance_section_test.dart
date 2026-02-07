import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/minimum_advance_section.dart';
import 'package:onemind_app/models/models.dart';

void main() {
  group('MinimumAdvanceSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Updated label: "Required Participation" instead of "Minimum to Advance"
      expect(find.text('Required Participation'), findsOneWidget);
    });

    testWidgets('displays helper text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Updated label: "Phase won't end until requirements are met"
      expect(
        find.text("Phase won't end until requirements are met"),
        findsOneWidget,
      );
    });

    testWidgets('displays proposing minimum input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Updated label: "Ideas needed" instead of "Proposing minimum"
      expect(find.text('Ideas needed'), findsOneWidget);
    });

    testWidgets('displays rating minimum input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Updated label: "Ratings needed" instead of "Avg ratings needed"
      expect(find.text('Ratings needed'), findsOneWidget);
    });

    testWidgets('displays default values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Default proposingMinimum is 3 (users can't rate own, need 2+ visible)
      // Default ratingMinimum is 2
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('displays custom values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: const MinimumSettings(
                proposingMinimum: 3,
                ratingMinimum: 5,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('calls onChanged when incrementing proposing minimum',
        (tester) async {
      MinimumSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      // Tap the first add button (proposing)
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.proposingMinimum, 4); // 3 + 1 (default is 3)
    });

    testWidgets('calls onChanged when incrementing rating minimum',
        (tester) async {
      MinimumSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (v) => updatedSettings = v,
            ),
          ),
        ),
      );

      // Tap the last add button (rating)
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();

      expect(updatedSettings, isNotNull);
      expect(updatedSettings!.ratingMinimum, 3); // 2 + 1
    });

    testWidgets('shows dynamic helper text in auto mode with threshold',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MinimumAdvanceSection(
                settings: MinimumSettings.defaults(),
                onChanged: (_) {},
                startMode: StartMode.auto,
                autoStartCount: 5,
                proposingDuration: 300, // 5 minutes
                proposingThreshold: 4,
              ),
            ),
          ),
        ),
      );

      // Should show the dynamic phase flow explanation
      expect(
        find.textContaining('Each phase runs for up to'),
        findsOneWidget,
      );
    });

    testWidgets('hides dynamic helper text in manual mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: MinimumAdvanceSection(
              settings: MinimumSettings.defaults(),
              onChanged: (_) {},
              startMode: StartMode.manual,
            ),
          ),
        ),
      );

      // Should NOT show the dynamic phase flow explanation in manual mode
      expect(
        find.textContaining('Each phase runs for up to'),
        findsNothing,
      );
    });

    // Note: max limit is now 100 (not capped by autoStartCount)
    // because more participants can join after the chat starts
  });
}
