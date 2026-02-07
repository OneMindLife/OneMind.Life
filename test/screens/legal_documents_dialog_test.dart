import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/legal/legal_documents_dialog.dart';

/// Mock LanguageService for testing
class _MockLanguageService extends Mock implements LanguageService {
  @override
  String getCurrentLanguage() => 'en';

  @override
  Future<String> initializeLanguage() async => 'en';

  @override
  Future<bool> updateLanguage(String languageCode) async => true;
}

/// Test LocaleNotifier that uses mock LanguageService
class _TestLocaleNotifier extends LocaleNotifier {
  _TestLocaleNotifier() : super(_MockLanguageService());
}

void main() {
  group('LegalDocumentsDialog', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showLegalDocumentsDialog(context),
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/privacy',
            builder: (context, state) => const Scaffold(
              body: Center(child: Text('Privacy Policy Page')),
            ),
          ),
          GoRoute(
            path: '/terms',
            builder: (context, state) => const Scaffold(
              body: Center(child: Text('Terms of Service Page')),
            ),
          ),
        ],
      );
    });

    Widget buildTestWidget() {
      return ProviderScope(
        overrides: [
          localeProvider.overrideWith((ref) => _TestLocaleNotifier()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
    }

    testWidgets('displays dialog title', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Legal'), findsOneWidget);
    });

    testWidgets('displays Privacy Policy option', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('displays Terms of Service option', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Terms of Service'), findsOneWidget);
    });

    testWidgets('displays close button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // MaterialLocalizations provides 'Close' button text
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text('Legal'), findsNothing);
    });

    testWidgets('tapping Privacy Policy navigates to /privacy', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy Page'), findsOneWidget);
    });

    testWidgets('tapping Terms of Service navigates to /terms', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();

      expect(find.text('Terms of Service Page'), findsOneWidget);
    });

    testWidgets('displays privacy tip icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.privacy_tip_outlined), findsOneWidget);
    });

    testWidgets('displays description icon for Terms', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });

    testWidgets('displays chevron icons for navigation', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    });
  });
}
