import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/chat_credits.dart';
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
  final List<ConsensusItem> consensusItems;
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
  // Skip proposing state
  final int skipCount;
  final bool hasSkipped;
  // Skip rating state
  final int ratingSkipCount;
  final bool hasSkippedRating;
  // Credit state
  final ChatCredits? chatCredits;
  final bool isMyParticipantFunded;
  // Allowed proposition categories for current cycle
  final List<String> allowedCategories;
  // True while translations are being fetched after a language change
  final bool isTranslating;

  /// Whether the UI should show simplified task result mode.
  /// True when the only allowed category is 'human_task_result'.
  bool get isTaskResultMode =>
      allowedCategories.length == 1 &&
      allowedCategories.first == 'human_task_result';

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
    this.skipCount = 0,
    this.hasSkipped = false,
    this.ratingSkipCount = 0,
    this.hasSkippedRating = false,
    this.chatCredits,
    this.isMyParticipantFunded = true,
    this.allowedCategories = const [],
    this.isTranslating = false,
  });

  /// Number of active participants (used for skip quota calculation)
  int get activeParticipantCount =>
      participants.where((p) => p.status == ParticipantStatus.active).length;

  /// Maximum number of skips allowed (participants - proposing_minimum)
  int get maxSkips {
    final minimum = chat?.proposingMinimum ?? 1;
    return (activeParticipantCount - minimum).clamp(0, activeParticipantCount);
  }

  /// Whether the current user can skip proposing
  /// - Must not have already submitted a proposition
  /// - Must not have already skipped
  /// - Skip quota must not be exceeded
  bool get canSkip {
    // Don't count carried forward propositions as submissions
    final newSubmissions = myPropositions.where((p) => !p.isCarriedForward).length;
    return !hasSkipped && newSubmissions == 0 && skipCount < maxSkips;
  }

  /// Maximum number of rating skips allowed (participants - rating_minimum)
  int get maxRatingSkips {
    final minimum = chat?.ratingMinimum ?? 2;
    return (activeParticipantCount - minimum).clamp(0, activeParticipantCount);
  }

  /// Whether the current user can skip rating
  /// - Must not have already rated (fully completed)
  /// - Must not have already skipped rating
  /// - Rating skip quota must not be exceeded
  bool get canSkipRating {
    return !hasSkippedRating &&
        !hasRated &&
        ratingSkipCount < maxRatingSkips;
  }

  ChatDetailState copyWith({
    Chat? chat,
    Cycle? currentCycle,
    Round? currentRound,
    List<ConsensusItem>? consensusItems,
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
    int? skipCount,
    bool? hasSkipped,
    int? ratingSkipCount,
    bool? hasSkippedRating,
    ChatCredits? chatCredits,
    bool? isMyParticipantFunded,
    List<String>? allowedCategories,
    bool? isTranslating,
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
      skipCount: skipCount ?? this.skipCount,
      hasSkipped: hasSkipped ?? this.hasSkipped,
      ratingSkipCount: ratingSkipCount ?? this.ratingSkipCount,
      hasSkippedRating: hasSkippedRating ?? this.hasSkippedRating,
      chatCredits: chatCredits ?? this.chatCredits,
      isMyParticipantFunded: isMyParticipantFunded ?? this.isMyParticipantFunded,
      allowedCategories: allowedCategories ?? this.allowedCategories,
      isTranslating: isTranslating ?? this.isTranslating,
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
        skipCount,
        hasSkipped,
        ratingSkipCount,
        hasSkippedRating,
        chatCredits,
        isMyParticipantFunded,
        allowedCategories,
        isTranslating,
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
  RealtimeChannel? _skipChannel;
  RealtimeChannel? _ratingSkipChannel;
  RealtimeChannel? _creditChannel;

  // Debounce timers
  Timer? _refreshDebounce;
  Timer? _propositionDebounce;
  Timer? _joinRequestDebounce;
  Timer? _skipDebounce;
  Timer? _ratingSkipDebounce;

  // Rate limiting
  DateTime? _lastRefreshTime;
  DateTime? _lastPropositionRefreshTime;
  DateTime? _lastJoinRequestRefreshTime;
  DateTime? _lastSkipRefreshTime;
  DateTime? _lastRatingSkipRefreshTime;

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

  /// Refresh all translatable data when language changes.
  /// Sets isTranslating immediately so the UI can show feedback.
  Future<void> _refreshForLanguageChange() async {
    final current = state.valueOrNull;
    if (current == null) return;
    // Show translating state immediately
    state = AsyncData(current.copyWith(isTranslating: true));
    // Full reload picks up translated consensus items, propositions, winners, etc.
    await _loadData();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _propositionDebounce?.cancel();
    _joinRequestDebounce?.cancel();
    _skipDebounce?.cancel();
    _ratingSkipDebounce?.cancel();
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
    _skipChannel?.unsubscribe();
    _ratingSkipChannel?.unsubscribe();
    _creditChannel?.unsubscribe();
  }

  Future<void> _loadData({bool setupSubscriptions = false}) async {
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
      final consensusItems = results[2] as List<ConsensusItem>;
      var participants = results[3] as List<Participant>;
      var myParticipant = results[4] as Participant?;

      // Auto-join official chat if user is not a participant
      if (myParticipant == null && chat?.isOfficial == true) {
        try {
          myParticipant = await _participantService.joinPublicChat(chatId: chatId);
          // Refetch participants to include self
          participants = await _participantService.getParticipants(chatId);
        } catch (e) {
          // Continue without participant - user can view but not participate
        }
      }

      // Fetch pending join requests if user is host
      List<Map<String, dynamic>> pendingJoinRequests = [];
      if (myParticipant?.isHost == true) {
        pendingJoinRequests =
            await _participantService.getPendingRequests(chatId);
      }

      // Fetch chat credits
      ChatCredits? chatCredits;
      try {
        final creditData = await _supabase
            .from('chat_credits')
            .select()
            .eq('chat_id', chatId)
            .maybeSingle();
        if (creditData != null) {
          chatCredits = ChatCredits.fromJson(creditData);
        }
      } catch (e) {
        debugPrint('[ChatDetail] Error fetching chat credits: $e');
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
      int skipCount = 0;
      bool hasSkipped = false;
      int ratingSkipCount = 0;
      bool hasSkippedRating = false;
      bool isMyParticipantFunded = true;
      List<String> allowedCategories = [];

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
            _propositionService.getSkipCount(currentRound.id),
            _propositionService.hasSkipped(currentRound.id, myParticipant.id),
            _propositionService.getRatingSkipCount(currentRound.id),
            _propositionService.hasSkippedRating(currentRound.id, myParticipant.id),
          ]);

          propositions = roundResults[0] as List<Proposition>;
          myPropositions = roundResults[1] as List<Proposition>;
          final ratingProgress = roundResults[2] as Map<String, dynamic>;
          hasRated = ratingProgress['completed'] as bool;
          hasStartedRating = ratingProgress['started'] as bool;
          skipCount = roundResults[3] as int;
          hasSkipped = roundResults[4] as bool;
          ratingSkipCount = roundResults[5] as int;
          hasSkippedRating = roundResults[6] as bool;

          // Check if my participant is funded for this round
          try {
            final fundingData = await _supabase
                .from('round_funding')
                .select('id')
                .eq('round_id', currentRound.id)
                .eq('participant_id', myParticipant.id)
                .maybeSingle();
            // If round has any funding records, check if we're funded
            // If no funding exists yet, assume funded (backward compat)
            if (fundingData != null) {
              isMyParticipantFunded = true;
            } else {
              final countData = await _supabase.rpc(
                'get_funded_participant_count',
                params: {'p_round_id': currentRound.id},
              );
              isMyParticipantFunded = (countData as int? ?? 0) == 0;
            }
          } catch (e) {
            debugPrint('[ChatDetail] Error checking funding: $e');
          }
        }

        // Fetch allowed proposition categories for current cycle
        try {
          final catData = await _supabase.rpc(
            'get_chat_allowed_categories',
            params: {'p_chat_id': chatId},
          );
          allowedCategories = (catData as List).cast<String>();
        } catch (e) {
          debugPrint('[ChatDetail] Error fetching allowed categories: $e');
        }
      }

      // Guard against stale API data reverting a phase that Realtime already
      // advanced. Realtime events can fire before the DB transaction commits,
      // so a follow-up refresh may read the old phase. If the round ID matches
      // and the current state has a more advanced phase, keep it.
      final existingRound = state.valueOrNull?.currentRound;
      if (currentRound != null &&
          existingRound != null &&
          currentRound.id == existingRound.id &&
          existingRound.phase.index > currentRound.phase.index) {
        currentRound = currentRound.copyWith(
          phase: existingRound.phase,
          phaseStartedAt: existingRound.phaseStartedAt,
          phaseEndsAt: existingRound.phaseEndsAt,
        );
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
        skipCount: skipCount,
        hasSkipped: hasSkipped,
        ratingSkipCount: ratingSkipCount,
        hasSkippedRating: hasSkippedRating,
        chatCredits: chatCredits,
        isMyParticipantFunded: isMyParticipantFunded,
        allowedCategories: allowedCategories,
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
    _cycleChannel = _chatService.subscribeToCycleChanges(
      chatId,
      () {
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

    // Subscribe to credit balance changes
    _creditChannel = _supabase
        .channel('chat_credits:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_credits',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            final newData = payload.newRecord;
            if (newData.isNotEmpty) {
              final currentState = state.valueOrNull;
              if (currentState != null) {
                try {
                  final credits = ChatCredits.fromJson(newData);
                  state = AsyncData(currentState.copyWith(chatCredits: credits));
                  // If user is currently unfunded, credits changing may mean
                  // they were just funded by fund_unfunded_spectators().
                  // Trigger full refresh to re-check funding status.
                  if (!currentState.isMyParticipantFunded) {
                    _scheduleRefresh();
                  }
                } catch (e) {
                  debugPrint('[ChatDetail] Error parsing credit update: $e');
                }
              }
            }
          },
        )
        .subscribe();

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

      // Update skip subscription for current round
      _skipChannel?.unsubscribe();
      _skipChannel = _propositionService.subscribeToSkips(
        currentState.currentRound!.id,
        () {
          _scheduleSkipRefresh();
        },
      );

      // Update rating skip subscription for current round
      _ratingSkipChannel?.unsubscribe();
      _ratingSkipChannel = _propositionService.subscribeToRatingSkips(
        currentState.currentRound!.id,
        () {
          _scheduleRatingSkipRefresh();
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
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < _minRefreshInterval) {
      // Instead of dropping the request, schedule a deferred refresh
      // This ensures critical updates like phase changes aren't missed
      final timeSinceLastRefresh = now.difference(_lastRefreshTime!);
      final delay = _minRefreshInterval - timeSinceLastRefresh;
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(delay + _debounceDuration, () {
        _lastRefreshTime = DateTime.now();
        _loadData();
      });
      return;
    }

    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_debounceDuration, () {
      _lastRefreshTime = DateTime.now();
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

  void _scheduleSkipRefresh() {
    final now = DateTime.now();
    if (_lastSkipRefreshTime != null &&
        now.difference(_lastSkipRefreshTime!) < _minRefreshInterval) {
      // Defer instead of drop
      final timeSinceLastRefresh = now.difference(_lastSkipRefreshTime!);
      final delay = _minRefreshInterval - timeSinceLastRefresh;
      _skipDebounce?.cancel();
      _skipDebounce = Timer(delay + _debounceDuration, () {
        _lastSkipRefreshTime = DateTime.now();
        _refreshSkips();
      });
      return;
    }

    _skipDebounce?.cancel();
    _skipDebounce = Timer(_debounceDuration, () {
      _lastSkipRefreshTime = DateTime.now();
      _refreshSkips();
    });
  }

  Future<void> _onParticipantsChanged(List<Participant> participants) async {
    final currentState = state.valueOrNull;
    if (currentState == null) {
      return;
    }


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

  Future<void> _refreshSkips() async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.myParticipant == null) {
      return;
    }

    try {
      final results = await Future.wait([
        _propositionService.getSkipCount(currentState!.currentRound!.id),
        _propositionService.hasSkipped(
          currentState.currentRound!.id,
          currentState.myParticipant!.id,
        ),
      ]);

      final skipCount = results[0] as int;
      final hasSkipped = results[1] as bool;

      final updatedState = currentState.copyWith(
        skipCount: skipCount,
        hasSkipped: hasSkipped,
      );
      state = AsyncData(updatedState);
      _cachedState = updatedState;
    } catch (e) {
      // Log but don't fail - next event will retry
    }
  }

  void _scheduleRatingSkipRefresh() {
    final now = DateTime.now();
    if (_lastRatingSkipRefreshTime != null &&
        now.difference(_lastRatingSkipRefreshTime!) < _minRefreshInterval) {
      // Defer instead of drop
      final timeSinceLastRefresh = now.difference(_lastRatingSkipRefreshTime!);
      final delay = _minRefreshInterval - timeSinceLastRefresh;
      _ratingSkipDebounce?.cancel();
      _ratingSkipDebounce = Timer(delay + _debounceDuration, () {
        _lastRatingSkipRefreshTime = DateTime.now();
        _refreshRatingSkips();
      });
      return;
    }

    _ratingSkipDebounce?.cancel();
    _ratingSkipDebounce = Timer(_debounceDuration, () {
      _lastRatingSkipRefreshTime = DateTime.now();
      _refreshRatingSkips();
    });
  }

  Future<void> _refreshRatingSkips() async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.myParticipant == null) {
      return;
    }

    try {
      final results = await Future.wait([
        _propositionService.getRatingSkipCount(currentState!.currentRound!.id),
        _propositionService.hasSkippedRating(
          currentState.currentRound!.id,
          currentState.myParticipant!.id,
        ),
      ]);

      final ratingSkipCount = results[0] as int;
      final hasSkippedRating = results[1] as bool;

      final updatedState = currentState.copyWith(
        ratingSkipCount: ratingSkipCount,
        hasSkippedRating: hasSkippedRating,
      );
      state = AsyncData(updatedState);
      _cachedState = updatedState;
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
    final sw = Stopwatch()..start();
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
    debugPrint('[submitProposition] edge function call: ${sw.elapsedMilliseconds}ms');

    // Immediately refresh to show own submission (don't wait for debounced realtime)
    await _refreshPropositions();
    debugPrint('[submitProposition] total (incl refresh): ${sw.elapsedMilliseconds}ms');
  }

  /// Skip proposing for the current round
  ///
  /// User must not have already submitted and skip quota must not be exceeded.
  /// Skippers count toward participation for early advance calculations.
  Future<void> skipProposing() async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.myParticipant == null) {
      return;
    }

    // Validate canSkip before calling service
    if (!currentState!.canSkip) {
      throw Exception('Cannot skip: already submitted, already skipped, or skip quota exceeded');
    }

    await _propositionService.skipProposing(
      roundId: currentState.currentRound!.id,
      participantId: currentState.myParticipant!.id,
    );

    // Immediately update local state (optimistic)
    final updatedState = currentState.copyWith(
      hasSkipped: true,
      skipCount: currentState.skipCount + 1,
    );
    state = AsyncData(updatedState);
    _cachedState = updatedState;

    // Refresh to get accurate skip count from server
    await _refreshSkips();
  }

  /// Skip rating for the current round
  ///
  /// User must not have already rated or started rating, and skip quota must not be exceeded.
  /// Skippers count toward participation for early advance calculations.
  Future<void> skipRating() async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.myParticipant == null) {
      return;
    }

    // Validate canSkipRating before calling service
    if (!currentState!.canSkipRating) {
      throw Exception('Cannot skip rating: already rated, already skipped, or skip quota exceeded');
    }

    if (currentState.hasStartedRating) {
      // Use cleanup version to delete intermediate grid_rankings first
      await _propositionService.skipRatingWithCleanup(
        roundId: currentState.currentRound!.id,
        participantId: currentState.myParticipant!.id,
      );
    } else {
      await _propositionService.skipRating(
        roundId: currentState.currentRound!.id,
        participantId: currentState.myParticipant!.id,
      );
    }

    // Immediately update local state (optimistic)
    final updatedState = currentState.copyWith(
      hasSkippedRating: true,
      ratingSkipCount: currentState.ratingSkipCount + 1,
    );
    state = AsyncData(updatedState);
    _cachedState = updatedState;

    // Refresh to get accurate skip count from server
    await _refreshRatingSkips();
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

  /// Delete a consensus on the server (host only).
  /// Used from Dismissible.confirmDismiss — no local state changes,
  /// so the Dismissible can snap back on failure.
  Future<void> deleteConsensusOnServer(int cycleId) async {
    await _chatService.deleteConsensus(cycleId);
  }

  /// Called from Dismissible.onDismissed after consensus delete succeeds.
  /// Removes the item from local state immediately (cleans up task result
  /// card too), then refreshes from server to pick up cycle restart.
  void onConsensusDismissed(int cycleId) {
    final current = state.valueOrNull;
    if (current != null) {
      final updatedItems = current.consensusItems
          .where((item) => item.cycleId != cycleId)
          .toList();
      state = AsyncData(current.copyWith(consensusItems: updatedItems));
    }
    _loadData(); // Refresh to pick up new round from cycle restart
  }

  /// Delete research results on the server (host only).
  /// Used from Dismissible.confirmDismiss — no local state changes.
  Future<void> deleteTaskResultOnServer(int cycleId) async {
    await _chatService.deleteTaskResult(cycleId);
  }

  /// Called from Dismissible.onDismissed after task result delete succeeds.
  /// Removes the task result from local state, then refreshes from server.
  void onTaskResultDismissed(int cycleId) {
    final current = state.valueOrNull;
    if (current != null) {
      final updatedItems = current.consensusItems.map((item) {
        if (item.cycleId == cycleId) {
          return item.copyWith(taskResult: () => null);
        }
        return item;
      }).toList();
      state = AsyncData(current.copyWith(consensusItems: updatedItems));
    }
    _loadData(); // Refresh to pick up changes
  }

  /// Force a proposition directly as consensus (host only)
  Future<void> forceConsensus(String content) async {
    try {
      await _chatService.forceConsensus(chatId, content);
      await _loadData(); // Full refresh to pick up new consensus + new cycle
    } catch (e) {
      rethrow;
    }
  }

  /// Update the initial message (host only)
  Future<void> updateInitialMessage(String newMessage) async {
    try {
      await _chatService.updateInitialMessage(chatId, newMessage);
      await _loadData(); // Refresh to pick up new message + potential restart
    } catch (e) {
      rethrow;
    }
  }

  /// Delete the initial message (host only)
  Future<void> deleteInitialMessage() async {
    try {
      await _chatService.deleteInitialMessage(chatId);
      await _loadData();
    } catch (e) {
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
