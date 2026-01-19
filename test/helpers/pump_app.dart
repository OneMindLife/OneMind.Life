import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/providers/providers.dart';
import '../mocks/mocks.dart';

/// Extension on WidgetTester to simplify widget testing with mocked providers
extension PumpApp on WidgetTester {
  /// Pumps a widget wrapped with ProviderScope and MaterialApp
  ///
  /// Automatically sets up provider overrides for any mocked services passed.
  /// Use this for testing widgets in isolation with mocked dependencies.
  ///
  /// Example:
  /// ```dart
  /// await tester.pumpApp(
  ///   const MyWidget(),
  ///   chatService: mockChatService,
  ///   authService: mockAuthService,
  /// );
  /// ```
  Future<void> pumpApp(
    Widget widget, {
    MockChatService? chatService,
    MockParticipantService? participantService,
    MockPropositionService? propositionService,
    MockAuthService? authService,
    ThemeData? theme,
    List<Override>? additionalOverrides,
    NavigatorObserver? navigatorObserver,
  }) async {
    final overrides = <Override>[
      if (chatService != null)
        chatServiceProvider.overrideWithValue(chatService),
      if (participantService != null)
        participantServiceProvider.overrideWithValue(participantService),
      if (propositionService != null)
        propositionServiceProvider.overrideWithValue(propositionService),
      if (authService != null)
        authServiceProvider.overrideWithValue(authService),
      ...?additionalOverrides,
    ];

    await pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: theme ?? ThemeData.light(),
          home: widget,
          navigatorObservers: [
            if (navigatorObserver != null) navigatorObserver,
          ],
        ),
      ),
    );
  }

  /// Pumps a widget as a dialog
  Future<void> pumpDialog(
    Widget dialog, {
    MockChatService? chatService,
    MockParticipantService? participantService,
    MockPropositionService? propositionService,
    MockAuthService? authService,
  }) async {
    await pumpApp(
      Scaffold(body: dialog),
      chatService: chatService,
      participantService: participantService,
      propositionService: propositionService,
      authService: authService,
    );
  }

  /// Settles the widget tree after async operations
  ///
  /// Convenience wrapper that handles common timeout scenarios
  Future<void> settle({Duration timeout = const Duration(seconds: 5)}) async {
    await pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.build, timeout);
  }
}

/// Extension on CommonFinders for custom finders
extension CustomFinders on CommonFinders {
  /// Find a widget by its Key string
  Finder byKeyString(String key) => byKey(Key(key));

  /// Find an IconButton with a specific icon
  Finder iconButton(IconData icon) => find.widgetWithIcon(IconButton, icon);

  /// Find a Text widget containing a substring
  Finder textContaining(String substring) => find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data?.contains(substring) ?? false),
      );

  /// Find an enabled button with specific text
  Finder enabledButton(String text) => find.byWidgetPredicate(
        (widget) =>
            widget is ElevatedButton &&
            widget.enabled &&
            find.descendant(of: find.byWidget(widget), matching: find.text(text)).evaluate().isNotEmpty,
      );
}
