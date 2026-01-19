import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/public_chat_summary.dart';
import '../../services/chat_service.dart';
import '../mixins/language_aware_mixin.dart';
import '../providers.dart';

/// Notifier for managing public chats discovery with Realtime updates.
///
/// Uses debounced refresh to handle Realtime race conditions where
/// events fire before transactions are fully visible to queries.
/// Supports translations based on user's language preference.
/// Automatically refreshes when the user changes their language setting.
class PublicChatsNotifier extends StateNotifier<AsyncValue<List<PublicChatSummary>>>
    with LanguageAwareMixin<AsyncValue<List<PublicChatSummary>>> {
  final ChatService _chatService;
  final SupabaseClient _supabaseClient;

  RealtimeChannel? _chatsChannel;
  Timer? _debounceTimer;
  DateTime? _lastRefreshTime;
  String? _currentSearchQuery;

  static const _debounceDuration = Duration(milliseconds: 150);
  static const _minRefreshInterval = Duration(seconds: 1);

  PublicChatsNotifier(Ref ref)
      : _chatService = ref.read(chatServiceProvider),
        _supabaseClient = ref.read(supabaseProvider),
        super(const AsyncLoading()) {
    initializeLanguageSupport(ref);
    _loadAndSubscribe();
  }

  @override
  void onLanguageChanged(String newLanguageCode) {
    _refreshForLanguageChange();
  }

  /// Refresh chats when language changes (silent refresh, no loading state)
  Future<void> _refreshForLanguageChange() async {
    try {
      final chats = _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty
          ? await _chatService.searchPublicChats(
              _currentSearchQuery!,
              languageCode: languageCode,
            )
          : await _chatService.getPublicChats(
              languageCode: languageCode,
            );
      state = AsyncData(chats);
    } catch (e) {
      // Silent failure - keep existing data on language refresh error
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _chatsChannel?.unsubscribe();
    disposeLanguageSupport();
    super.dispose();
  }

  Future<void> _loadAndSubscribe() async {
    try {
      final chats = await _chatService.getPublicChats(
        languageCode: languageCode,
      );
      state = AsyncData(chats);
      _setupSubscription();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void _setupSubscription() {
    _chatsChannel?.unsubscribe();

    // Subscribe to all chat changes (creates, deletes, updates)
    // Note: We don't filter by access_method because DELETE events only include
    // primary key in old_record (not access_method), so filtered deletes are missed.
    // The refresh query filters to public chats anyway, so extra events are harmless.
    _chatsChannel = _supabaseClient
        .channel('public_chats')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chats',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  /// Debounced refresh with rate limiting - waits for events to settle
  /// and prevents refresh storms from rapid-fire events.
  void _scheduleRefresh() {
    // Rate limiting: skip if we refreshed too recently
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _minRefreshInterval) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _lastRefreshTime = DateTime.now();
      _refreshChats();
    });
  }

  Future<void> _refreshChats() async {
    try {
      final chats = _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty
          ? await _chatService.searchPublicChats(
              _currentSearchQuery!,
              languageCode: languageCode,
            )
          : await _chatService.getPublicChats(
              languageCode: languageCode,
            );
      state = AsyncData(chats);
    } catch (e) {
      // Log but don't fail - next event will retry
    }
  }

  /// Search public chats by query
  Future<void> search(String query) async {
    _currentSearchQuery = query.isEmpty ? null : query;

    if (query.isEmpty) {
      // Clear search, refresh full list
      state = const AsyncLoading();
      await _loadAndSubscribe();
      return;
    }

    state = const AsyncLoading();
    try {
      final chats = await _chatService.searchPublicChats(
        query,
        languageCode: languageCode,
      );
      state = AsyncData(chats);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Manual refresh (pull-to-refresh)
  Future<void> refresh() async {
    _debounceTimer?.cancel();
    state = const AsyncLoading();

    if (_currentSearchQuery != null && _currentSearchQuery!.isNotEmpty) {
      // Refresh search results
      try {
        final chats = await _chatService.searchPublicChats(
          _currentSearchQuery!,
          languageCode: languageCode,
        );
        state = AsyncData(chats);
      } catch (e, st) {
        state = AsyncError(e, st);
      }
    } else {
      // Refresh full list
      await _loadAndSubscribe();
    }
  }
}
