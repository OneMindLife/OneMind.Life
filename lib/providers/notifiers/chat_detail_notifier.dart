import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/models.dart';
import '../../services/chat_service.dart';
import '../../services/participant_service.dart';
import '../../services/proposition_service.dart';
import '../mixins/language_aware_mixin.dart';
import '../providers.dart';

/// Complete state for the ChatScreen
class ChatDetailState extends Equatable {
  final Chat? chat; // Fresh chat data (includes schedulePaused, etc.)
  final Cycle? currentCycle;
  final Round? currentRound;
  final List<Proposition> consensusItems;
  final List<Proposition> propositions;
  final List<Participant> participants;
  final Participant? myParticipant;
  final List<Proposition> myPropositions;
  final bool hasRated;
  final bool hasStartedRating;
  final List<RoundWinner> previousRoundWinners;
  final bool isSoleWinner;
  final int consecutiveSoleWins;
  final int? previousRoundId;
  final List<Proposition> previousRoundResults;
  final bool isDeleted;
  final List<Map<String, dynamic>> pendingJoinRequests;

  const ChatDetailState({
    this.chat,
    this.currentCycle,
    this.currentRound,
    this.consensusItems = const [],
    this.propositions = const [],
    this.participants = const [],
    this.myParticipant,
    this.myPropositions = const [],
    this.hasRated = false,
    this.hasStartedRating = false,
    this.previousRoundWinners = const [],
    this.isSoleWinner = false,
    this.consecutiveSoleWins = 0,
    this.previousRoundId,
    this.previousRoundResults = const [],
    this.isDeleted = false,
    this.pendingJoinRequests = const [],
  });

  ChatDetailState copyWith({
    Chat? chat,
    Cycle? currentCycle,
    Round? currentRound,
    List<Proposition>? consensusItems,
    List<Proposition>? propositions,
    List<Participant>? participants,
    Participant? myParticipant,
    List<Proposition>? myPropositions,
    bool? hasRated,
    bool? hasStartedRating,
    List<RoundWinner>? previousRoundWinners,
    bool? isSoleWinner,
    int? consecutiveSoleWins,
    int? previousRoundId,
    List<Proposition>? previousRoundResults,
    bool? isDeleted,
    List<Map<String, dynamic>>? pendingJoinRequests,
  }) {
    return ChatDetailState(
      chat: chat ?? this.chat,
      currentCycle: currentCycle ?? this.currentCycle,
      currentRound: currentRound ?? this.currentRound,
      consensusItems: consensusItems ?? this.consensusItems,
      propositions: propositions ?? this.propositions,
      participants: participants ?? this.participants,
      myParticipant: myParticipant ?? this.myParticipant,
      myPropositions: myPropositions ?? this.myPropositions,
      hasRated: hasRated ?? this.hasRated,
      hasStartedRating: hasStartedRating ?? this.hasStartedRating,
      previousRoundWinners: previousRoundWinners ?? this.previousRoundWinners,
      isSoleWinner: isSoleWinner ?? this.isSoleWinner,
      consecutiveSoleWins: consecutiveSoleWins ?? this.consecutiveSoleWins,
      previousRoundId: previousRoundId ?? this.previousRoundId,
      previousRoundResults: previousRoundResults ?? this.previousRoundResults,
      isDeleted: isDeleted ?? this.isDeleted,
      pendingJoinRequests: pendingJoinRequests ?? this.pendingJoinRequests,
    );
  }

  @override
  List<Object?> get props => [
        chat,
        currentCycle,
        currentRound,
        consensusItems,
        propositions,
        participants,
        myParticipant,
        myPropositions,
        hasRated,
        hasStartedRating,
        previousRoundWinners,
        isSoleWinner,
        consecutiveSoleWins,
        previousRoundId,
        previousRoundResults,
        isDeleted,
        pendingJoinRequests,
      ];
}

/// Parameters for creating a ChatDetailNotifier
class ChatDetailParams extends Equatable {
  final int chatId;
  final bool showPreviousResults;

  const ChatDetailParams({
    required this.chatId,
    required this.showPreviousResults,
  });

  @override
  List<Object?> get props => [chatId, showPreviousResults];
}

