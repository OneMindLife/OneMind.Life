import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/widgets/language_selector.dart';

import '../helpers/pump_app.dart';

class _MockLanguageService extends Mock implements LanguageService {
  @override
  String getCurrentLanguage() => 'en';

  @override
  List<String> getSpokenLanguages() => ['en'];

  @override
  Future<void> setSpokenLanguages(List<String> codes) async {}
}

void main() {
  final languageOverrides = <Override>[
    spokenLanguagesProvider.overrideWith((ref) {
      return SpokenLanguagesNotifier(_MockLanguageService());
    }),
  ];

  group('LanguageSelector', () {
    group('compact mode', () {
      testWidgets('displays globe icon', (tester) async {
        await tester.pumpApp(
          const Scaffold(body: LanguageSelector(compact: true)),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.language), findsOneWidget);
      });

      testWidgets('tapping opens enhanced language dialog', (tester) async {
        await tester.pumpApp(
          const Scaffold(body: LanguageSelector(compact: true)),
          additionalOverrides: languageOverrides,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.language));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Primary Language'), findsOneWidget);
      });
    });

    group('full mode', () {
      testWidgets('displays language name with dropdown arrow', (tester) async {
        await tester.pumpApp(
          const Scaffold(body: LanguageSelector(compact: false)),
        );
        await tester.pumpAndSettle();

        expect(find.text('English'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
      });
    });
  });

  group('Enhanced Language Dialog', () {
    testWidgets('has 5 radio buttons and 4 checkboxes', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelector(compact: true)),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      // 5 radio buttons for primary language
      expect(find.byType(RadioListTile<String>), findsNWidgets(5));
      // 4 checkboxes for "I also speak" (primary excluded)
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
    });

    testWidgets('shows "I also speak" section', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelector(compact: true)),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      expect(find.text('I also speak'), findsOneWidget);
    });

    testWidgets('English is selected as primary by default', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelector(compact: true)),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      final radioTiles = tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>));
      final englishTile = radioTiles.firstWhere((t) => t.value == 'en');
      expect(englishTile.groupValue, 'en');
    });

    testWidgets('selecting different primary updates groupValue',
        (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelector(compact: true)),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      // Tap the Spanish (es) RadioListTile specifically
      final esRadioFinder = find.byWidgetPredicate(
        (w) => w is RadioListTile<String> && w.value == 'es',
      );
      await tester.ensureVisible(esRadioFinder);
      await tester.pumpAndSettle();
      await tester.tap(esRadioFinder);
      await tester.pumpAndSettle();

      final radioTiles = tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>));
      final esTile = radioTiles.firstWhere((t) => t.value == 'es');
      expect(esTile.groupValue, 'es');
    });

    testWidgets('switching primary excludes it from checkboxes',
        (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelector(compact: true)),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      // Default: English is primary → 4 checkboxes (es, pt, fr, de)
      expect(find.byType(CheckboxListTile), findsNWidgets(4));

      // Switch to Spanish as primary
      final esRadioFinder = find.byWidgetPredicate(
        (w) => w is RadioListTile<String> && w.value == 'es',
      );
      await tester.ensureVisible(esRadioFinder);
      await tester.pumpAndSettle();
      await tester.tap(esRadioFinder);
      await tester.pumpAndSettle();

      // Still 4 checkboxes (en, pt, fr, de — no es)
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
    });

    testWidgets('dialog has Cancel and Save buttons', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelector(compact: true)),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelector(compact: true)),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('LanguageSelectorTile', () {
    testWidgets('displays language icon, label, and current language',
        (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelectorTile()),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.language), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('tapping opens enhanced language dialog', (tester) async {
      await tester.pumpApp(
        const Scaffold(body: LanguageSelectorTile()),
        additionalOverrides: languageOverrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Primary Language'), findsOneWidget);
    });
  });
}
