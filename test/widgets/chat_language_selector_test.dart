import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/chat_language_selector.dart';

import '../helpers/pump_app.dart';

void main() {
  group('ChatLanguageSelector', () {
    testWidgets('hidden when only 1 language available', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ChatLanguageSelector(
            availableLanguages: const ['en'],
            currentLanguageCode: 'en',
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render SizedBox.shrink — no translate icon
      expect(find.byIcon(Icons.translate), findsNothing);
    });

    testWidgets('hidden when 0 languages available', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ChatLanguageSelector(
            availableLanguages: const [],
            currentLanguageCode: 'en',
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.translate), findsNothing);
    });

    testWidgets('shows translate icon when 2+ languages', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ChatLanguageSelector(
            availableLanguages: const ['en', 'es'],
            currentLanguageCode: 'en',
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.translate), findsOneWidget);
    });

    testWidgets('popup shows all available languages with names',
        (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ChatLanguageSelector(
            availableLanguages: const ['en', 'es', 'fr'],
            currentLanguageCode: 'en',
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
    });

    testWidgets('shows check mark next to current language', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ChatLanguageSelector(
            availableLanguages: const ['en', 'es'],
            currentLanguageCode: 'en',
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      // Check icon should appear once (next to English)
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('calls onLanguageChanged when selecting a language',
        (tester) async {
      String? selectedCode;

      await tester.pumpApp(
        Scaffold(
          body: ChatLanguageSelector(
            availableLanguages: const ['en', 'es', 'pt'],
            currentLanguageCode: 'en',
            onLanguageChanged: (code) => selectedCode = code,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Español'));
      await tester.pumpAndSettle();

      expect(selectedCode, 'es');
    });

    testWidgets('shows all 5 supported languages when all available',
        (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ChatLanguageSelector(
            availableLanguages: const ['en', 'es', 'pt', 'fr', 'de'],
            currentLanguageCode: 'en',
            onLanguageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      expect(find.text('Português'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
    });
  });
}