/// Notifier for managing ChatScreen state with real-time subscriptions.
///
/// Uses debounced refresh to handle Realtime race conditions.
/// Supports translations based on user's language preference.
class ChatDetailNotifier extends StateNotifier<AsyncValue<ChatDetailState>>
    with LanguageAwareMixin<AsyncValue<ChatDetailState>> {
  final int chatId;
  final bool showPreviousResults;

  // Services (initialized in constructor)
  final ChatService _chatService;
  final ParticipantService _participantService;
  final PropositionService _propositionService;
  final SupabaseClient _supabase;

  // Realtime subscriptions
  RealtimeChannel? _chatChannel;
  RealtimeChannel? _cycleChannel;
  RealtimeChannel? _roundChannel;
  RealtimeChannel? _participantChannel;
  RealtimeChannel? _propositionChannel;
  RealtimeChannel? _joinRequestChannel;

  // Debounce timers
  Timer? _refreshDebounce;
  Timer? _propositionDebounce;
  Timer? _joinRequestDebounce;

  // Rate limiting
  DateTime? _lastRefreshTime;
  DateTime? _lastPropositionRefreshTime;
  DateTime? _lastJoinRequestRefreshTime;

  // Cache last known state for use during loading
  ChatDetailState? _cachedState;

  // Prevent multiple startPhase clicks
  bool _isStartingPhase = false;
  bool get isStartingPhase => _isStartingPhase;

  static const _debounceDuration = Duration(milliseconds: 150);
  static const _minRefreshInterval = Duration(seconds: 1);

  ChatDetailNotifier({
    required Ref ref,
    required this.chatId,
    required this.showPreviousResults,
  })  : _chatService = ref.read(chatServiceProvider),
        _participantService = ref.read(participantServiceProvider),
        _propositionService = ref.read(propositionServiceProvider),
        _supabase = ref.read(supabaseProvider),
        super(const AsyncLoading()) {
    initializeLanguageSupport(ref);
    _loadData(setupSubscriptions: true);
  }

  @override
  void onLanguageChanged(String newLanguageCode) {
    _refreshForLanguageChange();
  }

  /// Refresh when language changes (silent refresh for chat data only)
  Future<void> _refreshForLanguageChange() async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    try {
      final chat = await _chatService.getChatById(chatId, languageCode: languageCode);
      state = AsyncData(currentState.copyWith(chat: chat));
    } catch (e) {
      // Silent failure - keep existing data on language refresh error
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _propositionDebounce?.cancel();
    _joinRequestDebounce?.cancel();
    disposeLanguageSupport();
    _unsubscribeAll();
    super.dispose();
  }

  void _unsubscribeAll() {
    _chatChannel?.unsubscribe();
    _cycleChannel?.unsubscribe();
    _roundChannel?.unsubscribe();
    _participantChannel?.unsubscribe();
    _propositionChannel?.unsubscribe();
    _joinRequestChannel?.unsubscribe();
  }

  Future<void> _loadData({bool setupSubscriptions = false}) async {
    // ignore: avoid_print
    print('[ChatDetailNotifier] _loadData starting for chat $chatId');
    try {
      // Load all data in parallel (including fresh chat data for schedulePaused, etc.)
      final results = await Future.wait([
        _chatService.getChatById(chatId, languageCode: languageCode),
        _chatService.getCurrentCycle(chatId),
        _chatService.getConsensusItems(chatId, languageCode: languageCode),
        _participantService.getParticipants(chatId),
        _participantService.getMyParticipant(chatId),
      ]);
      final chat = results[0] as Chat?;
      final currentCycle = results[1] as Cycle?;
      final consensusItems = results[2] as List<Proposition>;
      final participants = results[3] as List<Participant>;
      final myParticipant = results[4] as Participant?;

      // Fetch pending join requests if user is host
      List<Map<String, dynamic>> pendingJoinRequests = [];
      if (myParticipant?.isHost == true) {
        pendingJoinRequests =
            await _participantService.getPendingRequests(chatId);
      }

      Round? currentRound;
      List<RoundWinner> previousRoundWinners = [];
      bool isSoleWinner = false;
      int consecutiveSoleWins = 0;
      int? previousRoundId;
      List<Proposition> previousRoundResults = [];
      List<Proposition> propositions = [];
      List<Proposition> myPropositions = [];
      bool hasRated = false;
      bool hasStartedRating = false;

      if (currentCycle != null) {
        currentRound = await _chatService.getCurrentRound(currentCycle.id);

        // Fetch previous round winners
        final previousWinnersData =
            await _chatService.getPreviousRoundWinners(
              currentCycle.id,
              languageCode: languageCode,
            );
        previousRoundWinners =
            previousWinnersData['winners'] as List<RoundWinner>;
        isSoleWinner = previousWinnersData['isSoleWinner'] as bool;
        consecutiveSoleWins =
            previousWinnersData['consecutiveSoleWins'] as int;
        previousRoundId = previousWinnersData['previousRoundId'] as int?;

        // Load full previous round results if enabled
        if (showPreviousResults && previousRoundId != null) {
          previousRoundResults = await _propositionService
              .getPropositionsWithRatings(
                previousRoundId,
                languageCode: languageCode,
              );
        }

        if (currentRound != null && myParticipant != null) {
          // ignore: avoid_print
          print('[ChatDetailNotifier] Fetching propositions for round ${currentRound.id} with languageCode: $languageCode');
          final roundResults = await Future.wait([
            _propositionService.getPropositions(
              currentRound.id,
              languageCode: languageCode,
            ),
            _propositionService.getMyPropositions(
              currentRound.id,
              myParticipant.id,
            ),
            _propositionService.getRatingProgress(
              currentRound.id,
              myParticipant.id,
            ),
          ]);

          propositions = roundResults[0] as List<Proposition>;
          myPropositions = roundResults[1] as List<Proposition>;
          final ratingProgress = roundResults[2] as Map<String, dynamic>;
          hasRated = ratingProgress['completed'] as bool;
          hasStartedRating = ratingProgress['started'] as bool;
          // ignore: avoid_print
          print('[ChatDetailNotifier] Got ${propositions.length} propositions');
          for (final p in propositions) {
            // ignore: avoid_print
            print('[ChatDetailNotifier]   - id=${p.id} content="${p.content}" translated="${p.contentTranslated}" display="${p.displayContent}"');
          }
        }
      }

      final newState = ChatDetailState(
        chat: chat,
        currentCycle: currentCycle,
        currentRound: currentRound,
        consensusItems: consensusItems,
        propositions: propositions,
        participants: participants,
        myParticipant: myParticipant,
        myPropositions: myPropositions,
        hasRated: hasRated,
        hasStartedRating: hasStartedRating,
        previousRoundWinners: previousRoundWinners,
        isSoleWinner: isSoleWinner,
        consecutiveSoleWins: consecutiveSoleWins,
        previousRoundId: previousRoundId,
        previousRoundResults: previousRoundResults,
        pendingJoinRequests: pendingJoinRequests,
      );
      state = AsyncData(newState);
      _cachedState = newState;

      if (setupSubscriptions) {
        _setupSubscriptions();
      } else {
        _updateDynamicSubscriptions();
      }
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  void _setupSubscriptions() {
    // ignore: avoid_print
    print('[ChatDetailNotifier] Setting up subscriptions for chat $chatId');
    _unsubscribeAll();

    // Subscribe to chat changes (including delete)
    _chatChannel = _chatService.subscribeToChatChanges(
      chatId,
      onUpdate: (_) {
        _scheduleRefresh();
      },
      onDelete: _onChatDeleted,
    );

    // Subscribe to cycle changes
    // ignore: avoid_print
    print('[ChatDetailNotifier] Setting up cycle subscription for chat $chatId');
    _cycleChannel = _chatService.subscribeToCycleChanges(
      chatId,
      () {
        // ignore: avoid_print
        print('[ChatDetailNotifier] Cycle change received for chat $chatId - scheduling refresh');
        _scheduleRefresh();
      },
    );

    // Subscribe to participant changes
    _participantChannel = _participantService.subscribeToParticipants(
      chatId,
      (participants) {
        _onParticipantsChanged(participants);
      },
    );

    // Set up join request subscription if host
    _setupJoinRequestSubscription();

    // Set up dynamic subscriptions based on current state
    _updateDynamicSubscriptions();

    // Schedule a post-subscription refresh to catch any events that were
    // missed during the initial data load (race condition fix).
    // We reset the rate limiter to ensure this refresh runs.
    Timer(const Duration(milliseconds: 200), () {
      _lastRefreshTime = null;
      _scheduleRefresh();
    });
  }

  void _setupJoinRequestSubscription() {
    final currentState = state.valueOrNull;
    if (currentState?.myParticipant?.isHost != true) return;

    _joinRequestChannel?.unsubscribe();
    _joinRequestChannel = _supabase
        .channel('join_requests:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'join_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (_) => _scheduleJoinRequestRefresh(),
        )
        .subscribe();
  }

  void _updateDynamicSubscriptions() {
    final currentState = state.valueOrNull;
    if (currentState == null) {
      return;
    }

    // Update round subscription if cycle exists
    if (currentState.currentCycle != null) {
      _roundChannel?.unsubscribe();
      _roundChannel = _chatService.subscribeToRoundChanges(
        currentState.currentCycle!.id,
        _onRoundChange,
      );
    } else {
    }

    // Update proposition subscription if round exists
    if (currentState.currentRound != null) {
      _propositionChannel?.unsubscribe();
      _propositionChannel = _propositionService.subscribeToPropositions(
        currentState.currentRound!.id,
        () {
          _schedulePropositionRefresh();
        },
      );
    } else {
    }

    // Set up join request subscription (in case host status changed)
    _setupJoinRequestSubscription();
  }

  /// Handle round changes from realtime subscription
  ///
  /// Uses the payload directly for phase updates to avoid rate limiting issues.
  /// Only does full refresh for new rounds (INSERT) or when payload is incomplete.
  void _onRoundChange(
    PostgresChangeEvent event,
    Map<String, dynamic>? newRecord,
  ) {

    // Use cached state if current state is loading
    final currentState = state.valueOrNull ?? _cachedState;
    if (currentState == null) {
      return;
    }

    // For INSERT (new round), do a full refresh
    if (event == PostgresChangeEvent.insert) {
      _scheduleRefresh();
      return;
    }

    // For UPDATE, try to update state directly from payload
    if (event == PostgresChangeEvent.update && newRecord != null) {
      final roundId = newRecord['id'] as int?;
      final phaseStr = newRecord['phase'] as String?;


      // If this is our current round and we have phase info, update directly
      if (roundId == currentState.currentRound?.id && phaseStr != null) {
        final newPhase = RoundPhase.values.firstWhere(
          (p) => p.name == phaseStr,
          orElse: () => currentState.currentRound!.phase,
        );

        // Parse the new phaseEndsAt from payload
        final newPhaseEndsAt = newRecord['phase_ends_at'] != null
            ? DateTime.parse(newRecord['phase_ends_at'] as String)
            : null;

        // Check if phase or timer changed
        final phaseChanged = newPhase != currentState.currentRound!.phase;
        final currentTimer = currentState.currentRound!.phaseEndsAt;
        final timerChanged = newPhaseEndsAt?.toUtc() != currentTimer?.toUtc();

        if (phaseChanged || timerChanged) {
          final updatedRound = currentState.currentRound!.copyWith(
            phase: newPhase,
            phaseStartedAt: newRecord['phase_started_at'] != null
                ? DateTime.parse(newRecord['phase_started_at'] as String)
                : null,
            phaseEndsAt: newPhaseEndsAt,
          );

          final updatedState = currentState.copyWith(currentRound: updatedRound);
          state = AsyncData(updatedState);
          _cachedState = updatedState;

          // Schedule a full refresh after a short delay to get any other data
          // that might have changed (e.g., propositions when entering rating)
          if (phaseChanged) {
            Future.delayed(const Duration(milliseconds: 300), () {
              _lastRefreshTime = null; // Reset rate limiter for this refresh
              _scheduleRefresh();
            });
          }
          return;
        } else {
        }
      } else {
      }
    }

    // Fallback to full refresh for other cases
    _scheduleRefresh();
  }

  // Debounced refresh methods with rate limiting
  void _scheduleRefresh() {
    // ignore: avoid_print
    print('[ChatDetailNotifier] _scheduleRefresh called for chat $chatId');
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _minRefreshInterval) {
      // Instead of dropping the request, schedule a deferred refresh
      // This ensures critical updates like phase changes aren't missed
      final timeSinceLastRefresh = now.difference(_lastRefreshTime!);
      final delay = _minRefreshInterval - timeSinceLastRefresh;
      // ignore: avoid_print
      print('[ChatDetailNotifier] Rate limited - deferring refresh by ${delay.inMilliseconds}ms');
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(delay + _debounceDuration, () {
        _lastRefreshTime = DateTime.now();
        // ignore: avoid_print
        print('[ChatDetailNotifier] Deferred refresh executing');
        _loadData();
      });
      return;
    }

    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_debounceDuration, () {
      _lastRefreshTime = DateTime.now();
      // ignore: avoid_print
      print('[ChatDetailNotifier] Debounced refresh executing');
      _loadData();
    });
  }

  void _schedulePropositionRefresh() {
    final now = DateTime.now();
    if (_lastPropositionRefreshTime != null &&
        now.difference(_lastPropositionRefreshTime!) < _minRefreshInterval) {
      // Defer instead of drop
      final timeSinceLastRefresh = now.difference(_lastPropositionRefreshTime!);
      final delay = _minRefreshInterval - timeSinceLastRefresh;
      _propositionDebounce?.cancel();
      _propositionDebounce = Timer(delay + _debounceDuration, () {
        _lastPropositionRefreshTime = DateTime.now();
        _refreshPropositions();
      });
      return;
    }

    _propositionDebounce?.cancel();
    _propositionDebounce = Timer(_debounceDuration, () {
      _lastPropositionRefreshTime = DateTime.now();
      _refreshPropositions();
    });
  }

  void _scheduleJoinRequestRefresh() {
    final now = DateTime.now();
    if (_lastJoinRequestRefreshTime != null &&
        now.difference(_lastJoinRequestRefreshTime!) < _minRefreshInterval) {
      return;
    }

    _joinRequestDebounce?.cancel();
    _joinRequestDebounce = Timer(_debounceDuration, () {
      _lastJoinRequestRefreshTime = DateTime.now();
      _refreshJoinRequests();
    });
  }

  Future<void> _onParticipantsChanged(List<Participant> participants) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // Small delay for transaction visibility
    await Future.delayed(const Duration(milliseconds: 50));

    // Refresh myParticipant to detect if current user was kicked
    final myParticipant = await _participantService.getMyParticipant(chatId);

    state = AsyncData(currentState.copyWith(
      participants: participants,
      myParticipant: myParticipant,
    ));
  }

  Future<void> _refreshJoinRequests() async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    try {
      final requests = await _participantService.getPendingRequests(chatId);
      state = AsyncData(currentState.copyWith(pendingJoinRequests: requests));
    } catch (e) {
      // Log but don't fail - next event will retry
    }
  }

  Future<void> _refreshPropositions() async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.myParticipant == null) {
      return;
    }

    try {
      final results = await Future.wait([
        _propositionService.getPropositions(
          currentState!.currentRound!.id,
          languageCode: languageCode,
        ),
        _propositionService.getMyPropositions(
          currentState.currentRound!.id,
          currentState.myParticipant!.id,
        ),
      ]);

      state = AsyncData(currentState.copyWith(
        propositions: results[0],
        myPropositions: results[1],
      ));
    } catch (e) {
      // Log but don't fail - next refresh will pick it up
    }
  }

  /// Submit a new proposition
  Future<void> submitProposition(String content) async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.myParticipant == null) {
      return;
    }

    await _propositionService.submitProposition(
      roundId: currentState!.currentRound!.id,
      participantId: currentState.myParticipant!.id,
      content: content,
    );

    // Immediately refresh to show own submission (don't wait for debounced realtime)
    await _refreshPropositions();
  }

  /// Start the next phase (host only)
  Future<void> startPhase(Chat chat) async {
    // Prevent multiple clicks while operation is in progress
    if (_isStartingPhase) return;

    final currentState = state.valueOrNull;
    if (currentState == null) return;

    _isStartingPhase = true;
    try {
      if (currentState.currentCycle == null ||
          currentState.currentRound == null) {
        await _chatService.startChat(chatId, chat);
      } else if (currentState.currentRound!.phase == RoundPhase.waiting) {
        await _chatService.startPhase(currentState.currentRound!.id, chat);
      }
      // Realtime will trigger refresh
    } finally {
      _isStartingPhase = false;
    }
  }

  /// Advance from proposing or waiting-for-rating to rating phase (host only)
  /// This handles both:
  /// - Direct advance from proposing (rating_start_mode=auto or manual button)
  /// - Advance from waiting phase when rating_start_mode=manual
  Future<void> advanceToRating(Chat chat) async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null) return;

    final phase = currentState!.currentRound!.phase;
    final hasPropositions = currentState.propositions.isNotEmpty;

    // Allow advancing from proposing OR from waiting-for-rating (waiting with propositions)
    final isWaitingForRating = phase == RoundPhase.waiting && hasPropositions;
    if (phase != RoundPhase.proposing && !isWaitingForRating) {
      return;
    }

    final propositionCount = currentState.propositions.length;
    if (propositionCount < chat.proposingMinimum) {
      throw Exception(
        'Need at least ${chat.proposingMinimum} propositions to start rating. '
        'Currently have $propositionCount.',
      );
    }

    await _chatService.advanceToRating(currentState.currentRound!.id, chat);
    // Realtime will trigger refresh
  }

  /// Complete rating phase and start new round (host only)
  Future<void> completeRatingPhase(Chat chat) async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.currentCycle == null) {
      return;
    }

    await _chatService.completeRatingPhase(
      currentState!.currentRound!.id,
      currentState.currentCycle!.id,
      chat,
    );
    // Realtime will trigger refresh
  }

  /// Manual refresh (pull-to-refresh)
  /// If [silent] is true, keeps current data visible while fetching (no loading spinner)
  Future<void> refresh({bool silent = false}) async {
    _refreshDebounce?.cancel();
    if (!silent) {
      state = const AsyncLoading();
    }
    await _loadData(setupSubscriptions: false);
  }

  void _onChatDeleted() {
    _unsubscribeAll();
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(isDeleted: true));
    } else {
      state = const AsyncData(ChatDetailState(isDeleted: true));
    }
  }

  /// Called after rating to mark hasRated as true
  void markAsRated() {
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(hasRated: true));
    }
    // Schedule refresh for full state update
    _scheduleRefresh();
  }

  /// Delete a proposition (host only)
  Future<void> deleteProposition(int propositionId) async {
    await _propositionService.deleteProposition(propositionId);
    // Realtime will trigger refresh
  }

  /// Delete the entire chat (host only)
  Future<void> deleteChat() async {
    await _chatService.deleteChat(chatId);
    // Realtime will trigger _onChatDeleted
  }

  /// Approve a join request (host only) with optimistic update
  Future<void> approveJoinRequest(int requestId) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // Optimistic update
    state = AsyncData(currentState.copyWith(
      pendingJoinRequests: currentState.pendingJoinRequests
          .where((r) => r['id'] != requestId)
          .toList(),
    ));

    try {
      await _participantService.approveRequest(requestId);
    } catch (_) {
      // Revert on failure
      state = AsyncData(currentState);
      rethrow;
    }
  }

  /// Deny a join request (host only) with optimistic update
  Future<void> denyJoinRequest(int requestId) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // Optimistic update
    state = AsyncData(currentState.copyWith(
      pendingJoinRequests: currentState.pendingJoinRequests
          .where((r) => r['id'] != requestId)
          .toList(),
    ));

    try {
      await _participantService.denyRequest(requestId);
    } catch (_) {
      // Revert on failure
      state = AsyncData(currentState);
      rethrow;
    }
  }

  /// Leave the chat (current user removes themselves)
  Future<void> leaveChat() async {
    final currentState = state.valueOrNull;
    if (currentState?.myParticipant == null) return;

    await _participantService.leaveChat(currentState!.myParticipant!.id);
    // User will navigate away - no refresh needed
  }

  /// Kick a participant (host only)
  Future<void> kickParticipant(int participantId) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // Optimistic update
    state = AsyncData(currentState.copyWith(
      participants: currentState.participants
          .where((p) => p.id != participantId)
          .toList(),
    ));

    try {
      await _participantService.kickParticipant(participantId);
    } catch (_) {
      // Revert on failure
      state = AsyncData(currentState);
      rethrow;
    }
  }

  /// Pause the chat (host only)
  /// Stops the phase timer and saves remaining time
  Future<void> pauseChat() async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;
    if (currentState.myParticipant?.isHost != true) return;

    try {
      await _chatService.hostPauseChat(chatId);
      // Realtime will update state automatically
    } catch (e) {
      // Re-fetch to ensure UI is in sync
      await refresh();
      rethrow;
    }
  }

  /// Resume the chat (host only)
  /// Restores the phase timer from saved time
  Future<void> resumeChat() async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;
    if (currentState.myParticipant?.isHost != true) return;

    try {
      await _chatService.hostResumeChat(chatId);
      // Realtime will update state automatically
    } catch (e) {
      // Re-fetch to ensure UI is in sync
      await refresh();
      rethrow;
    }
  }
}
