import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/chat/widgets/seed_options_dialog.dart';
import 'package:onemind_app/services/chat_service.dart';

class MockChatService extends Mock implements ChatService {}

/// SeedOptionsDialog — the in-chat replacement for the old /create fork.
/// Leads with the group-proposes path (the prominent default); the poll
/// editor is behind a deliberate "I already have the options" tap.
/// Seed (>=2 options) → pop with the list (caller seeds + goes to voting);
/// any dismissal → pop null (caller starts proposing).
void main() {
  late MockChatService chatService;

  setUp(() {
    chatService = MockChatService();
    when(() => chatService.generateOptions(
          question: any(named: 'question'),
          count: any(named: 'count'),
        )).thenAnswer((_) async => const ['Pizza', 'Sushi', 'Tacos']);
  });

  Future<SeedDialogResult?Function()> pumpDialog(WidgetTester tester) async {
    SeedDialogResult? result;
    var resolved = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatServiceProvider.overrideWithValue(chatService)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await SeedOptionsDialog.show(context,
                        question: 'Where to eat?');
                    resolved = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => resolved ? result : throw StateError('dialog still open');
  }

  /// Reveal the poll editor (now behind a deliberate secondary tap).
  Future<void> revealOptions(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('seed-show-options')));
    await tester.pumpAndSettle();
  }

  testWidgets('default view: options editor hidden, "Get ideas from the group" '
      'is the primary action', (tester) async {
    await pumpDialog(tester);
    // The poll editor is NOT shown up front — group-proposes leads.
    expect(find.byKey(const Key('seed-option-0')), findsNothing);
    // "Get ideas from the group" is present AND the prominent FilledButton
    // (the easy default); "I already have the options" is the secondary tap.
    expect(find.byKey(const Key('seed-dialog-group')), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('seed-dialog-group'))),
        isA<FilledButton>());
    expect(find.byKey(const Key('seed-show-options')), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('seed-show-options'))),
        isA<TextButton>());
  });

  testWidgets('start-voting is disabled until 2 options are filled',
      (tester) async {
    await pumpDialog(tester);
    await revealOptions(tester);
    FilledButton startBtn() => tester
        .widget<FilledButton>(find.byKey(const Key('seed-dialog-start-voting')));
    expect(startBtn().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('seed-option-0')), 'Pizza');
    await tester.pumpAndSettle();
    expect(startBtn().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('seed-option-1')), 'Sushi');
    await tester.pumpAndSettle();
    expect(startBtn().onPressed, isNotNull);
  });

  testWidgets('seeding returns the filled options (trimmed, blanks dropped)',
      (tester) async {
    final result = await pumpDialog(tester);
    await revealOptions(tester);
    await tester.enterText(find.byKey(const Key('seed-option-0')), ' Pizza ');
    await tester.enterText(find.byKey(const Key('seed-option-1')), 'Sushi');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('seed-dialog-start-voting')));
    await tester.pumpAndSettle();
    expect(result()?.options, ['Pizza', 'Sushi']);
    expect(result()?.seeded, isTrue);
  });

  testWidgets('"Get ideas from the group" returns null', (tester) async {
    final result = await pumpDialog(tester);
    await tester.tap(find.byKey(const Key('seed-dialog-group')));
    await tester.pumpAndSettle();
    expect(result()?.options, isNull);
    expect(result()?.dismissMethod, 'group_button');
  });

  testWidgets('the X close returns null even with options typed',
      (tester) async {
    final result = await pumpDialog(tester);
    await revealOptions(tester);
    await tester.enterText(find.byKey(const Key('seed-option-0')), 'Pizza');
    await tester.enterText(find.byKey(const Key('seed-option-1')), 'Sushi');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('seed-dialog-close')));
    await tester.pumpAndSettle();
    expect(result()?.options, isNull);
    expect(result()?.dismissMethod, 'x');
  });

  testWidgets('Generate with AI fills empty rows (never a typed one)',
      (tester) async {
    await pumpDialog(tester);
    await revealOptions(tester);
    await tester.enterText(find.byKey(const Key('seed-option-0')), 'Burgers');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('seed-generate-ai')));
    await tester.pumpAndSettle();

    final texts = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((tf) => tf.controller?.text ?? '')
        .toList();
    expect(texts, contains('Burgers')); // typed row preserved
    expect(texts, containsAll(['Pizza', 'Sushi', 'Tacos']));
    verify(() => chatService.generateOptions(
        question: 'Where to eat?', count: any(named: 'count'))).called(1);
  });

  testWidgets('Add option appends a row', (tester) async {
    await pumpDialog(tester);
    await revealOptions(tester);
    expect(find.byKey(const Key('seed-option-3')), findsNothing);
    await tester.tap(find.byKey(const Key('seed-add-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('seed-option-3')), findsOneWidget);
  });

  testWidgets('"Get ideas instead" returns from the editor to the default',
      (tester) async {
    await pumpDialog(tester);
    await revealOptions(tester);
    expect(find.byKey(const Key('seed-option-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('seed-back-to-group')));
    await tester.pumpAndSettle();
    // Back to the default: editor hidden, group primary visible again.
    expect(find.byKey(const Key('seed-option-0')), findsNothing);
    expect(find.byKey(const Key('seed-dialog-group')), findsOneWidget);
  });
}
