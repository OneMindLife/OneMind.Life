import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/public_chat_summary.dart';
import '../../services/chat_service.dart';
import '../mixins/language_aware_mixin.dart';
import '../providers.dart';

/// State for paginated public chats discovery.
class PublicChatsState extends Equatable {
  final List<PublicChatSummary> chats;
  final bool hasMore;
  final bool isLoadingMore;

  const PublicChatsState({
    required this.chats,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  PublicChatsState copyWith({
    List<PublicChatSummary>? chats,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return PublicChatsState(
      chats: chats ?? this.chats,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [chats, hasMore, isLoadingMore];
}

/// Notifier for managing public chats discovery with pagination and Realtime.
///
/// Supports infinite scroll via [loadMore], debounced search, and
/// automatic refresh on Realtime events.
class PublicChatsNotifier extends StateNotifier<AsyncValue<PublicChatsState>>
    with LanguageAwareMixin<AsyncValue<PublicChatsState>> {
  final ChatService _chatService;
  final SupabaseClient _supabaseClient;

  RealtimeChannel? _chatsChannel;
  Timer? _debounceTimer;
  DateTime? _lastRefreshTime;
  String? _currentSearchQuery;

  static const _pageSize = 20;
  static const _debounceDuration = Duration(milliseconds: 150);
  static const _minRefreshInterval = Duration(seconds: 1);

  PublicChatsNotifier(Ref ref)
      : _chatService = ref.read(chatServiceProvider),
        _supabaseClient = ref.read(supabaseProvider),
        super(const AsyncLoading()) {
    initializeLanguageSupport(ref);
    _loadInitial();
  }

  @override
  void onLanguageChanged(String newLanguageCode) {
    _refreshForLanguageChange();
  }

  Future<void> _refreshForLanguageChange() async {
    try {
      final chats = _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty
          ? await _chatService.searchPublicChats(
              _currentSearchQuery!,
              languageCode: languageCode,
              limit: _pageSize,
            )
          : await _chatService.getPublicChats(
              languageCode: languageCode,
              limit: _pageSize,
            );
      state = AsyncData(PublicChatsState(
        chats: chats,
        hasMore: chats.length >= _pageSize,
      ));
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

  /// Initial load — first page + subscribe to realtime.
  Future<void> _loadInitial() async {
    try {
      final chats = await _chatService.getPublicChats(
        languageCode: languageCode,
        limit: _pageSize,
        offset: 0,
      );
      state = AsyncData(PublicChatsState(
        chats: chats,
        hasMore: chats.length >= _pageSize,
      ));
      _setupSubscription();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void _setupSubscription() {
    _chatsChannel?.unsubscribe();

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

  void _scheduleRefresh() {
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

  /// Refresh reloads the first page only (realtime or pull-to-refresh).
  Future<void> _refreshChats() async {
    try {
      final chats = _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty
          ? await _chatService.searchPublicChats(
              _currentSearchQuery!,
              languageCode: languageCode,
              limit: _pageSize,
            )
          : await _chatService.getPublicChats(
              languageCode: languageCode,
              limit: _pageSize,
              offset: 0,
            );
      state = AsyncData(PublicChatsState(
        chats: chats,
        hasMore: chats.length >= _pageSize,
      ));
    } catch (e) {
      // Log but don't fail - next event will retry
    }
  }

  /// Load next page of results (infinite scroll).
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final offset = current.chats.length;
      final chats = _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty
          ? await _chatService.searchPublicChats(
              _currentSearchQuery!,
              languageCode: languageCode,
              limit: _pageSize,
              offset: offset,
            )
          : await _chatService.getPublicChats(
              languageCode: languageCode,
              limit: _pageSize,
              offset: offset,
            );

      state = AsyncData(PublicChatsState(
        chats: [...current.chats, ...chats],
        hasMore: chats.length >= _pageSize,
      ));
    } catch (e) {
      // Revert loading state, keep existing data
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Search public chats by query (resets to first page).
  Future<void> search(String query) async {
    _currentSearchQuery = query.isEmpty ? null : query;

    if (query.isEmpty) {
      state = const AsyncLoading();
      await _loadInitial();
      return;
    }

    state = const AsyncLoading();
    try {
      final chats = await _chatService.searchPublicChats(
        query,
        languageCode: languageCode,
        limit: _pageSize,
      );
      state = AsyncData(PublicChatsState(
        chats: chats,
        hasMore: chats.length >= _pageSize,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Manual refresh — resets to first page.
  Future<void> refresh() async {
    _debounceTimer?.cancel();
    state = const AsyncLoading();

    if (_currentSearchQuery != null && _currentSearchQuery!.isNotEmpty) {
      try {
        final chats = await _chatService.searchPublicChats(
          _currentSearchQuery!,
          languageCode: languageCode,
          limit: _pageSize,
        );
        state = AsyncData(PublicChatsState(
          chats: chats,
          hasMore: chats.length >= _pageSize,
        ));
      } catch (e, st) {
        state = AsyncError(e, st);
      }
    } else {
      await _loadInitial();
    }
  }
}
