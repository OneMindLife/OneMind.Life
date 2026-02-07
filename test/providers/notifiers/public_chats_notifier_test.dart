import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/core/l10n/language_service.dart';
import 'package:onemind_app/core/l10n/locale_provider.dart';
import 'package:onemind_app/models/public_chat_summary.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/services/chat_service.dart';
import 'package:onemind_app/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../mocks/mock_supabase_client.dart';

class MockChatService extends Mock implements ChatService {}

class MockAuthService extends Mock implements AuthService {}

class MockLanguageService extends Mock implements LanguageService {}

/// Test locale notifier that allows programmatic locale changes
class TestLocaleNotifier extends LocaleNotifier {
  TestLocaleNotifier(MockLanguageService mockLanguageService)
      : super(mockLanguageService);

  /// Directly set the locale for testing
  void setLocaleForTest(Locale locale) {
    state = locale;
  }

  @override
  String get currentLanguageCode => state.languageCode;
}

void main() {
  late MockChatService mockChatService;
  late MockAuthService mockAuthService;
  late MockLanguageService mockLanguageService;
  late MockSupabaseClient mockSupabase;
  late MockRealtimeChannel mockChannel;
  late ProviderContainer container;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(PostgresChangeEvent.all);
    registerFallbackValue(PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: 1,
    ));
  });

  setUp(() {
    mockChatService = MockChatService();
    mockAuthService = MockAuthService();
    mockLanguageService = MockLanguageService();
    mockSupabase = MockSupabaseClient();
    mockChannel = MockRealtimeChannel();

    // Setup default auth behavior
    when(() => mockAuthService.currentUserId).thenReturn('test-user-id');
    when(() => mockAuthService.isSignedIn).thenReturn(true);
    when(() => mockAuthService.displayName).thenReturn('Test User');
    when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => 'test-user-id');

    // Setup default language behavior
    when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');

    // Setup default Supabase channel behavior (for realtime)
    when(() => mockSupabase.channel(any())).thenReturn(mockChannel);
    when(() => mockChannel.onPostgresChanges(
          event: any(named: 'event'),
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          filter: any(named: 'filter'),
          callback: any(named: 'callback'),
        )).thenReturn(mockChannel);
    when(() => mockChannel.subscribe()).thenReturn(mockChannel);
    when(() => mockChannel.unsubscribe()).thenAnswer((_) async => 'ok');
  });

  tearDown(() {
    container.dispose();
  });

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(mockChatService),
        authServiceProvider.overrideWithValue(mockAuthService),
        languageServiceProvider.overrideWithValue(mockLanguageService),
        supabaseProvider.overrideWithValue(mockSupabase),
      ],
    );
  }

  PublicChatSummary createSummary({
    required int id,
    required String name,
    String? description,
    int participantCount = 5,
  }) {
    return PublicChatSummary(
      id: id,
      name: name,
      initialMessage: 'Test message',
      description: description,
      participantCount: participantCount,
      createdAt: DateTime(2024, 1, 1),
    );
  }

  /// Wait for the provider state to transition from loading to data/error
  Future<AsyncValue<List<PublicChatSummary>>> waitForData(ProviderContainer container) async {
    final completer = Completer<AsyncValue<List<PublicChatSummary>>>();

    // Listen for state changes
    final sub = container.listen<AsyncValue<List<PublicChatSummary>>>(
      publicChatsProvider,
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
      onTimeout: () => container.read(publicChatsProvider),
    );

    sub.close();
    return result;
  }

  group('PublicChatsNotifier', () {
    group('build()', () {
      test('loads public chats on initialization', () async {
        final chats = [
          createSummary(id: 1, name: 'Public Chat 1'),
          createSummary(id: 2, name: 'Public Chat 2'),
        ];
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => chats);

        container = createContainer();

        // Wait for state to transition from loading
        final state = await waitForData(container);

        expect(state, isA<AsyncData<List<PublicChatSummary>>>());
        expect((state as AsyncData<List<PublicChatSummary>>).value, equals(chats));
        verify(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).called(1);
      });

      test('returns empty list when no public chats', () async {
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => []);

        container = createContainer();

        final state = await waitForData(container);

        expect(state, isA<AsyncData<List<PublicChatSummary>>>());
        expect((state as AsyncData<List<PublicChatSummary>>).value, isEmpty);
      });

      test('handles error during load', () async {
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenThrow(Exception('Network error'));

        container = createContainer();

        final state = await waitForData(container);

        expect(state.hasError, isTrue);
      });

      test('sets up realtime subscription on initialization', () async {
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => []);

        container = createContainer();

        await waitForData(container);

        // Verify realtime subscription was set up (no filter - catches DELETE events)
        verify(() => mockSupabase.channel('public_chats')).called(1);
        verify(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: 'public',
              table: 'chats',
              callback: any(named: 'callback'),
            )).called(1);
        verify(() => mockChannel.subscribe()).called(1);
      });
    });

    group('search()', () {
      test('searches public chats with query', () async {
        final allChats = [
          createSummary(id: 1, name: 'Flutter Chat'),
          createSummary(id: 2, name: 'Dart Chat'),
        ];
        final searchResults = [
          createSummary(id: 1, name: 'Flutter Chat'),
        ];

        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => allChats);
        when(() => mockChatService.searchPublicChats('Flutter', languageCode: any(named: 'languageCode'))).thenAnswer((_) async => searchResults);

        container = createContainer();

        // Wait for initial load
        await waitForData(container);

        // Search
        await container.read(publicChatsProvider.notifier).search('Flutter');

        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull, equals(searchResults));
        verify(() => mockChatService.searchPublicChats('Flutter', languageCode: any(named: 'languageCode'))).called(1);
      });

      test('resets to all chats when search query is empty', () async {
        final allChats = [
          createSummary(id: 1, name: 'Chat 1'),
          createSummary(id: 2, name: 'Chat 2'),
        ];

        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => allChats);

        container = createContainer();

        // Wait for initial load
        await waitForData(container);

        // Search with empty query - should reload
        await container.read(publicChatsProvider.notifier).search('');

        // getPublicChats should be called again
        verify(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).called(2);
      });

      test('handles search error gracefully', () async {
        final chats = [createSummary(id: 1, name: 'Chat')];
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => chats);
        when(() => mockChatService.searchPublicChats(any(), languageCode: any(named: 'languageCode'))).thenThrow(Exception('Search failed'));

        container = createContainer();

        await waitForData(container);
        await container.read(publicChatsProvider.notifier).search('test');

        final state = container.read(publicChatsProvider);
        expect(state.hasError, isTrue);
      });
    });

    group('refresh()', () {
      test('reloads public chats', () async {
        final initialChats = [createSummary(id: 1, name: 'Initial')];
        final updatedChats = [
          createSummary(id: 1, name: 'Initial'),
          createSummary(id: 2, name: 'New'),
        ];

        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => initialChats);

        container = createContainer();

        await waitForData(container);

        // Update mock
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => updatedChats);

        // Refresh
        await container.read(publicChatsProvider.notifier).refresh();

        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull, equals(updatedChats));
      });
    });

    group('realtime behavior', () {
      test('triggers refresh when realtime callback fires', () async {
        final initialChats = [createSummary(id: 1, name: 'Initial')];
        final updatedChats = [
          createSummary(id: 1, name: 'Initial'),
          createSummary(id: 2, name: 'New from Realtime'),
        ];

        // Capture the callback when subscription is set up
        void Function(PostgresChangePayload)? capturedCallback;
        when(() => mockChannel.onPostgresChanges(
              event: any(named: 'event'),
              schema: any(named: 'schema'),
              table: any(named: 'table'),
              callback: any(named: 'callback'),
            )).thenAnswer((invocation) {
          capturedCallback = invocation.namedArguments[#callback]
              as void Function(PostgresChangePayload);
          return mockChannel;
        });

        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => initialChats);

        container = createContainer();

        await waitForData(container);

        // Verify initial state
        expect(container.read(publicChatsProvider).valueOrNull?.length, equals(1));

        // Update mock to return new data
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => updatedChats);

        // Simulate realtime event by invoking the captured callback
        expect(capturedCallback, isNotNull, reason: 'Callback should have been captured');
        capturedCallback!(PostgresChangePayload(
          schema: 'public',
          table: 'chats',
          commitTimestamp: DateTime.now(),
          eventType: PostgresChangeEvent.insert,
          newRecord: {'id': 2, 'name': 'New from Realtime'},
          oldRecord: {},
          errors: null,
        ));

        // Wait for debounce to settle (150ms + some buffer)
        await Future.delayed(const Duration(milliseconds: 200));

        // State should now include the new chat
        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.length, equals(2),
            reason: 'Realtime callback should trigger refresh');
      });

      test('cleans up subscription on dispose', () async {
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => []);

        container = createContainer();

        await waitForData(container);

        // Dispose the container
        container.dispose();

        // Verify unsubscribe was called
        verify(() => mockChannel.unsubscribe()).called(1);
      });
    });

    group('language service integration', () {
      test('uses language service to get current language', () async {
        final chats = [
          createSummary(id: 1, name: 'Chat 1'),
        ];
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => chats);

        container = createContainer();

        await waitForData(container);

        // Verify language service was used
        verify(() => mockLanguageService.getCurrentLanguage()).called(greaterThan(0));
      });

      test('passes language code to service on search', () async {
        final chats = [createSummary(id: 1, name: 'Chat')];
        final searchResults = [createSummary(id: 1, name: 'Flutter Chat')];

        when(() => mockLanguageService.getCurrentLanguage()).thenReturn('es');
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).thenAnswer((_) async => chats);
        when(() => mockChatService.searchPublicChats(any(), languageCode: any(named: 'languageCode'))).thenAnswer((_) async => searchResults);

        container = createContainer();

        await waitForData(container);
        await container.read(publicChatsProvider.notifier).search('Flutter');

        // Verify search was called
        verify(() => mockChatService.searchPublicChats('Flutter', languageCode: any(named: 'languageCode'))).called(1);
      });

      test('auto-refreshes when locale changes', () async {
        final englishChats = [createSummary(id: 1, name: 'English Chat')];
        final spanishChats = [createSummary(id: 1, name: 'Chat en Español')];

        // Create a controllable locale notifier
        final testLocaleNotifier = TestLocaleNotifier(mockLanguageService);

        // Setup mock to return different chats based on language
        when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => englishChats);

        // Create container with controllable locale provider
        container = ProviderContainer(
          overrides: [
            chatServiceProvider.overrideWithValue(mockChatService),
            authServiceProvider.overrideWithValue(mockAuthService),
            languageServiceProvider.overrideWithValue(mockLanguageService),
            supabaseProvider.overrideWithValue(mockSupabase),
            localeProvider.overrideWith((ref) => testLocaleNotifier),
          ],
        );

        // Wait for initial load
        await waitForData(container);

        // Verify initial load called getPublicChats
        verify(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).called(1);

        // Update mock to return Spanish chats
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => spanishChats);

        // Change locale to Spanish
        testLocaleNotifier.setLocaleForTest(const Locale('es'));

        // Wait for async refresh to complete
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify getPublicChats was called again for the language change
        verify(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode'))).called(1);

        // Verify state was updated with Spanish chats
        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.first.name, equals('Chat en Español'));
      });

      test('does not refresh when locale changes to same language', () async {
        final chats = [createSummary(id: 1, name: 'Chat')];

        // Create a controllable locale notifier
        final testLocaleNotifier = TestLocaleNotifier(mockLanguageService);

        when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');
        when(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode')))
            .thenAnswer((_) async => chats);

        container = ProviderContainer(
          overrides: [
            chatServiceProvider.overrideWithValue(mockChatService),
            authServiceProvider.overrideWithValue(mockAuthService),
            languageServiceProvider.overrideWithValue(mockLanguageService),
            supabaseProvider.overrideWithValue(mockSupabase),
            localeProvider.overrideWith((ref) => testLocaleNotifier),
          ],
        );

        await waitForData(container);

        // Clear verification count
        clearInteractions(mockChatService);

        // Set locale to same language (should not trigger refresh)
        testLocaleNotifier.setLocaleForTest(const Locale('en'));

        // Wait a bit
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify getPublicChats was NOT called again
        verifyNever(() => mockChatService.getPublicChats(languageCode: any(named: 'languageCode')));
      });
    });
  });
}
