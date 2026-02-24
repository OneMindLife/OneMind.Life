import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/providers/notifiers/my_chats_notifier.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/participant_service.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../fixtures/chat_fixtures.dart';
import '../../fixtures/chat_dashboard_info_fixtures.dart';
import '../../fixtures/join_request_fixtures.dart';
import '../../mocks/mock_supabase_client.dart';

class MockChatService extends Mock implements ChatService {}

class MockParticipantService extends Mock implements ParticipantService {}

class MockAuthService extends Mock implements AuthService {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

class MockSession extends Mock implements Session {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockLanguageService extends Mock implements LanguageService {}

void main() {
  late MockChatService mockChatService;
  late MockParticipantService mockParticipantService;
  late MockAuthService mockAuthService;
  late MockSupabaseClient mockSupabase;
  late MockRealtimeChannel mockChannel;
  late MockGoTrueClient mockAuth;
  late MockUser mockUser;
  late MockSharedPreferences mockSharedPreferences;
  late MockLanguageService mockLanguageService;
  late MockSession mockSession;
  late StreamController<AuthState> authStateController;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(PostgresChangeEvent.all);
    registerFallbackValue(PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: 1,
    ));
  });

  setUp(() {
    mockChatService = MockChatService();
    mockParticipantService = MockParticipantService();
    mockAuthService = MockAuthService();
    mockSupabase = MockSupabaseClient();
    mockChannel = MockRealtimeChannel();
    mockAuth = MockGoTrueClient();
    mockUser = MockUser();
    mockSession = MockSession();
    mockSharedPreferences = MockSharedPreferences();
    mockLanguageService = MockLanguageService();
    authStateController = StreamController<AuthState>.broadcast();

    // Setup default auth behavior
    when(() => mockAuthService.currentUserId).thenReturn('test-user-id');
    when(() => mockAuthService.isSignedIn).thenReturn(true);
    when(() => mockAuthService.displayName).thenReturn('Test User');
    when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => 'test-user-id');

    // Setup mock Supabase auth
    when(() => mockSupabase.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('test-user-id');
    when(() => mockAuth.onAuthStateChange).thenAnswer((_) => authStateController.stream);
    when(() => mockSession.user).thenReturn(mockUser);

    // Setup default channel behavior
    when(() => mockSupabase.channel(any())).thenReturn(mockChannel);
    when(() => mockChannel.onPostgresChanges(
          event: any(named: 'event'),
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          filter: any(named: 'filter'),
          callback: any(named: 'callback'),
        )).thenReturn(mockChannel);
    // Also support calls without filter (for global rounds subscription)
    when(() => mockChannel.onPostgresChanges(
          event: any(named: 'event'),
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          callback: any(named: 'callback'),
        )).thenReturn(mockChannel);
    when(() => mockChannel.subscribe()).thenReturn(mockChannel);
    when(() => mockChannel.unsubscribe()).thenAnswer((_) async => 'ok');

    // Default empty pending requests
    when(() => mockParticipantService.getMyPendingRequests())
        .thenAnswer((_) async => []);

    // Setup mock language service
    when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');
  });

  tearDown(() {
    container.dispose();
    authStateController.close();
  });

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(mockChatService),
        participantServiceProvider.overrideWithValue(mockParticipantService),
        authServiceProvider.overrideWithValue(mockAuthService),
        supabaseProvider.overrideWithValue(mockSupabase),
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        languageServiceProvider.overrideWithValue(mockLanguageService),
      ],
    );
  }

  /// Wait for the provider state to transition from loading to data/error
  Future<AsyncValue<MyChatsState>> waitForData(ProviderContainer container) async {
    final completer = Completer<AsyncValue<MyChatsState>>();

    // Listen for state changes
    final sub = container.listen<AsyncValue<MyChatsState>>(
      myChatsProvider,
      (previous, next) {
        if (!next.isLoading && !completer.isCompleted) {
          completer.complete(next);
        }
      },
      fireImmediately: true,
    );

    // Timeout after 1 second
    final result = await completer.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => container.read(myChatsProvider),
    );

    sub.close();
    return result;
  }

  group('MyChatsNotifier', () {
    group('build()', () {
      test('loads dashboard chats on initialization', () async {
        final dashboardChats = [
          ChatDashboardInfoFixtures.idle(id: 1, name: 'Chat 1'),
          ChatDashboardInfoFixtures.idle(id: 2, name: 'Chat 2'),
        ];
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => dashboardChats);

        container = createContainer();

        final state = await waitForData(container);

        expect(state, isA<AsyncData<MyChatsState>>());
        final data = (state as AsyncData<MyChatsState>).value;
        expect(data.dashboardChats, equals(dashboardChats));
        expect(data.chats.length, 2);
        verify(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode'))).called(1);
      });

      test('returns empty list when no chats', () async {
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => []);

        container = createContainer();

        final state = await waitForData(container);

        expect(state, isA<AsyncData<MyChatsState>>());
        expect((state as AsyncData<MyChatsState>).value.dashboardChats, isEmpty);
        expect(state.value.chats, isEmpty);
      });

      test('handles error during load', () async {
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenThrow(Exception('Network error'));

        container = createContainer();

        final state = await waitForData(container);

        expect(state, isA<AsyncError<MyChatsState>>());
      });
    });

    group('refresh()', () {
      test('reloads dashboard chats from service', () async {
        final initialChats = [ChatDashboardInfoFixtures.idle(id: 1, name: 'Initial')];
        final updatedChats = [
          ChatDashboardInfoFixtures.idle(id: 1, name: 'Initial'),
          ChatDashboardInfoFixtures.proposingTimed(id: 2, name: 'New Chat'),
        ];

        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => initialChats);

        container = createContainer();

        // Wait for initial load
        await waitForData(container);

        // Update mock to return new data
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => updatedChats);

        // Refresh and wait for new data
        await container.read(myChatsProvider.notifier).refresh();

        // Give the state time to update
        await Future.delayed(const Duration(milliseconds: 50));

        final state = container.read(myChatsProvider);
        expect(state, isA<AsyncData<MyChatsState>>());
        expect((state as AsyncData<MyChatsState>).value.dashboardChats, equals(updatedChats));
      });
    });

    group('removeChat()', () {
      test('removes chat from local list', () async {
        final chats = [
          ChatDashboardInfoFixtures.idle(id: 1, name: 'Chat 1'),
          ChatDashboardInfoFixtures.idle(id: 2, name: 'Chat 2'),
          ChatDashboardInfoFixtures.idle(id: 3, name: 'Chat 3'),
        ];
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chats);

        container = createContainer();

        // Wait for initial load
        await waitForData(container);

        // Remove chat 2
        container.read(myChatsProvider.notifier).removeChat(2);

        final result = container.read(myChatsProvider).valueOrNull;
        expect(result?.dashboardChats.length, equals(2));
        expect(result?.dashboardChats.any((d) => d.chat.id == 2), isFalse);
        expect(result?.chats.length, equals(2));
      });

      test('does nothing if chat not found', () async {
        final chats = [ChatDashboardInfoFixtures.idle(id: 1, name: 'Chat 1')];
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chats);

        container = createContainer();

        await waitForData(container);

        // Remove non-existent chat
        container.read(myChatsProvider.notifier).removeChat(999);

        final result = container.read(myChatsProvider).valueOrNull;
        expect(result?.dashboardChats.length, equals(1));
      });

      test('does nothing if state is not loaded', () async {
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenThrow(Exception('Error'));

        container = createContainer();

        // Wait for error state
        await waitForData(container);

        // Should not throw
        container.read(myChatsProvider.notifier).removeChat(1);
      });
    });

    group('auth state handling', () {
      test('sets up subscriptions when currentUser is available on init', () async {
        // currentUser is available (default setup)
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => []);

        container = createContainer();
        await waitForData(container);

        // Verify channels were created for participants, join_requests, and rounds
        verify(() => mockSupabase.channel('my_participants')).called(1);
        verify(() => mockSupabase.channel('my_join_requests')).called(1);
        verify(() => mockSupabase.channel('dashboard_rounds')).called(1);
      });

      test('does not set up subscriptions when currentUser is null on init', () async {
        // Simulate auth not ready - currentUser is null
        when(() => mockAuth.currentUser).thenReturn(null);
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => []);

        container = createContainer();
        await waitForData(container);

        // Verify channels were NOT created (since user is null)
        verifyNever(() => mockSupabase.channel('my_participants'));
        verifyNever(() => mockSupabase.channel('my_join_requests'));
        verifyNever(() => mockSupabase.channel('dashboard_rounds'));
      });

      test('sets up subscriptions when auth state changes to signedIn', () async {
        // Start with currentUser as null (auth not ready)
        when(() => mockAuth.currentUser).thenReturn(null);
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => []);

        container = createContainer();
        await waitForData(container);

        // Verify no channels created yet
        verifyNever(() => mockSupabase.channel('my_participants'));
        verifyNever(() => mockSupabase.channel('my_join_requests'));

        // Now simulate auth completing - user becomes available
        when(() => mockAuth.currentUser).thenReturn(mockUser);

        // Emit auth state change
        authStateController.add(AuthState(
          AuthChangeEvent.signedIn,
          mockSession,
        ));

        // Allow async listener to process
        await Future.delayed(const Duration(milliseconds: 50));

        // Now verify channels WERE created after auth state change
        verify(() => mockSupabase.channel('my_participants')).called(1);
        verify(() => mockSupabase.channel('my_join_requests')).called(1);
        verify(() => mockSupabase.channel('dashboard_rounds')).called(1);
      });

      test('does not duplicate subscriptions on subsequent auth events', () async {
        // currentUser is available from the start
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => []);

        container = createContainer();
        await waitForData(container);

        // Channels created on init
        verify(() => mockSupabase.channel('my_participants')).called(1);
        verify(() => mockSupabase.channel('my_join_requests')).called(1);
        verify(() => mockSupabase.channel('dashboard_rounds')).called(1);

        // Emit another auth event (e.g., token refresh)
        authStateController.add(AuthState(
          AuthChangeEvent.tokenRefreshed,
          mockSession,
        ));

        await Future.delayed(const Duration(milliseconds: 50));

        // Should NOT create additional channels (no new calls after the auth event)
        verifyNever(() => mockSupabase.channel('my_participants'));
        verifyNever(() => mockSupabase.channel('my_join_requests'));
        verifyNever(() => mockSupabase.channel('dashboard_rounds'));
      });
    });

    group('approvedChatStream', () {
      test('emits chat when pending request becomes active chat', () async {
        // Initial state: pending request for chat 5
        final pendingRequest = JoinRequestFixtures.model(
          id: 1,
          chatId: 5,
          chatName: 'Pending Chat',
        );

        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => []);
        when(() => mockParticipantService.getMyPendingRequests())
            .thenAnswer((_) async => [pendingRequest]);

        container = createContainer();
        await waitForData(container);

        // Verify initial state has pending request
        final initialState = container.read(myChatsProvider).valueOrNull;
        expect(initialState?.pendingRequests.length, equals(1));
        expect(initialState?.dashboardChats.length, equals(0));

        // Set up stream listener before triggering refresh
        final approvedChats = <int>[];
        final subscription = container
            .read(myChatsProvider.notifier)
            .approvedChatStream
            .listen((chat) {
          approvedChats.add(chat.id);
        });

        // Now the request is approved - chat 5 appears in chats list
        final approvedChat = ChatDashboardInfoFixtures.idle(id: 5, name: 'Pending Chat');
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => [approvedChat]);
        when(() => mockParticipantService.getMyPendingRequests())
            .thenAnswer((_) async => []); // No more pending requests

        // Trigger refresh
        await container.read(myChatsProvider.notifier).refresh();
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify the stream emitted the approved chat
        expect(approvedChats, contains(5));

        await subscription.cancel();
      });

      test('does not emit when chat was already in chats list', () async {
        // Chat 5 already exists
        final existingChat = ChatDashboardInfoFixtures.idle(id: 5, name: 'Existing Chat');

        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => [existingChat]);
        when(() => mockParticipantService.getMyPendingRequests())
            .thenAnswer((_) async => []);

        container = createContainer();
        await waitForData(container);

        // Set up stream listener
        final approvedChats = <int>[];
        final subscription = container
            .read(myChatsProvider.notifier)
            .approvedChatStream
            .listen((chat) {
          approvedChats.add(chat.id);
        });

        // Refresh with same data (no change)
        await container.read(myChatsProvider.notifier).refresh();
        await Future.delayed(const Duration(milliseconds: 100));

        // Should not emit anything since chat was already there
        expect(approvedChats, isEmpty);

        await subscription.cancel();
      });

      test('does not emit when new chat was not in pending requests', () async {
        // No pending requests initially
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => []);
        when(() => mockParticipantService.getMyPendingRequests())
            .thenAnswer((_) async => []);

        container = createContainer();
        await waitForData(container);

        // Set up stream listener
        final approvedChats = <int>[];
        final subscription = container
            .read(myChatsProvider.notifier)
            .approvedChatStream
            .listen((chat) {
          approvedChats.add(chat.id);
        });

        // New chat appears but it was never in pending requests (e.g., host created it)
        final newChat = ChatDashboardInfoFixtures.idle(id: 10, name: 'New Chat');
        when(() => mockChatService.getMyDashboard(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => [newChat]);

        await container.read(myChatsProvider.notifier).refresh();
        await Future.delayed(const Duration(milliseconds: 100));

        // Should not emit - this chat was not in pending requests
        expect(approvedChats, isEmpty);

        await subscription.cancel();
      });
    });
  });
}
