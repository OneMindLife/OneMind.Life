import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/providers/notifiers/my_chats_notifier.dart';
import 'package:onemind_app/screens/home/all_chats_screen.dart';

import '../../fixtures/chat_dashboard_info_fixtures.dart';
import '../../fixtures/join_request_fixtures.dart';

class _MockLanguageService extends Mock implements LanguageService {
  @override
  String getCurrentLanguage() => 'en';
  @override
  Future<String> initializeLanguage() async => 'en';
  @override
  Future<bool> updateLanguage(String code) async => true;
}

class _TestLocaleNotifier extends LocaleNotifier {
  _TestLocaleNotifier() : super(_MockLanguageService());
}

/// Fake notifier that immediately exposes a handcrafted MyChatsState.
/// Accepts ChatDashboardInfo directly so tests can drive the bucket
/// partition (nextUp / wrappingUp / inactive).
class _FakeMyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    implements MyChatsNotifier {
  _FakeMyChatsNotifier(
    List<ChatDashboardInfo> dashboardChats, {
    List<JoinRequest> pendingRequests = const [],
  }) : super(AsyncData(MyChatsState(
          dashboardChats: dashboardChats,
          pendingRequests: pendingRequests,
        )));

  @override
  Future<void> refresh() async {}
  @override
  void removeChat(int chatId) {}
  @override
  Future<void> cancelRequest(int requestId) async {}
  @override
  void addPendingRequest(JoinRequest request) {}
  @override
  Stream<Chat> get approvedChatStream => const Stream.empty();
  @override
  String get languageCode => 'en';
  @override
  void initializeLanguageSupport(dynamic ref) {}
  @override
  void onLanguageChanged(String newLanguageCode) {}
  @override
  void disposeLanguageSupport() {}
}

Widget _buildScreen({required List<ChatDashboardInfo> dashboardChats}) {
  return ProviderScope(
    overrides: [
      localeProvider.overrideWith((ref) => _TestLocaleNotifier()),
      myChatsProvider.overrideWith(
        (ref) => _FakeMyChatsNotifier(dashboardChats),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const AllChatsScreen(),
    ),
  );
}

void main() {
  group('AllChatsScreen', () {
    testWidgets(
        'shows empty state when no wrapping-up or inactive chats',
        (tester) async {
      await tester.pumpWidget(_buildScreen(dashboardChats: const []));
      await tester.pump();

      expect(find.text("Nothing here — you're all caught up."), findsOneWidget);
      expect(find.textContaining('Wrapping up'), findsNothing);
      expect(find.textContaining('Inactive'), findsNothing);
    });

    testWidgets('renders wrapping-up section with chats where user has already participated',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        dashboardChats: [
          ChatDashboardInfoFixtures.proposingTimed(
            id: 1,
            name: 'Wrapping A',
            hasParticipated: true,
          ),
          ChatDashboardInfoFixtures.ratingTimed(
            id: 2,
            name: 'Wrapping B',
            hasParticipated: true,
          ),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('WRAPPING UP (2)'), findsOneWidget);
      expect(find.text('Wrapping A'), findsOneWidget);
      expect(find.text('Wrapping B'), findsOneWidget);
    });

    testWidgets('renders inactive section with paused/waiting/idle chats',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        dashboardChats: [
          ChatDashboardInfoFixtures.paused(id: 10, name: 'Paused Chat'),
          ChatDashboardInfoFixtures.waiting(id: 11, name: 'Waiting Chat'),
          ChatDashboardInfoFixtures.idle(id: 12, name: 'Idle Chat'),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('INACTIVE (3)'), findsOneWidget);
      expect(find.text('Paused Chat'), findsOneWidget);
      expect(find.text('Waiting Chat'), findsOneWidget);
      expect(find.text('Idle Chat'), findsOneWidget);
    });

    testWidgets(
        'renders both sections when wrapping-up and inactive chats coexist',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        dashboardChats: [
          ChatDashboardInfoFixtures.proposingTimed(
              id: 1, name: 'Wrap', hasParticipated: true),
          ChatDashboardInfoFixtures.paused(id: 2, name: 'Paused'),
        ],
      ));
      await tester.pump();

      expect(find.textContaining('WRAPPING UP (1)'), findsOneWidget);
      expect(find.textContaining('INACTIVE (1)'), findsOneWidget);
    });

    testWidgets(
        'includes next-up chats — true "everything I am in" view',
        (tester) async {
      // The redesigned AllChatsScreen lists every chat the user is in,
      // including next-up. Home shows the focused queue; this is the
      // searchable escape hatch for finding any specific chat.
      final nextUp = ChatDashboardInfoFixtures.proposingTimed(
        id: 99,
        name: 'Next Up Chat',
        hasParticipated: false,
      );
      await tester.pumpWidget(_buildScreen(dashboardChats: [nextUp]));
      await tester.pumpAndSettle();

      expect(find.text('Next Up Chat'), findsOneWidget);
      expect(find.textContaining('NEXT UP'), findsOneWidget);
    });

    testWidgets('app bar shows localized "All chats" title', (tester) async {
      await tester.pumpWidget(_buildScreen(dashboardChats: const []));
      await tester.pump();

      expect(find.widgetWithText(AppBar, 'All chats'), findsOneWidget);
    });
  });
}
