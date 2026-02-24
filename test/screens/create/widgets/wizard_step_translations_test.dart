import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';
import 'package:onemind_app/screens/create/widgets/wizard_step_translations.dart';

void main() {
  Widget buildWidget({
    required TranslationSettings settings,
    required void Function(TranslationSettings) onChanged,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: WizardStepTranslations(
          translationSettings: settings,
          onTranslationSettingsChanged: onChanged,
          onBack: () {},
          onContinue: () {},
        ),
      ),
    );
  }

  group('WizardStepTranslations', () {
    testWidgets('displays title and subtitle', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          settings: TranslationSettings.defaults(),
          onChanged: (_) {},
        ),
      );

      expect(find.text('Languages'), findsOneWidget);
      expect(
        find.text('Choose what languages this chat supports'),
        findsOneWidget,
      );
    });

    testWidgets('displays language icon', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          settings: TranslationSettings.defaults(),
          onChanged: (_) {},
        ),
      );

      expect(find.byIcon(Icons.language), findsOneWidget);
    });

    testWidgets('single language toggle defaults to ON', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          settings: TranslationSettings.defaults(),
          onChanged: (_) {},
        ),
      );

      final switchWidget = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      // Single language = !enabled = !false = true
      expect(switchWidget.value, true);
    });

    testWidgets('shows dropdown when single language mode', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          settings: TranslationSettings.defaults(),
          onChanged: (_) {},
        ),
      );

      // Should show dropdown, not checkboxes
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('switching to multi-language shows checkboxes', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          // Multi-language: enabled=true, all languages
          settings: const TranslationSettings(
            enabled: true,
            languages: {'en', 'es', 'pt', 'fr', 'de'},
          ),
          onChanged: (_) {},
        ),
      );

      // Should show checkboxes, not dropdown
      expect(find.byType(CheckboxListTile), findsNWidgets(5));
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      expect(find.text('Português'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
    });

    testWidgets('toggling switch to OFF enables multi-language', (tester) async {
      TranslationSettings? captured;
      await tester.pumpWidget(
        buildWidget(
          settings: TranslationSettings.defaults(),
          onChanged: (s) => captured = s,
        ),
      );

      // Tap the switch to turn off single-language mode
      await tester.tap(find.byType(SwitchListTile));
      expect(captured?.enabled, true);
      expect(captured?.languages, {'en', 'es', 'pt', 'fr', 'de'});
    });

    testWidgets('unchecking a language in multi-language mode', (tester) async {
      TranslationSettings? captured;
      await tester.pumpWidget(
        buildWidget(
          settings: const TranslationSettings(
            enabled: true,
            languages: {'en', 'es', 'pt', 'fr', 'de'},
          ),
          onChanged: (s) => captured = s,
        ),
      );

      // Scroll to Deutsch and tap it
      await tester.scrollUntilVisible(find.text('Deutsch'), 100);
      await tester.tap(find.text('Deutsch'));
      expect(captured?.languages, {'en', 'es', 'pt', 'fr'});
    });

    testWidgets('prevents removing below 2 languages in multi-language mode',
        (tester) async {
      TranslationSettings? captured;
      await tester.pumpWidget(
        buildWidget(
          settings: const TranslationSettings(
            enabled: true,
            languages: {'en', 'es'},
          ),
          onChanged: (s) => captured = s,
        ),
      );

      // Try unchecking English - should keep both since minimum is 2
      await tester.tap(find.text('English'));
      expect(captured?.languages, {'en', 'es'});
    });

    testWidgets('displays back and continue buttons', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          settings: TranslationSettings.defaults(),
          onChanged: (_) {},
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('shows auto-translate hint in multi-language mode',
        (tester) async {
      await tester.pumpWidget(
        buildWidget(
          settings: const TranslationSettings(
            enabled: true,
            languages: {'en', 'es', 'pt', 'fr', 'de'},
          ),
          onChanged: (_) {},
        ),
      );

      await tester.scrollUntilVisible(
        find.text(
          'Propositions will be automatically translated between all selected languages',
        ),
        100,
      );
      expect(
        find.text(
          'Propositions will be automatically translated between all selected languages',
        ),
        findsOneWidget,
      );
    });
  });
}
