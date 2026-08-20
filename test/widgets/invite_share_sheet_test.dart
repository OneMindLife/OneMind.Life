import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/services/analytics_service.dart';
import 'package:onemind_app/widgets/invite_share_sheet.dart';

class _MockAnalyticsService extends Mock implements AnalyticsService {}

/// InviteShareSheet lifecycle tests — verifies the 2026-06-05 instrumentation:
/// the sheet fires invite_dialog_shown when it opens (initState) and
/// invite_dialog_dismissed when it closes (dispose, every path), carrying the
/// had_shared flag so a cold walk-away (had_shared=false) is distinguishable
/// from a close-after-sharing.
void main() {
  late _MockAnalyticsService analytics;

  setUp(() {
    analytics = _MockAnalyticsService();
    when(() => analytics.logInviteDialogShown(
          chatId: any(named: 'chatId'),
          auto: any(named: 'auto'),
        )).thenAnswer((_) async {});
    when(() => analytics.logInviteDialogDismissed(
          chatId: any(named: 'chatId'),
          hadShared: any(named: 'hadShared'),
        )).thenAnswer((_) async {});
    when(() => analytics.logInviteShared(
          chatId: any(named: 'chatId'),
          shareMethod: any(named: 'shareMethod'),
        )).thenAnswer((_) async {});
  });

  Widget _wrap(Widget child) => ProviderScope(
        overrides: [analyticsServiceProvider.overrideWithValue(analytics)],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  const sheet = InviteShareSheet(
    chatName: 'Test Chat',
    inviteCode: 'CODE1',
    chatId: 'chat-1',
    auto: true,
  );

  testWidgets('fires invite_dialog_shown with the auto flag on open',
      (tester) async {
    await tester.pumpWidget(_wrap(sheet));

    verify(() => analytics.logInviteDialogShown(chatId: 'chat-1', auto: true))
        .called(1);
  });

  testWidgets(
      'fires invite_dialog_dismissed with had_shared=false on close without sharing',
      (tester) async {
    await tester.pumpWidget(_wrap(sheet));
    // Replace the sheet → its State.dispose() runs (every close path goes here).
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    verify(() =>
            analytics.logInviteDialogDismissed(chatId: 'chat-1', hadShared: false))
        .called(1);
  });

  testWidgets(
      'tapping the copy link logs the share AND makes dismissal report had_shared=true',
      (tester) async {
    await tester.pumpWidget(_wrap(sheet));

    // Tap the copy affordance (the tap-to-copy InkWell carries the copy icon).
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    verify(() =>
            analytics.logInviteShared(chatId: 'chat-1', shareMethod: 'copy'))
        .called(1);

    // Now close it — had_shared must be true (not a cold walk-away).
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    verify(() =>
            analytics.logInviteDialogDismissed(chatId: 'chat-1', hadShared: true))
        .called(1);
  });
}
