import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/widgets/proposition_limits_section.dart';

void main() {
  group('PropositionLimitsSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Proposition Limits'), findsOneWidget);
    });

    testWidgets('displays input label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Propositions per user'), findsOneWidget);
    });

    testWidgets('displays singular helper text when value is 1',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Each user can submit 1 proposition per round'),
        findsOneWidget,
      );
    });

    testWidgets('displays plural helper text when value > 1', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 3,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('Each user can submit up to 3 propositions per round'),
        findsOneWidget,
      );
    });

    testWidgets('displays current value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 5,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('calls onChanged when incrementing', (tester) async {
      int? updatedValue;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 3,
              onChanged: (v) => updatedValue = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(updatedValue, 4);
    });

    testWidgets('calls onChanged when decrementing', (tester) async {
      int? updatedValue;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 3,
              onChanged: (v) => updatedValue = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(updatedValue, 2);
    });

    testWidgets('respects min limit of 1', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final decrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(decrementButton.onPressed, isNull);
    });

    testWidgets('respects max limit of 20', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: PropositionLimitsSection(
              propositionsPerUser: 20,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final incrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(incrementButton.onPressed, isNull);
    });
  });
}
