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
import 'package:onemind_app/providers/notifiers/public_chats_notifier.dart';
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

  /// Stub getPublicChats with all required params
  void stubGetPublicChats(List<PublicChatSummary> chats) {
    when(() => mockChatService.getPublicChats(
          languageCode: any(named: 'languageCode'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => chats);
  }

  /// Stub searchPublicChats with all required params
  void stubSearchPublicChats(dynamic query, List<PublicChatSummary> chats) {
    when(() => mockChatService.searchPublicChats(
          query is Matcher ? any() : query as String,
          languageCode: any(named: 'languageCode'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer((_) async => chats);
  }

  /// Wait for the provider state to transition from loading to data/error
  Future<AsyncValue<PublicChatsState>> waitForData(ProviderContainer container) async {
    final completer = Completer<AsyncValue<PublicChatsState>>();

    // Listen for state changes
    final sub = container.listen<AsyncValue<PublicChatsState>>(
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
        stubGetPublicChats(chats);

        container = createContainer();

        // Wait for state to transition from loading
        final state = await waitForData(container);

        expect(state, isA<AsyncData<PublicChatsState>>());
        expect((state as AsyncData<PublicChatsState>).value.chats, equals(chats));
        verify(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(1);
      });

      test('returns empty list when no public chats', () async {
        stubGetPublicChats([]);

        container = createContainer();

        final state = await waitForData(container);

        expect(state, isA<AsyncData<PublicChatsState>>());
        expect((state as AsyncData<PublicChatsState>).value.chats, isEmpty);
      });

      test('handles error during load', () async {
        when(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenThrow(Exception('Network error'));

        container = createContainer();

        final state = await waitForData(container);

        expect(state.hasError, isTrue);
      });

      test('sets up realtime subscription on initialization', () async {
        stubGetPublicChats([]);

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

        stubGetPublicChats(allChats);
        when(() => mockChatService.searchPublicChats(
              'Flutter',
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => searchResults);

        container = createContainer();

        // Wait for initial load
        await waitForData(container);

        // Search
        await container.read(publicChatsProvider.notifier).search('Flutter');

        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.chats, equals(searchResults));
        verify(() => mockChatService.searchPublicChats(
              'Flutter',
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(1);
      });

      test('resets to all chats when search query is empty', () async {
        final allChats = [
          createSummary(id: 1, name: 'Chat 1'),
          createSummary(id: 2, name: 'Chat 2'),
        ];

        stubGetPublicChats(allChats);

        container = createContainer();

        // Wait for initial load
        await waitForData(container);

        // Search with empty query - should reload
        await container.read(publicChatsProvider.notifier).search('');

        // getPublicChats should be called again
        verify(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(2);
      });

      test('handles search error gracefully', () async {
        final chats = [createSummary(id: 1, name: 'Chat')];
        stubGetPublicChats(chats);
        when(() => mockChatService.searchPublicChats(
              any(),
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenThrow(Exception('Search failed'));

        container = createContainer();

        await waitForData(container);
        await container.read(publicChatsProvider.notifier).search('test');

        final state = container.read(publicChatsProvider);
        expect(state.hasError, isTrue);
      });

      test('search("") resets _currentSearchQuery and uses getPublicChats', () async {
        final allChats = [
          createSummary(id: 1, name: 'Chat 1'),
        ];
        final searchResults = [
          createSummary(id: 1, name: 'Chat 1'),
        ];

        stubGetPublicChats(allChats);
        when(() => mockChatService.searchPublicChats(
              'test',
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => searchResults);

        container = createContainer();
        await waitForData(container);

        // Search then clear
        await container.read(publicChatsProvider.notifier).search('test');
        await container.read(publicChatsProvider.notifier).search('');

        // Verify getPublicChats was called (initial + reset) and searchPublicChats once
        verify(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(2);
        verify(() => mockChatService.searchPublicChats(
              'test',
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(1);
      });
    });

    group('refresh()', () {
      test('reloads public chats', () async {
        final initialChats = [createSummary(id: 1, name: 'Initial')];
        final updatedChats = [
          createSummary(id: 1, name: 'Initial'),
          createSummary(id: 2, name: 'New'),
        ];

        stubGetPublicChats(initialChats);

        container = createContainer();

        await waitForData(container);

        // Update mock
        stubGetPublicChats(updatedChats);

        // Refresh
        await container.read(publicChatsProvider.notifier).refresh();

        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.chats, equals(updatedChats));
      });
    });

    group('loadMore()', () {
      test('appends next page to existing list', () async {
        final firstPage = List.generate(
          20,
          (i) => createSummary(id: i + 1, name: 'Chat ${i + 1}'),
        );
        final secondPage = List.generate(
          5,
          (i) => createSummary(id: i + 21, name: 'Chat ${i + 21}'),
        );

        // First call returns page 1, second returns page 2
        int callCount = 0;
        when(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((invocation) async {
          callCount++;
          if (callCount == 1) return firstPage;
          return secondPage;
        });

        container = createContainer();
        await waitForData(container);

        // Verify initial state has 20 chats
        expect(container.read(publicChatsProvider).valueOrNull?.chats.length, 20);
        expect(container.read(publicChatsProvider).valueOrNull?.hasMore, isTrue);

        // Load more
        await container.read(publicChatsProvider.notifier).loadMore();

        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.chats.length, 25);
        expect(state.valueOrNull?.chats.last.name, 'Chat 25');
      });

      test('sets hasMore=false when page < pageSize', () async {
        // Return fewer than 20 items (pageSize) to indicate no more pages
        final smallPage = List.generate(
          5,
          (i) => createSummary(id: i + 1, name: 'Chat ${i + 1}'),
        );

        stubGetPublicChats(smallPage);

        container = createContainer();
        await waitForData(container);

        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.hasMore, isFalse);
      });

      test('is no-op when hasMore=false', () async {
        // Return fewer than pageSize to set hasMore=false
        final smallPage = [createSummary(id: 1, name: 'Only Chat')];

        stubGetPublicChats(smallPage);

        container = createContainer();
        await waitForData(container);

        // Clear interactions to track new calls
        clearInteractions(mockChatService);

        // Try to load more - should be no-op
        await container.read(publicChatsProvider.notifier).loadMore();

        verifyNever(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ));
      });

      test('is no-op when isLoadingMore=true', () async {
        final firstPage = List.generate(
          20,
          (i) => createSummary(id: i + 1, name: 'Chat ${i + 1}'),
        );

        // First call returns page 1 immediately, second call never completes
        final neverCompleter = Completer<List<PublicChatSummary>>();
        int callCount = 0;
        when(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return firstPage;
          return neverCompleter.future;
        });

        container = createContainer();
        await waitForData(container);

        // Start loading more (will hang because completer never finishes)
        container.read(publicChatsProvider.notifier).loadMore();

        // Wait for isLoadingMore to be set
        await Future.delayed(const Duration(milliseconds: 50));

        // Try another loadMore - should be no-op since already loading
        await container.read(publicChatsProvider.notifier).loadMore();

        // getPublicChats should be called exactly twice (initial + first loadMore)
        verify(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(2);

        // Clean up
        neverCompleter.complete([]);
      });

      test('paginates search results with correct offset', () async {
        final firstPage = List.generate(
          20,
          (i) => createSummary(id: i + 1, name: 'Flutter Chat ${i + 1}'),
        );
        final secondPage = List.generate(
          3,
          (i) => createSummary(id: i + 21, name: 'Flutter Chat ${i + 21}'),
        );

        stubGetPublicChats([]);

        int searchCallCount = 0;
        when(() => mockChatService.searchPublicChats(
              'Flutter',
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async {
          searchCallCount++;
          if (searchCallCount == 1) return firstPage;
          return secondPage;
        });

        container = createContainer();
        await waitForData(container);

        // Perform search
        await container.read(publicChatsProvider.notifier).search('Flutter');
        expect(container.read(publicChatsProvider).valueOrNull?.chats.length, 20);

        // Load more search results
        await container.read(publicChatsProvider.notifier).loadMore();

        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.chats.length, 23);
        expect(state.valueOrNull?.hasMore, isFalse);
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

        stubGetPublicChats(initialChats);

        container = createContainer();

        await waitForData(container);

        // Verify initial state
        expect(container.read(publicChatsProvider).valueOrNull?.chats.length, equals(1));

        // Update mock to return new data
        stubGetPublicChats(updatedChats);

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
        expect(state.valueOrNull?.chats.length, equals(2),
            reason: 'Realtime callback should trigger refresh');
      });

      test('cleans up subscription on dispose', () async {
        stubGetPublicChats([]);

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
        stubGetPublicChats(chats);

        container = createContainer();

        await waitForData(container);

        // Verify language service was used
        verify(() => mockLanguageService.getCurrentLanguage()).called(greaterThan(0));
      });

      test('passes language code to service on search', () async {
        final chats = [createSummary(id: 1, name: 'Chat')];
        final searchResults = [createSummary(id: 1, name: 'Flutter Chat')];

        when(() => mockLanguageService.getCurrentLanguage()).thenReturn('es');
        stubGetPublicChats(chats);
        when(() => mockChatService.searchPublicChats(
              any(),
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => searchResults);

        container = createContainer();

        await waitForData(container);
        await container.read(publicChatsProvider.notifier).search('Flutter');

        // Verify search was called
        verify(() => mockChatService.searchPublicChats(
              'Flutter',
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(1);
      });

      test('auto-refreshes when locale changes', () async {
        final englishChats = [createSummary(id: 1, name: 'English Chat')];
        final spanishChats = [createSummary(id: 1, name: 'Chat en Español')];

        // Create a controllable locale notifier
        final testLocaleNotifier = TestLocaleNotifier(mockLanguageService);

        // Setup mock to return different chats based on language
        when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');
        when(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => englishChats);

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
        verify(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(1);

        // Update mock to return Spanish chats
        when(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => spanishChats);

        // Change locale to Spanish
        testLocaleNotifier.setLocaleForTest(const Locale('es'));

        // Wait for async refresh to complete
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify getPublicChats was called again for the language change
        verify(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(1);

        // Verify state was updated with Spanish chats
        final state = container.read(publicChatsProvider);
        expect(state.valueOrNull?.chats.first.name, equals('Chat en Español'));
      });

      test('does not refresh when locale changes to same language', () async {
        final chats = [createSummary(id: 1, name: 'Chat')];

        // Create a controllable locale notifier
        final testLocaleNotifier = TestLocaleNotifier(mockLanguageService);

        when(() => mockLanguageService.getCurrentLanguage()).thenReturn('en');
        when(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => chats);

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
        verifyNever(() => mockChatService.getPublicChats(
              languageCode: any(named: 'languageCode'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ));
      });
    });
  });
}
