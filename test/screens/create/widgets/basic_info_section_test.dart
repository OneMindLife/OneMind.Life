import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/widgets/basic_info_section.dart';

import '../../../helpers/pump_app.dart';

// Import the constant to use in tests
const _testMaxLength = kChatNameMaxLength;

void main() {
  late TextEditingController nameController;
  late TextEditingController messageController;

  setUp(() {
    nameController = TextEditingController();
    messageController = TextEditingController();
  });

  tearDown(() {
    nameController.dispose();
    messageController.dispose();
  });

  Widget createTestWidget() {
    return Form(
      child: SingleChildScrollView(
        child: BasicInfoSection(
          nameController: nameController,
          messageController: messageController,
        ),
      ),
    );
  }

  group('BasicInfoSection', () {
    testWidgets('displays section header', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      expect(find.text('Basic Info'), findsOneWidget);
    });

    testWidgets('displays chat name field', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      expect(find.text('Chat Name *'), findsOneWidget);
      expect(find.text('e.g., Team Lunch Friday'), findsOneWidget);
    });

    testWidgets('displays initial message field', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      expect(find.text('Initial Message *'), findsOneWidget);
      expect(find.text('The opening topic or question'), findsOneWidget);
    });

    testWidgets('allows entering chat name', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Chat Name *'),
        'Test Chat',
      );

      expect(nameController.text, 'Test Chat');
    });

    testWidgets('allows entering initial message', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Initial Message *'),
        'What should we discuss?',
      );

      expect(messageController.text, 'What should we discuss?');
    });

    testWidgets('validates empty chat name', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpApp(
        Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                BasicInfoSection(
                  nameController: nameController,
                  messageController: messageController,
                ),
                ElevatedButton(
                  onPressed: () => formKey.currentState!.validate(),
                  child: const Text('Validate'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Validate'));
      await tester.pump();

      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('validates empty initial message', (tester) async {
      nameController.text = 'Valid Name';
      final formKey = GlobalKey<FormState>();

      await tester.pumpApp(
        Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                BasicInfoSection(
                  nameController: nameController,
                  messageController: messageController,
                ),
                ElevatedButton(
                  onPressed: () => formKey.currentState!.validate(),
                  child: const Text('Validate'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Validate'));
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('passes validation with valid inputs', (tester) async {
      nameController.text = 'Valid Name';
      messageController.text = 'Valid Message';

      bool isValid = false;
      final formKey = GlobalKey<FormState>();

      await tester.pumpApp(
        Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                BasicInfoSection(
                  nameController: nameController,
                  messageController: messageController,
                ),
                ElevatedButton(
                  onPressed: () {
                    isValid = formKey.currentState!.validate();
                  },
                  child: const Text('Validate'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Validate'));
      await tester.pump();

      expect(isValid, isTrue);
    });

    testWidgets('chat name field has character limit configured', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      // Verify the constant is set to expected value
      expect(_testMaxLength, 50);

      // The maxLength is enforced via the TextField inside TextFormField
      // We verify this through behavior tests below
    });

    testWidgets('chat name is limited to max length characters', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      // Create a string longer than the max length
      final longName = 'A' * (_testMaxLength + 20);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Chat Name *'),
        longName,
      );

      // The controller should only have maxLength characters
      expect(nameController.text.length, _testMaxLength);
    });

    testWidgets('chat name allows exactly max length characters', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      // Create a string exactly at the max length
      final exactName = 'B' * _testMaxLength;

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Chat Name *'),
        exactName,
      );

      // The controller should have exactly maxLength characters
      expect(nameController.text.length, _testMaxLength);
      expect(nameController.text, exactName);
    });

    testWidgets('chat name character counter is displayed', (tester) async {
      await tester.pumpApp(Scaffold(body: createTestWidget()));

      // Enter some text
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Chat Name *'),
        'Test',
      );
      await tester.pump();

      // Verify character counter is displayed (e.g., "4/50")
      expect(find.text('4/$_testMaxLength'), findsOneWidget);
    });
  });
}
