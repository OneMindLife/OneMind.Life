import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:onemind_app/widgets/name_section.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;

  setUp(() {
    auth = MockAuthService();
    when(() => auth.hasDisplayName).thenAnswer((_) {
      final n = auth.displayName;
      return n != null && n.isNotEmpty;
    });
    when(() => auth.setDisplayName(any())).thenAnswer((_) async {});
  });

  Widget harness(Widget child) {
    return ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
      ),
    );
  }

  group('NameSection', () {
    testWidgets('nameless user sees the inline name field', (tester) async {
      when(() => auth.displayName).thenReturn(null);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(harness(NameSection(
        controller: controller,
        asLabel: (name) => 'Joining as $name',
      )));

      expect(find.byKey(const Key('name-section-field')), findsOneWidget);
      expect(find.text("What's your name?"), findsOneWidget);
      expect(find.byKey(const Key('name-section-edit')), findsNothing);
    });

    testWidgets('named user sees the as-label with an edit pencil',
        (tester) async {
      when(() => auth.displayName).thenReturn('Joel');
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(harness(NameSection(
        controller: controller,
        asLabel: (name) => 'Joining as $name',
      )));

      expect(find.text('Joining as Joel'), findsOneWidget);
      expect(find.byKey(const Key('name-section-edit')), findsOneWidget);
      expect(find.byKey(const Key('name-section-field')), findsNothing);
    });

    testWidgets('edit pencil opens the shared dialog and saves',
        (tester) async {
      when(() => auth.displayName).thenReturn('Joel');
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(harness(NameSection(
        controller: controller,
        asLabel: (name) => 'Joining as $name',
      )));

      await tester.tap(find.byKey(const Key('name-section-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit name'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'New Name');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verify(() => auth.setDisplayName('New Name')).called(1);
    });
  });

  group('commitNameSection', () {
    testWidgets('returns stored name without saving when one exists',
        (tester) async {
      when(() => auth.displayName).thenReturn('Joel');
      final controller = TextEditingController(text: 'ignored');
      addTearDown(controller.dispose);

      String? result;
      await tester.pumpWidget(harness(Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () async {
            result = await commitNameSection(ref, controller);
          },
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(result, 'Joel');
      verifyNever(() => auth.setDisplayName(any()));
    });

    testWidgets('saves and returns the typed name when nameless',
        (tester) async {
      when(() => auth.displayName).thenReturn(null);
      final controller = TextEditingController(text: '  Typed Name  ');
      addTearDown(controller.dispose);

      String? result;
      await tester.pumpWidget(harness(Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () async {
            result = await commitNameSection(ref, controller);
          },
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(result, 'Typed Name');
      verify(() => auth.setDisplayName('Typed Name')).called(1);
    });

    testWidgets('returns null when nameless and the field is empty',
        (tester) async {
      when(() => auth.displayName).thenReturn(null);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      String? result = 'sentinel';
      await tester.pumpWidget(harness(Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () async {
            result = await commitNameSection(ref, controller);
          },
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(result, isNull);
      verifyNever(() => auth.setDisplayName(any()));
    });
  });
}
