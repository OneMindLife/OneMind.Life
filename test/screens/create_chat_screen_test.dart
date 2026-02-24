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

  // Section headers tests commented out - localization not available in pumpApp helper
  // group('CreateChatScreen - Section Headers', () {
  //   testWidgets('displays all section headers', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Basic visible sections (top of form)
  //     expect(find.text('Basic Info'), findsOneWidget);
  //     expect(find.text('Visibility'), findsOneWidget);
  //   });

  //   testWidgetsLargeScreen('can scroll to see all sections', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Scroll down to see more sections (Auto mode is now default)
  //     await tester.drag(find.byType(ListView), const Offset(0, -500));
  //     await tester.pumpAndSettle();

  //     // Should now see more sections
  //     expect(find.text('Timers'), findsOneWidget);
  //   });
  // });

  group('CreateChatScreen - Basic Info', () {
    testWidgets('displays name and message fields', (tester) async {
      await pumpCreateChatScreen(tester);

      expect(find.text('Chat Name *'), findsOneWidget);
      expect(find.text('Initial Message *'), findsOneWidget);
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

    testWidgets('does not display a host name input field', (tester) async {
      await pumpCreateChatScreen(tester);

      // No display-name-field key should exist on the create chat screen.
      expect(find.byKey(const Key('display-name-field')), findsNothing);
      // No "Your Name" or "Display Name" label should be shown.
      expect(find.text('Your Name'), findsNothing);
      expect(find.text('Display Name'), findsNothing);
      // Only "Chat Name *" and "Initial Message *" TextFormFields should exist,
      // not a host name field.
      expect(find.widgetWithText(TextFormField, 'Chat Name *'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Initial Message *'), findsOneWidget);
    });
  });

  // Visibility tests commented out - requires pumpApp localization fixes
  // group('CreateChatScreen - Visibility Settings', () {
  //   testWidgets('displays visibility section header', (tester) async {
  //     await pumpCreateChatScreen(tester);
  //     expect(find.text('Visibility'), findsOneWidget);
  //   });
  // });

  // Hidden for MVP - Auto mode is now default
  // group('CreateChatScreen - How Phases Run', () {
  //   testWidgetsLargeScreen('displays start mode selector', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Scroll to How Phases Run section if needed (renamed from Facilitation Mode)
  //     await tester.dragUntilVisible(
  //       find.text('How Phases Run'),
  //       find.byType(ListView),
  //       const Offset(0, -100),
  //     );
  //     await tester.pumpAndSettle();

  //     // How Phases Run has Manual/Auto
  //     expect(find.text('Manual'), findsOneWidget);
  //     expect(find.text('Auto'), findsOneWidget);
  //   });

  //   testWidgetsLargeScreen('can toggle to auto mode', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Scroll to How Phases Run section if needed
  //     await tester.dragUntilVisible(
  //       find.text('How Phases Run'),
  //       find.byType(ListView),
  //       const Offset(0, -100),
  //     );
  //     await tester.pumpAndSettle();

  //     // Toggle to auto mode
  //     await tester.tap(find.text('Auto'));
  //     await tester.pumpAndSettle();

  //     // Verify tap succeeded (no crash)
  //     expect(find.text('Auto'), findsOneWidget);
  //   });
  // });

  group('CreateChatScreen - Timers (scrolled)', () {
    testWidgetsLargeScreen('displays timer section with presets', (tester) async {
      await pumpCreateChatScreen(tester);

      // Auto mode is now default, timers are always visible
      await tester.dragUntilVisible(
        find.text('Timers'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Timers'), findsOneWidget);
      // Default is useSameDuration: true, so shows "Phase Duration" instead of separate labels
      expect(find.text('Phase Duration'), findsOneWidget);
      expect(find.text('Same duration for both phases'), findsOneWidget);
      // Timer presets appear once (unified duration)
      expect(find.text('5 min'), findsWidgets);
      expect(find.text('1 day'), findsWidgets);
    });
  });

  // Hidden for MVP - using smart defaults
  // group('CreateChatScreen - Required Participation (scrolled)', () {
  //   testWidgetsLargeScreen('displays minimum inputs', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Renamed from "Minimum to Advance" to "Required Participation"
  //     await tester.dragUntilVisible(
  //       find.text('Required Participation'),
  //       find.byType(ListView),
  //       const Offset(0, -200),
  //     );
  //     await tester.pumpAndSettle();

  //     expect(find.text('Required Participation'), findsOneWidget);
  //     // Renamed: "Proposing minimum" -> "Ideas needed"
  //     expect(find.text('Ideas needed'), findsOneWidget);
  //     // Renamed: "Rating minimum" -> "Avg ratings needed"
  //     expect(find.text('Avg ratings needed'), findsOneWidget);
  //   });
  // });

  // Hidden for MVP - using smart defaults (100% auto-advance)
  // group('CreateChatScreen - End Phase Early (scrolled)', () {
  //   testWidgetsLargeScreen('displays auto-advance toggles', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Select 'Auto' mode first to enable Timer/End Phase Early sections
  //     await tester.tap(find.text('Auto'));
  //     await tester.pumpAndSettle();

  //     // Renamed from "Auto-Advance At" to "End Phase Early"
  //     await tester.dragUntilVisible(
  //       find.text('End Phase Early'),
  //       find.byType(ListView),
  //       const Offset(0, -200),
  //     );
  //     await tester.pumpAndSettle();

  //     expect(find.text('End Phase Early'), findsOneWidget);
  //     // Renamed labels
  //     expect(find.text('End early when enough ideas submitted'), findsOneWidget);
  //     expect(find.text('End early when enough ratings submitted'), findsOneWidget);
  //   });

  //   testWidgetsLargeScreen('can toggle auto-advance switches', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Select 'Auto' mode first to enable Timer/End Phase Early sections
  //     await tester.tap(find.text('Auto'));
  //     await tester.pumpAndSettle();

  //     await tester.dragUntilVisible(
  //       find.text('End early when enough ideas submitted'),
  //       find.byType(ListView),
  //       const Offset(0, -200),
  //     );
  //     await tester.pumpAndSettle();

  //     // Toggle end early for proposing
  //     final proposingSwitch = find.widgetWithText(
  //       SwitchListTile,
  //       'End early when enough ideas submitted',
  //     );
  //     await tester.tap(proposingSwitch);
  //     await tester.pumpAndSettle();

  //     // Verify tap succeeded (no crash)
  //     expect(proposingSwitch, findsOneWidget);
  //   });
  // });

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

  // Proposition Limits is now part of Consensus Settings
  // group('CreateChatScreen - Proposition Limits (scrolled)', () {
  //   testWidgetsLargeScreen('displays propositions per user setting', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     // Use dragUntilVisible for reliable scrolling
  //     await tester.dragUntilVisible(
  //       find.text('Proposition Limits'),
  //       find.byType(ListView),
  //       const Offset(0, -200),
  //     );
  //     await tester.pumpAndSettle();

  //     expect(find.text('Proposition Limits'), findsOneWidget);
  //     expect(find.text('Propositions per user'), findsOneWidget);
  //   });

  //   testWidgetsLargeScreen('shows default helper text for 1 proposition', (tester) async {
  //     await pumpCreateChatScreen(tester);

  //     await tester.dragUntilVisible(
  //       find.text('Each user can submit 1 proposition per round'),
  //       find.byType(ListView),
  //       const Offset(0, -200),
  //     );
  //     await tester.pumpAndSettle();

  //     expect(
  //       find.text('Each user can submit 1 proposition per round'),
  //       findsOneWidget,
  //     );
  //   });
  // });

  group('CreateChatScreen - Consensus Settings (scrolled)', () {
    // Hidden for MVP - using default of 2 rounds
    // testWidgetsLargeScreen('displays confirmation rounds input', (tester) async {
    //   await pumpCreateChatScreen(tester);

    //   await tester.dragUntilVisible(
    //     find.text('Consensus Settings'),
    //     find.byType(ListView),
    //     const Offset(0, -200),
    //   );
    //   await tester.pumpAndSettle();

    //   expect(find.text('Consensus Settings'), findsOneWidget);
    //   expect(find.text('Confirmation rounds'), findsOneWidget);
    // });

    // testWidgetsLargeScreen('shows default of 2 rounds with explanation', (tester) async {
    //   await pumpCreateChatScreen(tester);

    //   await tester.dragUntilVisible(
    //     find.text('Same proposition must win 2 rounds in a row'),
    //     find.byType(ListView),
    //     const Offset(0, -200),
    //   );
    //   await tester.pumpAndSettle();

    //   expect(
    //     find.text('Same proposition must win 2 rounds in a row'),
    //     findsOneWidget,
    //   );
    // });

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
