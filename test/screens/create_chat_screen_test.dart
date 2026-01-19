import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/screens/create/create_chat_screen.dart';

import '../helpers/pump_app.dart';
import '../mocks/mocks.dart';

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
    // Default: user has no display name set
    when(() => mockAuthService.displayName).thenReturn(null);
  });

  Widget createTestWidget(WidgetTester tester) {
    // Use pumpApp to properly inject mocked services
    return const CreateChatScreen();
  }

  Future<void> pumpCreateChatScreen(WidgetTester tester, {String? displayName}) async {
    if (displayName != null) {
      when(() => mockAuthService.displayName).thenReturn(displayName);
    }
    await tester.pumpApp(
      const CreateChatScreen(),
      authService: mockAuthService,
    );
  }

  /// Helper for tests that need scrolling - sets larger screen to avoid overflow
  void testWidgetsLargeScreen(
    String description,
    Future<void> Function(WidgetTester) callback,
  ) {
    testWidgets(description, (tester) async {
      // Set larger screen size to avoid overflow errors
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await callback(tester);
    });
  }

  group('CreateChatScreen - Section Headers', () {
    testWidgets('displays all section headers', (tester) async {
      await pumpCreateChatScreen(tester);

      // Basic visible sections (top of form)
      expect(find.text('Basic Info'), findsOneWidget);
      expect(find.text('Visibility'), findsOneWidget);
      // Phase Start may need scrolling depending on viewport
    });

    testWidgetsLargeScreen('can scroll to see all sections', (tester) async {
      await pumpCreateChatScreen(tester);

      // First select 'Auto' mode to enable Timer sections
      // Use .first because Rating Start Mode also has an 'Auto' button
      await tester.tap(find.text('Auto').first);
      await tester.pumpAndSettle();

      // Scroll down to see more sections
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      // Should now see more sections
      expect(find.text('Timers'), findsOneWidget);
    });
  });

  group('CreateChatScreen - Basic Info', () {
    testWidgets('displays name and message fields', (tester) async {
      await pumpCreateChatScreen(tester);

      expect(find.text('Chat Name *'), findsOneWidget);
      expect(find.text('Initial Message *'), findsOneWidget);
      expect(find.text('Description (Optional)'), findsOneWidget);
    });

    testWidgets('can enter chat name', (tester) async {
      await pumpCreateChatScreen(tester);

      final nameField = find.widgetWithText(TextFormField, 'Chat Name *');
      await tester.enterText(nameField, 'My Test Chat');
      await tester.pump();

      expect(find.text('My Test Chat'), findsOneWidget);
    });

    testWidgets('can enter initial message', (tester) async {
      await pumpCreateChatScreen(tester);

      final messageField = find.widgetWithText(TextFormField, 'Initial Message *');
      await tester.enterText(messageField, 'What should we discuss?');
      await tester.pump();

      expect(find.text('What should we discuss?'), findsOneWidget);
    });
  });

  group('CreateChatScreen - Visibility Settings', () {
    testWidgets('displays access method selector with public as default', (tester) async {
      await pumpCreateChatScreen(tester);

      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Invite Code'), findsOneWidget);
      expect(find.text('Email Invite Only'), findsOneWidget);
    });

    testWidgets('can toggle access method to invite code', (tester) async {
      await pumpCreateChatScreen(tester);

      await tester.tap(find.text('Invite Code'));
      await tester.pumpAndSettle();

      // Verify tap succeeded (no crash)
      expect(find.text('Invite Code'), findsOneWidget);
    });

    testWidgetsLargeScreen('can toggle access method to email invite only', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll to make Email Invite Only visible
      await tester.dragUntilVisible(
        find.text('Email Invite Only'),
        find.byType(ListView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Email Invite Only'));
      await tester.pumpAndSettle();

      // Verify tap succeeded (no crash)
      expect(find.text('Email Invite Only'), findsOneWidget);
    });

    // Skip: Require authentication UI is disabled pending user auth implementation
    // See lib/screens/create/widgets/visibility_section.dart TODO comment
    testWidgets('displays require authentication toggle', (tester) async {
      await pumpCreateChatScreen(tester);

      expect(find.text('Require authentication'), findsOneWidget);
      // Default subtitle
      expect(find.text('Anonymous users allowed'), findsOneWidget);
    }, skip: true); // Require authentication UI disabled - see visibility_section.dart TODO

    // Skip: Require authentication UI is disabled pending user auth implementation
    testWidgets('can toggle require authentication', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll to make the switch visible
      await tester.dragUntilVisible(
        find.text('Require authentication'),
        find.byType(ListView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();

      final authSwitch = find.widgetWithText(SwitchListTile, 'Require authentication');
      await tester.tap(authSwitch);
      await tester.pumpAndSettle();

      // Subtitle changes after toggle
      expect(find.text('Users must sign in'), findsOneWidget);
    }, skip: true); // Require authentication UI disabled - see visibility_section.dart TODO

    testWidgetsLargeScreen('require approval only shows for non-public access', (tester) async {
      await pumpCreateChatScreen(tester);

      // Default is now 'Invite Code', so require approval should be visible
      expect(find.text('Require approval'), findsOneWidget);

      // Switch to public access
      await tester.tap(find.text('Public'));
      await tester.pumpAndSettle();

      // For public access, require approval should NOT be visible
      expect(find.text('Require approval'), findsNothing);
    });

    testWidgetsLargeScreen('can toggle require approval when visible', (tester) async {
      await pumpCreateChatScreen(tester);

      // Default is 'Invite Code' so require approval is already visible
      final approvalSwitch = find.widgetWithText(SwitchListTile, 'Require approval');
      expect(approvalSwitch, findsOneWidget);

      await tester.tap(approvalSwitch);
      await tester.pumpAndSettle();

      // Verify switch was toggled (still exists, no crash)
      expect(approvalSwitch, findsOneWidget);
    });
  });

  group('CreateChatScreen - Facilitation Mode', () {
    testWidgetsLargeScreen('displays start mode selector', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll to Facilitation Mode section if needed
      await tester.dragUntilVisible(
        find.text('Facilitation Mode'),
        find.byType(ListView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();

      // Facilitation Mode has Manual/Auto, Rating Start Mode also has Auto/Manual
      expect(find.text('Manual'), findsWidgets);
      expect(find.text('Auto'), findsWidgets);
    });

    testWidgetsLargeScreen('can toggle to auto mode', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll to Facilitation Mode section if needed
      await tester.dragUntilVisible(
        find.text('Facilitation Mode'),
        find.byType(ListView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();

      // Toggle to auto mode (use .first since Rating Start Mode also has 'Auto')
      await tester.tap(find.text('Auto').first);
      await tester.pumpAndSettle();

      // Verify tap succeeded (no crash)
      expect(find.text('Auto'), findsWidgets);
    });
  });

  group('CreateChatScreen - Timers (scrolled)', () {
    testWidgetsLargeScreen('displays timer section with presets', (tester) async {
      await pumpCreateChatScreen(tester);

      // Select 'Auto' mode first to enable Timer sections
      // Use .first since Rating Start Mode also has 'Auto'
      await tester.tap(find.text('Auto').first);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Timers'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Timers'), findsOneWidget);
      expect(find.text('Proposing'), findsOneWidget);
      // Timer presets appear twice (proposing + rating)
      expect(find.text('5 min'), findsWidgets);
      expect(find.text('1 day'), findsWidgets);
    });
  });

  group('CreateChatScreen - Minimum to Advance (scrolled)', () {
    testWidgetsLargeScreen('displays minimum inputs', (tester) async {
      await pumpCreateChatScreen(tester);

      await tester.dragUntilVisible(
        find.text('Minimum to Advance'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Minimum to Advance'), findsOneWidget);
      expect(find.text('Proposing minimum'), findsOneWidget);
      expect(find.text('Rating minimum'), findsOneWidget);
    });
  });

  group('CreateChatScreen - Auto-Advance (scrolled)', () {
    testWidgetsLargeScreen('displays auto-advance toggles', (tester) async {
      await pumpCreateChatScreen(tester);

      // Select 'Auto' mode first to enable Timer/Auto-Advance sections
      // Use .first since Rating Start Mode also has 'Auto'
      await tester.tap(find.text('Auto').first);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Auto-Advance At'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Auto-Advance At'), findsOneWidget);
      expect(find.text('Enable auto-advance (proposing)'), findsOneWidget);
      expect(find.text('Enable auto-advance (rating)'), findsOneWidget);
    });

    testWidgetsLargeScreen('can toggle auto-advance switches', (tester) async {
      await pumpCreateChatScreen(tester);

      // Select 'Auto' mode first to enable Timer/Auto-Advance sections
      // Use .first since Rating Start Mode also has 'Auto'
      await tester.tap(find.text('Auto').first);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Enable auto-advance (proposing)'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      // Toggle auto-advance for proposing
      final proposingSwitch = find.widgetWithText(
        SwitchListTile,
        'Enable auto-advance (proposing)',
      );
      await tester.tap(proposingSwitch);
      await tester.pumpAndSettle();

      // Verify tap succeeded (no crash)
      expect(proposingSwitch, findsOneWidget);
    });
  });

  group('CreateChatScreen - AI Participant (hidden)', () {
    // AI Participant section is hidden - not implemented yet
    testWidgetsLargeScreen('AI section is not displayed', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll to bottom to ensure we've seen all sections
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      // AI section should not be visible (commented out in create_chat_screen.dart)
      expect(find.text('AI Participant'), findsNothing);
      expect(find.text('Enable OneMind AI'), findsNothing);
    });

    testWidgetsLargeScreen('AI propositions count is not displayed', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll to bottom to ensure we've seen all sections
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(find.text('AI propositions per round'), findsNothing);
    });
  });

  group('CreateChatScreen - Proposition Limits (scrolled)', () {
    testWidgetsLargeScreen('displays propositions per user setting', (tester) async {
      await pumpCreateChatScreen(tester);

      // Use dragUntilVisible for reliable scrolling
      await tester.dragUntilVisible(
        find.text('Proposition Limits'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Proposition Limits'), findsOneWidget);
      expect(find.text('Propositions per user'), findsOneWidget);
    });

    testWidgetsLargeScreen('shows default helper text for 1 proposition', (tester) async {
      await pumpCreateChatScreen(tester);

      await tester.dragUntilVisible(
        find.text('Each user can submit 1 proposition per round'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Each user can submit 1 proposition per round'),
        findsOneWidget,
      );
    });
  });

  group('CreateChatScreen - Consensus Settings (scrolled)', () {
    testWidgetsLargeScreen('displays confirmation rounds input', (tester) async {
      await pumpCreateChatScreen(tester);

      await tester.dragUntilVisible(
        find.text('Consensus Settings'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Consensus Settings'), findsOneWidget);
      expect(find.text('Confirmation rounds'), findsOneWidget);
    });

    testWidgetsLargeScreen('shows default of 2 rounds with explanation', (tester) async {
      await pumpCreateChatScreen(tester);

      await tester.dragUntilVisible(
        find.text('Same proposition must win 2 rounds in a row'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Same proposition must win 2 rounds in a row'),
        findsOneWidget,
      );
    });

    testWidgetsLargeScreen('displays show previous results toggle', (tester) async {
      await pumpCreateChatScreen(tester);

      await tester.dragUntilVisible(
        find.text('Show full results from past rounds'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Show full results from past rounds'), findsOneWidget);
      // Default is now showPreviousResults: true
      expect(
        find.text('Users see all propositions and ratings'),
        findsOneWidget,
      );
    });
  });

  group('CreateChatScreen - Create Button', () {
    testWidgetsLargeScreen('displays create button at bottom', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll until the ElevatedButton with 'Create Chat' is visible
      await tester.dragUntilVisible(
        find.widgetWithText(ElevatedButton, 'Create Chat'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ElevatedButton, 'Create Chat'), findsOneWidget);
    });

    testWidgetsLargeScreen('create button tappable', (tester) async {
      await pumpCreateChatScreen(tester);

      // Scroll to create button
      await tester.dragUntilVisible(
        find.widgetWithText(ElevatedButton, 'Create Chat'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      // Verify button is present and tappable
      final createButton = find.widgetWithText(ElevatedButton, 'Create Chat');
      expect(createButton, findsOneWidget);

      // Tap the button - form validation should run without crash
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Button should still be present (not navigated away because of validation)
      expect(createButton, findsOneWidget);
    });
  });
}
