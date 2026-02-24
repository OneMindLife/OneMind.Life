import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/models.dart';
import '../../services/chat_service.dart';
import '../../services/participant_service.dart';
import '../mixins/language_aware_mixin.dart';
import '../providers.dart';

/// State for the user's chat list including pending join requests
class MyChatsState extends Equatable {
  final List<ChatDashboardInfo> dashboardChats;
  final List<JoinRequest> pendingRequests;
  final bool isTranslating;

  const MyChatsState({
    this.dashboardChats = const [],
    this.pendingRequests = const [],
    this.isTranslating = false,
  });

  /// Backward-compatible accessor for code that expects `List<Chat>`
  List<Chat> get chats => dashboardChats.map((d) => d.chat).toList();

  MyChatsState copyWith({
    List<ChatDashboardInfo>? dashboardChats,
    List<JoinRequest>? pendingRequests,
    bool? isTranslating,
  }) {
    return MyChatsState(
      dashboardChats: dashboardChats ?? this.dashboardChats,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      isTranslating: isTranslating ?? this.isTranslating,
    );
  }

  @override
  List<Object?> get props => [dashboardChats, pendingRequests, isTranslating];
}

/// Notifier for managing the user's chat list with Realtime updates.
///
/// Uses debounced refresh to handle Realtime race conditions where
/// events fire before transactions are fully visible to queries.
/// Supports translations based on user's language preference.
/// Automatically refreshes when the user changes their language setting.
/// Subscribes to rounds table for phase change events (dashboard updates).
class MyChatsNotifier extends StateNotifier<AsyncValue<MyChatsState>>
    with LanguageAwareMixin<AsyncValue<MyChatsState>> {
  final ChatService _chatService;
  final ParticipantService _participantService;
  final SupabaseClient _supabaseClient;

  RealtimeChannel? _participantChannel;
  RealtimeChannel? _joinRequestChannel;
  RealtimeChannel? _roundsChannel;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _debounceTimer;
  Timer? _periodicRefreshTimer;
  DateTime? _lastRefreshTime;

  /// Stream that emits when a join request is approved (chat becomes accessible)
  final _approvedChatController = StreamController<Chat>.broadcast();
  Stream<Chat> get approvedChatStream => _approvedChatController.stream;

  static const _debounceDuration = Duration(milliseconds: 150);
  static const _minRefreshInterval = Duration(seconds: 1);
  static const _periodicRefreshInterval = Duration(seconds: 30);

  MyChatsNotifier(Ref ref)
      : _chatService = ref.read(chatServiceProvider),
        _participantService = ref.read(participantServiceProvider),
        _supabaseClient = ref.read(supabaseProvider),
        super(const AsyncLoading()) {
    initializeLanguageSupport(ref);
    _listenToAuthChanges();
    _loadAndSubscribe();
    _startPeriodicRefresh();
  }

  /// Listen for auth state changes to set up subscriptions when user is authenticated
  void _listenToAuthChanges() {
    _authSubscription = _supabaseClient.auth.onAuthStateChange.listen((data) {
      final userId = data.session?.user.id;
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.tokenRefreshed) {
        // User just signed in or token refreshed - set up subscriptions if not already done
        if (_participantChannel == null && userId != null) {
          _setupSubscriptions();
        }
      }
    });
  }

  @override
  void onLanguageChanged(String newLanguageCode) {
    _refreshForLanguageChange();
  }

  /// Refresh when language changes.
  /// Sets isTranslating immediately so the UI can show feedback.
  Future<void> _refreshForLanguageChange() async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // Show translating state immediately
    state = AsyncData(currentState.copyWith(isTranslating: true));

    try {
      final results = await Future.wait([
        _chatService.getMyDashboard(languageCode: languageCode),
        _participantService.getMyPendingRequests(),
      ]);

      state = AsyncData(MyChatsState(
        dashboardChats: results[0] as List<ChatDashboardInfo>,
        pendingRequests: results[1] as List<JoinRequest>,
      ));
    } catch (e) {
      // Revert translating state on failure
      state = AsyncData(currentState);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _periodicRefreshTimer?.cancel();
    _authSubscription?.cancel();
    _participantChannel?.unsubscribe();
    _joinRequestChannel?.unsubscribe();
    _roundsChannel?.unsubscribe();
    _approvedChatController.close();
    disposeLanguageSupport();
    super.dispose();
  }

  Future<void> _loadAndSubscribe() async {
    try {
      final results = await Future.wait([
        _chatService.getMyDashboard(languageCode: languageCode),
        _participantService.getMyPendingRequests(),
      ]);

      final dashboardChats = results[0] as List<ChatDashboardInfo>;
      final pendingRequests = results[1] as List<JoinRequest>;

      state = AsyncData(MyChatsState(
        dashboardChats: dashboardChats,
        pendingRequests: pendingRequests,
      ));

      _setupSubscriptions();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void _setupSubscriptions() {
    _participantChannel?.unsubscribe();
    _joinRequestChannel?.unsubscribe();
    _roundsChannel?.unsubscribe();

    final userId = _supabaseClient.auth.currentUser?.id;
    if (userId == null) return;

    // Subscribe to participant changes (joins, kicks, leaves)
    _participantChannel = _supabaseClient
        .channel('my_participants')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _scheduleRefresh();
          },
        )
        .subscribe();

    // Subscribe to join request changes (created, approved, denied)
    _joinRequestChannel = _supabaseClient
        .channel('my_join_requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'join_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _scheduleRefresh();
          },
        )
        .subscribe();

    // Subscribe to global rounds changes for dashboard phase updates
    _roundsChannel = _supabaseClient
        .channel('dashboard_rounds')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rounds',
          callback: (payload) {
            _scheduleRefresh();
          },
        )
        .subscribe();
  }

  /// Start periodic refresh as safety net for missed realtime events
  void _startPeriodicRefresh() {
    _periodicRefreshTimer = Timer.periodic(_periodicRefreshInterval, (_) {
      // Only refresh if we have data (not in loading/error state)
      if (state.valueOrNull != null) {
        _refreshAll();
      }
    });
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
      _refreshAll();
    });
  }

  Future<void> _refreshAll() async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    try {
      final results = await Future.wait([
        _chatService.getMyDashboard(languageCode: languageCode),
        _participantService.getMyPendingRequests(),
      ]);

      final newDashboardChats = results[0] as List<ChatDashboardInfo>;
      final newPendingRequests = results[1] as List<JoinRequest>;

      // Detect approved join requests:
      // A pending request was approved if its chatId now appears in chats
      // but wasn't there before
      final oldChatIds = currentState.dashboardChats.map((d) => d.chat.id).toSet();
      final oldPendingChatIds =
          currentState.pendingRequests.map((r) => r.chatId).toSet();

      for (final dashInfo in newDashboardChats) {
        // Chat is new (wasn't in old chats) AND was in pending requests
        if (!oldChatIds.contains(dashInfo.chat.id) &&
            oldPendingChatIds.contains(dashInfo.chat.id)) {
          debugPrint(
              '[MyChatsNotifier] Join request approved for chat ${dashInfo.chat.id}: ${dashInfo.chat.name}');
          _approvedChatController.add(dashInfo.chat);
        }
      }

      state = AsyncData(MyChatsState(
        dashboardChats: newDashboardChats,
        pendingRequests: newPendingRequests,
      ));
    } catch (e) {
      // Silent failure - keep existing data on refresh error
    }
  }

  /// Manual refresh (pull-to-refresh)
  Future<void> refresh() async {
    _debounceTimer?.cancel();
    // Store previous state for approval detection
    final previousState = state.valueOrNull;
    state = const AsyncLoading();
    await _loadAndSubscribeWithApprovalCheck(previousState);
  }

  /// Load and subscribe, checking for approved requests against previous state
  Future<void> _loadAndSubscribeWithApprovalCheck(MyChatsState? previousState) async {
    try {
      final results = await Future.wait([
        _chatService.getMyDashboard(languageCode: languageCode),
        _participantService.getMyPendingRequests(),
      ]);

      final dashboardChats = results[0] as List<ChatDashboardInfo>;
      final pendingRequests = results[1] as List<JoinRequest>;

      // Detect approved join requests if we have previous state
      if (previousState != null) {
        final oldChatIds = previousState.dashboardChats.map((d) => d.chat.id).toSet();
        final oldPendingChatIds =
            previousState.pendingRequests.map((r) => r.chatId).toSet();

        for (final dashInfo in dashboardChats) {
          if (!oldChatIds.contains(dashInfo.chat.id) &&
              oldPendingChatIds.contains(dashInfo.chat.id)) {
            debugPrint(
                '[MyChatsNotifier] Join request approved for chat ${dashInfo.chat.id}: ${dashInfo.chat.name}');
            _approvedChatController.add(dashInfo.chat);
          }
        }
      }

      state = AsyncData(MyChatsState(
        dashboardChats: dashboardChats,
        pendingRequests: pendingRequests,
      ));

      _setupSubscriptions();
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Cancel a pending join request with optimistic update
  Future<void> cancelRequest(int requestId) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // Optimistic update
    state = AsyncData(currentState.copyWith(
      pendingRequests: currentState.pendingRequests
          .where((r) => r.id != requestId)
          .toList(),
    ));

    try {
      await _participantService.cancelJoinRequest(requestId);
    } catch (e) {
      // Revert on failure - Realtime will also trigger refresh
      state = AsyncData(currentState);
    }
  }

  /// Remove a chat from local state (optimistic update after leaving)
  void removeChat(int chatId) {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncData(currentState.copyWith(
      dashboardChats: currentState.dashboardChats
          .where((d) => d.chat.id != chatId)
          .toList(),
    ));
  }
}
