import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/l10n/language_service.dart';
import '../../core/l10n/locale_provider.dart';
import '../../models/models.dart';
import '../../services/affirmation_service.dart';
import '../../services/chat_service.dart';
import '../../services/participant_service.dart';
import '../../services/proposition_service.dart';
import '../../utils/perf_logger.dart';
import '../mixins/language_aware_mixin.dart';
import '../providers.dart';

/// REALTIME-RACE-DEBUG (2026-05-02): emit events to perf_logs from
/// every realtime handler so we can reconstruct each client's
/// arrival timeline + resulting state. Tag is `rt_race.<event>`.
/// Remove with the call sites before merge.
void _rtRaceLog(String event, {int? chatId, int? roundId,
    Map<String, dynamic>? payload}) {
  PerfLogger.start('rt_race.$event',
      chatId: chatId, roundId: roundId, payload: payload);
}

void _rtRaceSnapshot(String trigger, ChatDetailState s) {
  final r = s.currentRound;
  PerfLogger.start(
    'rt_race.snapshot',
    chatId: s.chat?.id,
    roundId: r?.id,
    payload: {
      'trigger': trigger,
      'phase': r?.phase.name,
      'phase_ends_at': r?.phaseEndsAt?.toIso8601String(),
      'rating_progress_percent': s.ratingProgressPercent,
      'rating_skip_count': s.ratingSkipCount,
      'skip_count': s.skipCount,
      'has_skipped': s.hasSkipped,
      'has_skipped_rating': s.hasSkippedRating,
      'has_started_rating': s.hasStartedRating,
      'has_rated': s.hasRated,
      'props': s.propositions.length,
      'my_props': s.myPropositions.length,
      'participants': s.participants.length,
      'skipped_proposing': s.participantsWhoSkippedProposing.length,
      'skipped_rating': s.participantsWhoSkippedRating.length,
      'affirmed': s.participantsWhoAffirmed.length,
    },
  );
}

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
  // Affirmation state for the current proposing round (R2+ "I support
  // the carried-forward winner" action). Counts toward participation %
  // alongside submitters and skippers.
  final int affirmationCount;
  final bool hasAffirmed;
  // Participants who have submitted ratings in the current round
  final Set<int> participantsWhoRated;
  // Participants who have submitted a NEW proposition in the current round.
  // Drives the proposing-phase "Done" tag on the participants leaderboard —
  // proposition authorship is hidden client-side during proposing, so this
  // set (from the SECURITY DEFINER bootstrap RPC) is the only who-proposed
  // signal. Exposes participation only, never idea content.
  final Set<int> participantsWhoProposed;
  // Participants who have skipped proposing in the current round
  final Set<int> participantsWhoSkippedProposing;
  // Participants who have skipped rating in the current round
  final Set<int> participantsWhoSkippedRating;
  // Participants who have affirmed in the current proposing round.
  final Set<int> participantsWhoAffirmed;
  // Minimum rating count across all propositions (for per-proposition progress bar)
  final int minRatingsPerProp;
  // Number of grid_rankings rows the current user has in the current round.
  // Used to gate the "Skip Rating" UI — skip is only available when this is 0.
  // Kept fresh by the existing grid_rankings realtime subscription.
  final int myCurrentRoundRatingCount;
  // Matches (pairwise) mode group progress. Populated only when
  // chat.ratingMode == 'matches' (via get_matches_rating_progress). done =
  // raters finished (completion marker / grid coverage / skip); eligible =
  // get_rating_eligible_count. Drives the round-status bar in matches mode.
  final int matchesDoneRaters;
  final int matchesEligibleRaters;
  // Credit state
  final ChatCredits? chatCredits;
  final bool isMyParticipantFunded;
  // Allowed proposition categories for current cycle
  final List<String> allowedCategories;
  // True while translations are being fetched after a language change
  final bool isTranslating;
  // Per-chat content language (separate from app UI language)
  final String? viewingLanguageCode;
  // True when user must pick a content language (their app language isn't in this chat's languages)
  final bool needsLanguageSelection;

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
    this.affirmationCount = 0,
    this.hasAffirmed = false,
    this.participantsWhoRated = const {},
    this.participantsWhoProposed = const {},
    this.participantsWhoSkippedProposing = const {},
    this.participantsWhoSkippedRating = const {},
    this.participantsWhoAffirmed = const {},
    this.minRatingsPerProp = 0,
    this.myCurrentRoundRatingCount = 0,
    this.matchesDoneRaters = 0,
    this.matchesEligibleRaters = 0,
    this.chatCredits,
    this.isMyParticipantFunded = true,
    this.allowedCategories = const [],
    this.isTranslating = false,
    this.viewingLanguageCode,
    this.needsLanguageSelection = false,
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
  /// - Chat must allow skipping proposing
  /// - Must not have already submitted a proposition
  /// - Must not have already skipped
  /// - Skip quota must not be exceeded
  bool get canSkip {
    if (chat?.allowSkipProposing != true) return false;
    // Don't count carried forward propositions as submissions
    final newSubmissions = myPropositions.where((p) => !p.isCarriedForward).length;
    return !hasSkipped && newSubmissions == 0 && skipCount < maxSkips;
  }

  /// Maximum number of rating skips allowed (participants - rating_minimum)
  int get maxRatingSkips {
    final minimum = chat?.ratingMinimum ?? 2;
    return (activeParticipantCount - minimum).clamp(0, activeParticipantCount);
  }

  /// Per-proposition advance threshold for rating phase.
  /// min(10, max(active_raters - selfExcl, 1)) where active_raters excludes
  /// skippers. selfExcl is 1 (a prop's author can't rate it) except in
  /// conditional-self-inclusion rounds (<= 2 props: authors rate their own
  /// too, so every prop's audience is the full rater set). Keep in sync with
  /// recompute_round_participation_percent / check_early_advance_on_rating.
  int get ratingAdvanceThreshold {
    final activeRaters = activeParticipantCount - ratingSkipCount;
    if (activeRaters <= 0) return 1;
    final selfExcl = propositions.length <= 2 ? 0 : 1;
    final raw = activeRaters - selfExcl;
    return raw < 1 ? 1 : (raw > 10 ? 10 : raw);
  }

  /// Rating progress percentage (0-100).
  /// Matches mode: per-RATER completion (done / eligible) — pairwise votes
  /// never touch grid_rankings, so the grid coverage formula would read 0.
  /// Grid mode: per-proposition coverage, min(ratings per prop) / threshold.
  int get ratingProgressPercent {
    if (chat?.ratingMode == 'matches') {
      if (matchesEligibleRaters <= 0) return 0;
      return ((matchesDoneRaters / matchesEligibleRaters) * 100)
          .round()
          .clamp(0, 100);
    }
    final threshold = ratingAdvanceThreshold;
    if (threshold <= 0) return 100;
    return ((minRatingsPerProp / threshold) * 100).round().clamp(0, 100);
  }

  /// Whether the current user can skip rating
  /// - Chat must allow skipping rating
  /// - Must not have already rated (fully completed)
  /// - Must not have already skipped rating
  /// - Rating skip quota must not be exceeded
  /// - Must not have placed any ratings yet — the rating_skips RLS policy
  ///   refuses to insert if any grid_rankings rows already exist for the
  ///   participant in this round. Undoing all placements (which deletes the
  ///   rows server-side) re-enables skip.
  bool get canSkipRating {
    if (chat?.allowSkipRating != true) return false;
    return !hasSkippedRating &&
        !hasRated &&
        ratingSkipCount < maxRatingSkips;
    // myCurrentRoundRatingCount intentionally NOT gated: a user mid-rating
    // (e.g. binary placed but not yet positioning) must still be able to
    // skip. skipRating() routes to skipRatingWithCleanup() which deletes
    // intermediate grid_rankings before inserting the skip row, so the
    // partial state gets wiped atomically. Gating the button here would
    // strand them — Skip disappears the moment they place anything, but
    // the chat screen still flags them as "in progress" so they're stuck.
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
    int? affirmationCount,
    bool? hasAffirmed,
    Set<int>? participantsWhoRated,
    Set<int>? participantsWhoProposed,
    Set<int>? participantsWhoSkippedProposing,
    Set<int>? participantsWhoSkippedRating,
    Set<int>? participantsWhoAffirmed,
    int? minRatingsPerProp,
    int? myCurrentRoundRatingCount,
    int? matchesDoneRaters,
    int? matchesEligibleRaters,
    ChatCredits? chatCredits,
    bool? isMyParticipantFunded,
    List<String>? allowedCategories,
    bool? isTranslating,
    String? viewingLanguageCode,
    bool? needsLanguageSelection,
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
      affirmationCount: affirmationCount ?? this.affirmationCount,
      hasAffirmed: hasAffirmed ?? this.hasAffirmed,
      participantsWhoRated: participantsWhoRated ?? this.participantsWhoRated,
      participantsWhoProposed: participantsWhoProposed ?? this.participantsWhoProposed,
      participantsWhoSkippedProposing: participantsWhoSkippedProposing ?? this.participantsWhoSkippedProposing,
      participantsWhoSkippedRating: participantsWhoSkippedRating ?? this.participantsWhoSkippedRating,
      participantsWhoAffirmed: participantsWhoAffirmed ?? this.participantsWhoAffirmed,
      minRatingsPerProp: minRatingsPerProp ?? this.minRatingsPerProp,
      myCurrentRoundRatingCount:
          myCurrentRoundRatingCount ?? this.myCurrentRoundRatingCount,
      matchesDoneRaters: matchesDoneRaters ?? this.matchesDoneRaters,
      matchesEligibleRaters:
          matchesEligibleRaters ?? this.matchesEligibleRaters,
      chatCredits: chatCredits ?? this.chatCredits,
      isMyParticipantFunded: isMyParticipantFunded ?? this.isMyParticipantFunded,
      allowedCategories: allowedCategories ?? this.allowedCategories,
      isTranslating: isTranslating ?? this.isTranslating,
      viewingLanguageCode: viewingLanguageCode ?? this.viewingLanguageCode,
      needsLanguageSelection: needsLanguageSelection ?? this.needsLanguageSelection,
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
        affirmationCount,
        hasAffirmed,
        participantsWhoRated,
        participantsWhoProposed,
        participantsWhoSkippedProposing,
        participantsWhoSkippedRating,
        participantsWhoAffirmed,
        minRatingsPerProp,
        myCurrentRoundRatingCount,
        matchesDoneRaters,
        matchesEligibleRaters,
        chatCredits,
        isMyParticipantFunded,
        allowedCategories,
        isTranslating,
        viewingLanguageCode,
        needsLanguageSelection,
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

/// Routing decision for the rating-skip action.
///
///   reject  — caller is in a state where skip isn't allowed (already
///             rated, already skipped, quota exceeded, chat disallows).
///   cleanup — caller has placed grid rankings; route through the
///             skip_rating_with_cleanup RPC so the partial state gets
///             wiped atomically before the skip row is inserted.
///   direct  — caller has no grid rankings yet; the simple insert path
///             is enough.
///
/// Extracted from `ChatDetailNotifier.skipRating` so the gate logic is
/// independently testable. The earlier inline form was the source of
/// the bug fixed in 2d5e3cd: a stricter `canSkipRating` gate hid the
/// cleanup branch behind a check it never satisfied.
enum SkipRatingRoute { reject, cleanup, direct }

/// Decides which skip-rating path to take for a given chat state.
/// Pure function — no side effects, no service calls — so the gate
/// matrix is testable as a 3-line unit test instead of a full notifier
/// integration.
SkipRatingRoute decideSkipRatingRoute(ChatDetailState state) {
  if (!state.canSkipRating) return SkipRatingRoute.reject;
  return state.hasStartedRating
      ? SkipRatingRoute.cleanup
      : SkipRatingRoute.direct;
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
  final AffirmationService _affirmationService;
  final SupabaseClient _supabase;
  final LanguageService _languageService;

  /// Content language for this chat (per-chat viewing language, falling back to app language).
  String get contentLanguageCode =>
      state.valueOrNull?.viewingLanguageCode ?? languageCode;

  // Realtime subscriptions
  RealtimeChannel? _chatChannel;
  RealtimeChannel? _cycleChannel;
  RealtimeChannel? _roundChannel;
  RealtimeChannel? _participantChannel;
  RealtimeChannel? _propositionChannel;
  RealtimeChannel? _joinRequestChannel;
  RealtimeChannel? _skipChannel;
  RealtimeChannel? _ratingSkipChannel;
  RealtimeChannel? _gridRankingChannel;
  RealtimeChannel? _ratingCompletionChannel;
  RealtimeChannel? _creditChannel;
  RealtimeChannel? _affirmationChannel;

  // Debounce timers
  Timer? _refreshDebounce;
  Timer? _propositionDebounce;
  Timer? _joinRequestDebounce;
  Timer? _skipDebounce;
  Timer? _ratingSkipDebounce;
  Timer? _affirmationDebounce;

  // Rate limiting (only the full-refresh + join-request paths still need
  // dedicated rate limiters; the skip/affirm/proposition paths now patch
  // realtime events directly so a per-event timestamp would be overkill).
  DateTime? _lastRefreshTime;
  DateTime? _lastJoinRequestRefreshTime;

  // Cache last known state for use during loading
  ChatDetailState? _cachedState;

  // Prevent multiple startPhase clicks
  bool _isStartingPhase = false;
  bool get isStartingPhase => _isStartingPhase;

  // Concurrent-load guard. Without this, Realtime cascades (e.g. a single
  // pause click fires chats UPDATE → cycles UPDATE → chat_credits UPDATE
  // → ...) trigger overlapping _loadData calls. Eight in flight at once
  // serialize on the DB connection pool, each one slower than the last.
  // Observed in perf_logs: a single pause produced 8 chat_detail_load
  // events spanning 13 seconds with the slowest at 5.2s (vs 1.6s alone).
  // Mutex collapses the storm: while one load is running, new
  // _scheduleRefresh calls flip a "pending" flag; when the running load
  // finishes, ONE more refresh is scheduled if pending.
  bool _isLoading = false;
  bool _pendingRefresh = false;

  static const _debounceDuration = Duration(milliseconds: 150);
  static const _minRefreshInterval = Duration(seconds: 1);

  ChatDetailNotifier({
    required Ref ref,
    required this.chatId,
    required this.showPreviousResults,
  })  : _chatService = ref.read(chatServiceProvider),
        _participantService = ref.read(participantServiceProvider),
        _propositionService = ref.read(propositionServiceProvider),
        _affirmationService = ref.read(affirmationServiceProvider),
        _supabase = ref.read(supabaseProvider),
        _languageService = ref.read(languageServiceProvider),
        super(const AsyncLoading()) {
    initializeLanguageSupport(ref);
    _loadData(setupSubscriptions: true);
  }

  @override
  void onLanguageChanged(String newLanguageCode) {
    // No-op: app language changes should NOT refresh chat content.
    // Chat content is controlled by the per-chat viewingLanguageCode.
  }

  /// Set the per-chat viewing language and reload content.
  /// Persists locally (SharedPreferences) and remotely (participants table).
  Future<void> setViewingLanguage(String code) async {
    await _languageService.setChatViewingLanguage(chatId, code);
    // Sync to participant row so home screen can use it
    _participantService.updateViewingLanguage(chatId, code);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      viewingLanguageCode: code,
      needsLanguageSelection: false,
      isTranslating: true,
    ));
    await _loadData();
  }

  /// Resolve which content language to use when entering the chat.
  /// Called after the first _loadData() completes, once we know the chat's translation settings.
  void _resolveViewingLanguage(Chat? chat) {
    if (chat == null) return;

    final current = state.valueOrNull;
    if (current == null) return;

    // If translations aren't enabled or single language, no selection needed
    if (!chat.translationsEnabled || chat.translationLanguages.length <= 1) {
      final autoLang = chat.translationLanguages.isNotEmpty
          ? chat.translationLanguages.first
          : languageCode;
      state = AsyncData(current.copyWith(
        viewingLanguageCode: autoLang,
        needsLanguageSelection: false,
      ));
      return;
    }

    // Check persisted preference
    final persisted = _languageService.getChatViewingLanguage(chatId);
    if (persisted != null && chat.translationLanguages.contains(persisted)) {
      state = AsyncData(current.copyWith(
        viewingLanguageCode: persisted,
        needsLanguageSelection: false,
      ));
      return;
    }

    // Check if app language is in chat's languages
    if (chat.translationLanguages.contains(languageCode)) {
      _languageService.setChatViewingLanguage(chatId, languageCode);
      state = AsyncData(current.copyWith(
        viewingLanguageCode: languageCode,
        needsLanguageSelection: false,
      ));
      return;
    }

    // Smart fallback: check user's spoken languages
    final spokenLanguages = _languageService.getSpokenLanguages();
    for (final lang in spokenLanguages) {
      if (chat.translationLanguages.contains(lang)) {
        _languageService.setChatViewingLanguage(chatId, lang);
        state = AsyncData(current.copyWith(
          viewingLanguageCode: lang,
          needsLanguageSelection: false,
        ));
        return;
      }
    }

    // User's language not supported — prompt them to choose
    state = AsyncData(current.copyWith(needsLanguageSelection: true));
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _propositionDebounce?.cancel();
    _joinRequestDebounce?.cancel();
    _skipDebounce?.cancel();
    _ratingSkipDebounce?.cancel();
    _affirmationDebounce?.cancel();
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
    _affirmationChannel?.unsubscribe();
    _gridRankingChannel?.unsubscribe();
    _ratingCompletionChannel?.unsubscribe();
    _creditChannel?.unsubscribe();
  }

  Future<void> _loadData({bool setupSubscriptions = false}) async {
    // Concurrent-load guard. If a load is already running, mark that we
    // need another pickup once it finishes and bail out. The pending
    // refresh fires in the finally block, so we still get the latest
    // state — just without 8 parallel loads competing for the pool.
    if (_isLoading) {
      _pendingRefresh = true;
      // Best-effort observability: log the suppression so we can see
      // in perf_logs how many cascades the guard collapsed.
      PerfLogger.start(
        'chat_detail_load_suppressed',
        chatId: chatId,
      );
      return;
    }
    _isLoading = true;
    final perfCorr = PerfLogger.start(
      'chat_detail_load',
      chatId: chatId,
      payload: {'setup_subscriptions': setupSubscriptions},
    );
    try {
      // One round-trip replaces the 18 parallel queries this method used
      // to fire. The bootstrap RPC does the joins/aggregations server-side
      // and returns one JSONB payload — at NCDD demo scale this avoids the
      // connection-pool stampede where queue depth grew faster than the
      // server could drain it (~13s pause→render lag).
      final boot = await _chatService.getChatDetailBootstrap(
        chatId,
        languageCode: contentLanguageCode,
        includePreviousResults: showPreviousResults,
      );

      if (boot == null) {
        // Caller can't view this chat (deleted, kicked, etc). Mirror the
        // null-state the old query path would produce so downstream UI
        // sees a "chat is gone" outcome rather than spinning forever.
        final newState = ChatDetailState(
          chat: null,
          currentCycle: null,
          currentRound: null,
          consensusItems: const [],
          propositions: const [],
          participants: const [],
          myParticipant: null,
          myPropositions: const [],
          hasRated: false,
          hasStartedRating: false,
          previousRoundWinners: const [],
          isSoleWinner: false,
          consecutiveSoleWins: 0,
          previousRoundId: null,
          previousRoundResults: const [],
          pendingJoinRequests: const [],
          skipCount: 0,
          hasSkipped: false,
          ratingSkipCount: 0,
          hasSkippedRating: false,
          affirmationCount: 0,
          hasAffirmed: false,
          participantsWhoRated: const {},
          participantsWhoProposed: const {},
          participantsWhoSkippedProposing: const {},
          participantsWhoSkippedRating: const {},
          participantsWhoAffirmed: const {},
          minRatingsPerProp: 0,
          myCurrentRoundRatingCount: 0,
          chatCredits: null,
          isMyParticipantFunded: true,
          allowedCategories: const [],
          viewingLanguageCode: state.valueOrNull?.viewingLanguageCode,
          needsLanguageSelection:
              state.valueOrNull?.needsLanguageSelection ?? false,
        );
        state = AsyncData(newState);
        _cachedState = newState;
        PerfLogger.end(perfCorr,
            action: 'chat_detail_load', chatId: chatId);
        return;
      }

      Round? currentRound = boot.currentRound;

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

      // Preserve per-chat viewing language across reloads
      final existingViewingLang = state.valueOrNull?.viewingLanguageCode;
      final existingNeedsLangSelection =
          state.valueOrNull?.needsLanguageSelection ?? false;

      final newState = ChatDetailState(
        chat: boot.chat,
        currentCycle: boot.currentCycle,
        currentRound: currentRound,
        consensusItems: boot.consensusItems,
        propositions: boot.propositions,
        participants: boot.participants,
        myParticipant: boot.myParticipant,
        myPropositions: boot.myPropositions,
        hasRated: boot.hasRated,
        hasStartedRating: boot.hasStartedRating,
        previousRoundWinners: boot.previousRoundWinners,
        isSoleWinner: boot.isSoleWinner,
        consecutiveSoleWins: boot.consecutiveSoleWins,
        previousRoundId: boot.previousRoundId,
        previousRoundResults: boot.previousRoundResults,
        pendingJoinRequests: boot.pendingJoinRequests,
        skipCount: boot.skipCount,
        hasSkipped: boot.hasSkipped,
        ratingSkipCount: boot.ratingSkipCount,
        hasSkippedRating: boot.hasSkippedRating,
        affirmationCount: boot.affirmationCount,
        hasAffirmed: boot.hasAffirmed,
        participantsWhoRated: boot.participantsWhoRated,
        participantsWhoProposed: boot.participantsWhoProposed,
        participantsWhoSkippedProposing: boot.participantsWhoSkippedProposing,
        participantsWhoSkippedRating: boot.participantsWhoSkippedRating,
        participantsWhoAffirmed: boot.participantsWhoAffirmed,
        minRatingsPerProp: boot.minRatingsPerProp,
        myCurrentRoundRatingCount: boot.myCurrentRoundRatingCount,
        chatCredits: boot.chatCredits,
        isMyParticipantFunded: boot.isMyParticipantFunded,
        allowedCategories: boot.allowedCategories,
        viewingLanguageCode: existingViewingLang,
        needsLanguageSelection: existingNeedsLangSelection,
      );
      state = AsyncData(newState);
      _cachedState = newState;

      // Matches mode: the round-status bar reads done/eligible raters
      // (pairwise votes never touch grid_rankings, so minRatingsPerProp stays
      // 0). Patch it in after the fast bootstrap so grid chats pay nothing.
      if (boot.chat?.ratingMode == 'matches' && currentRound != null) {
        await _refreshMatchesProgress(currentRound.id);
      }

      // On first load, resolve which content language to use
      if (existingViewingLang == null && !existingNeedsLangSelection) {
        _resolveViewingLanguage(boot.chat);
      }

      if (setupSubscriptions) {
        _setupSubscriptions();
      } else {
        _updateDynamicSubscriptions();
      }
      PerfLogger.end(perfCorr,
          action: 'chat_detail_load', chatId: chatId);
    } catch (e, st) {
      PerfLogger.error(perfCorr, e,
          action: 'chat_detail_load',
          chatId: chatId,
          stackTrace: st);
      state = AsyncError(e, st);
    } finally {
      _isLoading = false;
      // Drain any refresh requests that arrived while we were loading.
      // Goes through _scheduleRefresh so it picks up the existing
      // 150ms debounce + 1s rate limit (and any further suppressions
      // if more events keep arriving).
      if (_pendingRefresh) {
        _pendingRefresh = false;
        _scheduleRefresh();
      }
    }
  }

  /// Matches mode only: fetch group rating progress (done / eligible raters)
  /// and patch it into state. Best-effort — never breaks the load.
  Future<void> _refreshMatchesProgress(int roundId) async {
    try {
      final res = await _supabase.rpc(
        'get_matches_rating_progress',
        params: {'p_round_id': roundId, 'p_chat_id': chatId},
      );
      if (res is List && res.isNotEmpty) {
        final row = res.first as Map<String, dynamic>;
        final done = (row['done'] as num?)?.toInt() ?? 0;
        final eligible = (row['eligible'] as num?)?.toInt() ?? 0;
        final cur = state.valueOrNull;
        if (cur != null) {
          final patched = cur.copyWith(
            matchesDoneRaters: done,
            matchesEligibleRaters: eligible,
          );
          state = AsyncData(patched);
          _cachedState = patched;
        }
      }
    } catch (_) {
      // Progress bar is best-effort; a failure here must not break the chat.
    }
  }

  void _setupSubscriptions() {
    _unsubscribeAll();

    // Subscribe to chat changes (including delete).
    //
    // Most `chats` UPDATE events are operational ticks — host_paused,
    // schedule_paused, last_activity_at — which we can merge into the
    // current Chat without refetching. The full bootstrap is only needed
    // when something structural changed that the Realtime payload doesn't
    // cover (notably translated columns, which live in a separate table).
    // _onChatUpdate handles the patch-vs-refresh decision.
    _chatChannel = _chatService.subscribeToChatChanges(
      chatId,
      onUpdate: _onChatUpdate,
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
                  // Error parsing credit update - ignore
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

    // Update proposition subscription if round exists. Each subscription
    // here uses payload-aware callbacks so we can merge state in place
    // and avoid the cross-client cascade — when one user submits, all
    // 20 subscribers used to fan out 3 queries each. Now they merge
    // the payload locally and only refetch on edge cases.
    if (currentState.currentRound != null) {
      final roundId = currentState.currentRound!.id;

      // DEBUG (perflog): record every (re)bind of the proposition channel and
      // which round/phase it bound to — pinpoints whether the host actually
      // re-subscribes to the new round after Start (the live-count bug).
      _rtRaceLog('dyn_subs.bind_props', roundId: roundId, payload: {
        'phase': currentState.currentRound!.phase.name,
        'cycle': currentState.currentCycle?.id,
        'props_in_state': currentState.propositions.length,
      });

      _propositionChannel?.unsubscribe();
      _propositionChannel = _propositionService.subscribeToPropositions(
        roundId,
        _onPropositionRealtime,
      );

      _skipChannel?.unsubscribe();
      _skipChannel = _propositionService.subscribeToSkips(
        roundId,
        _onRoundSkipRealtime,
      );

      _affirmationChannel?.unsubscribe();
      _affirmationChannel = _affirmationService.subscribeToAffirmations(
        roundId,
        _onAffirmationRealtime,
      );

      _ratingSkipChannel?.unsubscribe();
      _ratingSkipChannel = _propositionService.subscribeToRatingSkips(
        roundId,
        _onRatingSkipRealtime,
      );

      // Grid rankings drive the participants_who_rated set, which is
      // computed across all rows via the rating-cap rule. Patching it
      // in place is much trickier (need access to all per-participant
      // rated counts to recompute "is done"). Defer to a focused
      // refetch via _scheduleRefresh; cheap because it's debounced.
      _gridRankingChannel?.unsubscribe();
      _gridRankingChannel = _propositionService.subscribeToGridRankings(
        roundId,
        () => _scheduleRefresh(),
      );

      // All modes: one event per rater when they finish rating (grid batch
      // submit or matches pair-exhaustion). Patches participantsWhoRated in
      // place so Done tags flip live — the only per-rater grid signal we
      // get, since grid_rankings is deliberately not in the publication.
      _ratingCompletionChannel?.unsubscribe();
      _ratingCompletionChannel =
          _propositionService.subscribeToRatingCompletions(
        roundId,
        _onRatingCompletionRealtime,
      );
    } else {
    }

    // Set up join request subscription (in case host status changed)
    _setupJoinRequestSubscription();
  }

  /// Handle round changes from realtime subscription
  ///
  /// Phase changes (and new-round INSERTs) trigger a full bootstrap
  /// refetch — bootstrap is the source of truth on those, because a
  /// single logical change ("round advanced to rating") is split across
  /// multiple Postgres realtime events on independent subscriptions
  /// (rounds UPDATE + rating_skips INSERTs from the stranded-rater
  /// trigger + carried-forward propositions from on_round_winner_set,
  /// etc.). Patching state from each event individually means arrival
  /// order changes local state, which produced the May 2026 bugs:
  /// auto-nav guard racing the rating_skips realtime, participation bar
  /// lagging 5–11s across viewers for the same underlying event,
  /// stranded users bouncing through the rating screen with "not enough
  /// propositions."
  ///
  /// Timer-only updates (phase_ends_at changing while phase stays the
  /// same — process-timers cron extends every 30s while below minimum)
  /// patch in place. These are frequent and consistency-safe:
  /// phase_ends_at is independent of any other state, and the timer
  /// widget reads it directly.
  void _onRoundChange(
    PostgresChangeEvent event,
    Map<String, dynamic>? newRecord,
  ) {
    _rtRaceLog('round_${event.name}',
        roundId: newRecord?['id'] as int?,
        payload: {
          'phase': newRecord?['phase'],
          'phase_ends_at': newRecord?['phase_ends_at'],
        });
    final currentState = state.valueOrNull ?? _cachedState;
    if (currentState == null) {
      _rtRaceLog('round_${event.name}.bail_no_state');
      return;
    }

    if (event == PostgresChangeEvent.insert) {
      _rtRaceLog('round_insert.refetch_scheduled',
          roundId: newRecord?['id'] as int?);
      _scheduleRefresh();
      return;
    }

    if (event == PostgresChangeEvent.update && newRecord != null) {
      final roundId = newRecord['id'] as int?;
      final phaseStr = newRecord['phase'] as String?;
      if (roundId != currentState.currentRound?.id || phaseStr == null) {
        _rtRaceLog('round_update.refetch_other_round',
            roundId: roundId,
            payload: {'current_round': currentState.currentRound?.id});
        _scheduleRefresh();
        return;
      }

      final newPhase = RoundPhase.values.firstWhere(
        (p) => p.name == phaseStr,
        orElse: () => currentState.currentRound!.phase,
      );
      final phaseChanged = newPhase != currentState.currentRound!.phase;

      if (phaseChanged) {
        // Full refetch so rating_skips, carried-forward propositions,
        // and any other side-effects of the phase transition arrive in
        // one consistent snapshot before the UI reacts.
        _rtRaceLog('round_update.phase_change_refetch',
            roundId: roundId,
            payload: {
              'from': currentState.currentRound!.phase.name,
              'to': newPhase.name,
            });
        _scheduleRefresh();
        return;
      }

      // Non-phase-change UPDATE: patch participation_percent and timer
      // from the realtime payload in place. participation_percent is
      // server-computed by the trigger chain on every prop / skip /
      // affirm / rating event for this round (see migration
      // 20260502170000), so the rounds row itself becomes the single
      // delivery surface for the bar value — even when individual
      // propositions/round_skips events are dropped on this client.
      final newPhaseEndsAt = newRecord['phase_ends_at'] != null
          ? DateTime.parse(newRecord['phase_ends_at'] as String)
          : null;
      final currentTimer = currentState.currentRound!.phaseEndsAt;
      final timerChanged = newPhaseEndsAt?.toUtc() != currentTimer?.toUtc();
      final newParticipation =
          (newRecord['participation_percent'] as num?)?.toInt();
      final participationChanged =
          newParticipation != currentState.currentRound!.participationPercent;
      if (timerChanged || participationChanged) {
        final updatedRound = currentState.currentRound!.copyWith(
          phase: newPhase,
          phaseStartedAt: newRecord['phase_started_at'] != null
              ? DateTime.parse(newRecord['phase_started_at'] as String)
              : null,
          phaseEndsAt: newPhaseEndsAt,
          participationPercent: newParticipation,
        );
        final updatedState = currentState.copyWith(currentRound: updatedRound);
        state = AsyncData(updatedState);
        _cachedState = updatedState;
        _rtRaceSnapshot(
            participationChanged ? 'round_update_participation'
                                 : 'round_update_timer',
            updatedState);
      } else {
        _rtRaceLog('round_update.no_change',
            roundId: roundId);
      }
      return;
    }

    _rtRaceLog('round_${event.name}.fallback_refetch');
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
        _propositionService.getParticipantsWhoSkippedProposing(currentState.currentRound!.id),
      ]);

      final skipCount = results[0] as int;
      final hasSkipped = results[1] as bool;
      final participantsWhoSkippedProposing = results[2] as Set<int>;

      final updatedState = currentState.copyWith(
        skipCount: skipCount,
        hasSkipped: hasSkipped,
        participantsWhoSkippedProposing: participantsWhoSkippedProposing,
      );
      state = AsyncData(updatedState);
      _cachedState = updatedState;
    } catch (e) {
      // Log but don't fail - next event will retry
    }
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
        _propositionService.getParticipantsWhoSkippedRating(currentState.currentRound!.id),
      ]);

      final ratingSkipCount = results[0] as int;
      final hasSkippedRating = results[1] as bool;
      final participantsWhoSkippedRating = results[2] as Set<int>;

      final updatedState = currentState.copyWith(
        ratingSkipCount: ratingSkipCount,
        hasSkippedRating: hasSkippedRating,
        participantsWhoSkippedRating: participantsWhoSkippedRating,
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
          languageCode: contentLanguageCode,
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

    final roundId = currentState!.currentRound!.id;
    await PerfLogger.measure(
      'submit_proposition',
      () async {
        await _propositionService.submitProposition(
          roundId: roundId,
          participantId: currentState.myParticipant!.id,
          content: content,
        );
        // Immediately refresh to show own submission (don't wait for debounced realtime)
        await _refreshPropositions();
      },
      chatId: chatId,
      roundId: roundId,
      payload: {'content_length': content.length},
    );
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
  /// User must not have already rated or already skipped, and skip quota
  /// must not be exceeded. Skippers count toward participation for early
  /// advance calculations. If they had placed any grid rankings the route
  /// goes through skip_rating_with_cleanup so the partial state gets
  /// wiped atomically.
  Future<void> skipRating() async {
    final currentState = state.valueOrNull;
    if (currentState?.currentRound == null ||
        currentState?.myParticipant == null) {
      return;
    }

    final route = decideSkipRatingRoute(currentState!);
    switch (route) {
      case SkipRatingRoute.reject:
        throw Exception('Cannot skip rating: already rated, already skipped, or skip quota exceeded');
      case SkipRatingRoute.cleanup:
        // Manual start/end (instead of measure) so we can thread the
        // correlation_id into the DB function for cross-source ties.
        final cleanupRoundId = currentState.currentRound!.id;
        final cleanupCorr = PerfLogger.start(
          'skip_rating_with_cleanup',
          chatId: chatId,
          roundId: cleanupRoundId,
        );
        try {
          await _propositionService.skipRatingWithCleanup(
            roundId: cleanupRoundId,
            participantId: currentState.myParticipant!.id,
            correlationId: cleanupCorr,
          );
          PerfLogger.end(cleanupCorr,
              action: 'skip_rating_with_cleanup',
              chatId: chatId,
              roundId: cleanupRoundId);
        } catch (e, st) {
          PerfLogger.error(cleanupCorr, e,
              action: 'skip_rating_with_cleanup',
              chatId: chatId,
              roundId: cleanupRoundId,
              stackTrace: st);
          rethrow;
        }
      case SkipRatingRoute.direct:
        await PerfLogger.measure(
          'skip_rating_direct',
          () => _propositionService.skipRating(
            roundId: currentState.currentRound!.id,
            participantId: currentState.myParticipant!.id,
          ),
          chatId: chatId,
          roundId: currentState.currentRound!.id,
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

  /// Force a fresh _loadData(). Called from chat_screen on app resume
  /// (silent) and phase-timer expiry (non-silent). If [silent] is true,
  /// keeps current data visible while fetching (no loading spinner).
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

  /// Realtime UPDATE handler for the `chats` row.
  ///
  /// Strategy:
  /// - Default to merging the payload into the current Chat — operational
  ///   ticks like host_paused, schedule_paused, last_activity_at land
  ///   here and don't justify the bootstrap RPC.
  /// - Schedule a full refetch only if the payload changed a translated
  ///   field source (name / description / initial_message). The Realtime
  ///   payload doesn't carry the translated_* columns; only the bootstrap
  ///   RPC re-derives them via the translations table.
  /// - If we don't have a prior Chat (cold start race), fall back to a
  ///   refresh — there's nothing to merge into.
  void _onChatUpdate(Map<String, dynamic> newRecord) {
    final currentState = state.valueOrNull ?? _cachedState;
    final existingChat = currentState?.chat;
    if (currentState == null || existingChat == null) {
      _scheduleRefresh();
      return;
    }

    if (_payloadTouchesTranslatableFields(existingChat, newRecord)) {
      // Translation source changed — refresh so translated_* fields
      // stay coherent with the new source text.
      _scheduleRefresh();
      return;
    }

    final mergedChat = existingChat.mergeRealtimePayload(newRecord);
    if (mergedChat == existingChat) return; // no-op merge

    final updated = currentState.copyWith(chat: mergedChat);
    state = AsyncData(updated);
    _cachedState = updated;
  }

  /// Translated columns aren't in the Realtime payload (they live in a
  /// separate `translations` table). If the source text moved, the
  /// translated_* fields on local state are stale; trigger a refetch so
  /// the bootstrap RPC re-derives them.
  bool _payloadTouchesTranslatableFields(
    Chat existing,
    Map<String, dynamic> newRecord,
  ) {
    final newName = newRecord['name'];
    if (newName != null && newName != existing.name) return true;
    if (newRecord.containsKey('description') &&
        newRecord['description'] != existing.description) {
      return true;
    }
    if (newRecord.containsKey('initial_message') &&
        newRecord['initial_message'] != existing.initialMessage) {
      return true;
    }
    return false;
  }

  // ===========================================================================
  // Targeted Realtime patching — propositions / skips / rating_skips /
  // affirmations.
  //
  // Before this refactor each subscription handler did a 3-way Future.wait
  // refetch on every event, which is fine at 1 user but at 20 simultaneous
  // raters means 60 round-trips per submit. The patch path collapses the
  // common cases (INSERT, DELETE) into local state mutation; we only fall
  // back to _scheduleRefresh when the payload is missing or we see an
  // event we don't know how to merge cleanly.
  // ===========================================================================

  void _onPropositionRealtime(
    PostgresChangeEvent event,
    Map<String, dynamic>? newRecord,
    Map<String, dynamic>? oldRecord,
  ) {
    final currentState = state.valueOrNull ?? _cachedState;
    final myParticipantId = currentState?.myParticipant?.id;
    if (currentState == null) {
      _scheduleRefresh();
      return;
    }

    if (event == PostgresChangeEvent.delete && oldRecord != null) {
      final deletedId = oldRecord['id'] as int?;
      if (deletedId == null) {
        _scheduleRefresh();
        return;
      }
      final newProps = currentState.propositions
          .where((p) => p.id != deletedId)
          .toList(growable: false);
      final newMine = currentState.myPropositions
          .where((p) => p.id != deletedId)
          .toList(growable: false);
      final updated = currentState.copyWith(
        propositions: newProps,
        myPropositions: newMine,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      return;
    }

    if (newRecord == null) {
      _scheduleRefresh();
      return;
    }

    final Proposition incoming;
    try {
      incoming = Proposition.fromJson(newRecord);
    } catch (_) {
      // Malformed payload — fall back to refresh rather than corrupt state.
      _scheduleRefresh();
      return;
    }

    // Translated content lives in a separate table; the propositions
    // payload doesn't include it. If the user picked a content language
    // for this chat, schedule a refresh so the bootstrap RPC can attach
    // translations onto the freshly merged proposition.
    final needsTranslations = currentState.viewingLanguageCode != null;

    _rtRaceLog('prop_${event.name}',
        roundId: incoming.roundId,
        payload: {'prop_id': incoming.id,
                  'participant_id': incoming.participantId,
                  'carried': incoming.carriedFromId != null});

    if (event == PostgresChangeEvent.insert) {
      // Append, dedup by id (Realtime can deliver duplicates on resubscribe).
      final existing = currentState.propositions;
      if (existing.any((p) => p.id == incoming.id)) {
        _rtRaceLog('prop_insert.dedup', roundId: incoming.roundId,
            payload: {'prop_id': incoming.id});
        return; // already known, no-op
      }
      final newProps = [...existing, incoming];
      final newMine = (incoming.participantId != null &&
              incoming.participantId == myParticipantId)
          ? [...currentState.myPropositions, incoming]
          : currentState.myPropositions;
      // Patch the proposing-phase "Done" set in place for a NEW (non-carried)
      // proposition. Trivially safe — just adds the author's id. The Done tag
      // also self-corrects on the next bootstrap refresh during proposing.
      final newProposers = (incoming.carriedFromId == null &&
              incoming.participantId != null)
          ? {...currentState.participantsWhoProposed, incoming.participantId!}
          : currentState.participantsWhoProposed;
      final updated = currentState.copyWith(
        propositions: newProps,
        myPropositions: newMine,
        participantsWhoProposed: newProposers,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      _rtRaceSnapshot('prop_insert', updated);
      if (needsTranslations) _scheduleRefresh();
      return;
    }

    if (event == PostgresChangeEvent.update) {
      final newProps = currentState.propositions
          .map((p) => p.id == incoming.id ? incoming : p)
          .toList(growable: false);
      final newMine = currentState.myPropositions
          .map((p) => p.id == incoming.id ? incoming : p)
          .toList(growable: false);
      final updated = currentState.copyWith(
        propositions: newProps,
        myPropositions: newMine,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      _rtRaceSnapshot('prop_update', updated);
      if (needsTranslations) _scheduleRefresh();
      return;
    }

    // Unknown event — be safe.
    _rtRaceLog('prop_${event.name}.fallback_refetch');
    _scheduleRefresh();
  }

  void _onRoundSkipRealtime(
    PostgresChangeEvent event,
    Map<String, dynamic>? newRecord,
    Map<String, dynamic>? oldRecord,
  ) {
    final currentState = state.valueOrNull ?? _cachedState;
    final myParticipantId = currentState?.myParticipant?.id;
    if (currentState == null) {
      _scheduleRefresh();
      return;
    }

    final record = newRecord ?? oldRecord;
    final participantId = (record?['participant_id'] as int?);
    if (participantId == null) {
      _scheduleRefresh();
      return;
    }

    final mine = participantId == myParticipantId;
    _rtRaceLog('round_skip_${event.name}',
        payload: {'pid': participantId, 'mine': mine});

    if (event == PostgresChangeEvent.insert) {
      final newSet = {...currentState.participantsWhoSkippedProposing,
        participantId};
      final updated = currentState.copyWith(
        skipCount: currentState.skipCount + 1,
        hasSkipped: mine ? true : currentState.hasSkipped,
        participantsWhoSkippedProposing: newSet,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      _rtRaceSnapshot('round_skip_insert', updated);
      return;
    }

    if (event == PostgresChangeEvent.delete) {
      final newSet =
          {...currentState.participantsWhoSkippedProposing}..remove(participantId);
      final updated = currentState.copyWith(
        skipCount: (currentState.skipCount - 1).clamp(0, 1 << 30),
        hasSkipped: mine ? false : currentState.hasSkipped,
        participantsWhoSkippedProposing: newSet,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      _rtRaceSnapshot('round_skip_delete', updated);
      return;
    }

    _rtRaceLog('round_skip_${event.name}.fallback_refetch');
    _scheduleRefresh();
  }

  void _onRatingSkipRealtime(
    PostgresChangeEvent event,
    Map<String, dynamic>? newRecord,
    Map<String, dynamic>? oldRecord,
  ) {
    final currentState = state.valueOrNull ?? _cachedState;
    final myParticipantId = currentState?.myParticipant?.id;
    if (currentState == null) {
      _scheduleRefresh();
      return;
    }

    final record = newRecord ?? oldRecord;
    final participantId = record?['participant_id'] as int?;
    if (participantId == null) {
      _scheduleRefresh();
      return;
    }

    final mine = participantId == myParticipantId;
    _rtRaceLog('rating_skip_${event.name}',
        payload: {'pid': participantId, 'mine': mine});

    if (event == PostgresChangeEvent.insert) {
      final newSet = {...currentState.participantsWhoSkippedRating,
        participantId};
      final updated = currentState.copyWith(
        ratingSkipCount: currentState.ratingSkipCount + 1,
        hasSkippedRating: mine ? true : currentState.hasSkippedRating,
        participantsWhoSkippedRating: newSet,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      _rtRaceSnapshot('rating_skip_insert', updated);
      return;
    }

    if (event == PostgresChangeEvent.delete) {
      final newSet =
          {...currentState.participantsWhoSkippedRating}..remove(participantId);
      final updated = currentState.copyWith(
        ratingSkipCount: (currentState.ratingSkipCount - 1).clamp(0, 1 << 30),
        hasSkippedRating: mine ? false : currentState.hasSkippedRating,
        participantsWhoSkippedRating: newSet,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      _rtRaceSnapshot('rating_skip_delete', updated);
      return;
    }

    _rtRaceLog('rating_skip_${event.name}.fallback_refetch');
    _scheduleRefresh();
  }

  /// A rater finished (or un-finished) rating this round: patch
  /// participantsWhoRated in place. Fires at most once per rater per round,
  /// so this stays cheap at any viewer count. Matches mode additionally
  /// refreshes the done/eligible counts that drive the round-status bar
  /// (kept as the authoritative RPC rather than derived incrementally).
  void _onRatingCompletionRealtime(
    PostgresChangeEvent event,
    Map<String, dynamic>? newRecord,
    Map<String, dynamic>? oldRecord,
  ) {
    final currentState = state.valueOrNull ?? _cachedState;
    if (currentState == null) {
      _scheduleRefresh();
      return;
    }

    final record = newRecord ?? oldRecord;
    final roundId = record?['round_id'] as int?;
    if (roundId != null && roundId != currentState.currentRound?.id) {
      // Stale event from a previous round's channel — ignore.
      return;
    }

    // Anonymous session raters (session_token, no participant row) aren't in
    // the roster, so they can't carry a Done tag — nothing to patch.
    final participantId = record?['participant_id'] as int?;
    if (participantId != null) {
      _rtRaceLog('rating_completion_${event.name}',
          payload: {'pid': participantId});

      if (event == PostgresChangeEvent.insert) {
        final updated = currentState.copyWith(
          participantsWhoRated: {
            ...currentState.participantsWhoRated,
            participantId,
          },
        );
        state = AsyncData(updated);
        _cachedState = updated;
        _rtRaceSnapshot('rating_completion_insert', updated);
      } else if (event == PostgresChangeEvent.delete) {
        final updated = currentState.copyWith(
          participantsWhoRated: {...currentState.participantsWhoRated}
            ..remove(participantId),
        );
        state = AsyncData(updated);
        _cachedState = updated;
        _rtRaceSnapshot('rating_completion_delete', updated);
      }
    }

    if (currentState.chat?.ratingMode == 'matches' &&
        currentState.currentRound != null) {
      _refreshMatchesProgress(currentState.currentRound!.id);
    }
  }

  void _onAffirmationRealtime(
    PostgresChangeEvent event,
    Map<String, dynamic>? newRecord,
    Map<String, dynamic>? oldRecord,
  ) {
    final currentState = state.valueOrNull ?? _cachedState;
    final myParticipantId = currentState?.myParticipant?.id;
    if (currentState == null) {
      _scheduleRefresh();
      return;
    }

    final record = newRecord ?? oldRecord;
    final participantId = record?['participant_id'] as int?;
    if (participantId == null) {
      _scheduleRefresh();
      return;
    }

    final mine = participantId == myParticipantId;
    _rtRaceLog('affirm_${event.name}',
        payload: {'pid': participantId, 'mine': mine});

    if (event == PostgresChangeEvent.insert) {
      final newSet = {...currentState.participantsWhoAffirmed, participantId};
      final updated = currentState.copyWith(
        affirmationCount: currentState.affirmationCount + 1,
        hasAffirmed: mine ? true : currentState.hasAffirmed,
        participantsWhoAffirmed: newSet,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      _rtRaceSnapshot('affirm_insert', updated);
      return;
    }

    if (event == PostgresChangeEvent.delete) {
      final newSet =
          {...currentState.participantsWhoAffirmed}..remove(participantId);
      final updated = currentState.copyWith(
        affirmationCount:
            (currentState.affirmationCount - 1).clamp(0, 1 << 30),
        hasAffirmed: mine ? false : currentState.hasAffirmed,
        participantsWhoAffirmed: newSet,
      );
      state = AsyncData(updated);
      _cachedState = updated;
      return;
    }

    _scheduleRefresh();
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

    // Find the request being approved so we can build an optimistic participant
    final request = currentState.pendingJoinRequests
        .cast<Map<String, dynamic>?>()
        .firstWhere((r) => r?['id'] == requestId, orElse: () => null);

    // Optimistic update: remove request + add participant
    final updatedRequests = currentState.pendingJoinRequests
        .where((r) => r['id'] != requestId)
        .toList();

    var updatedParticipants = currentState.participants;
    if (request != null) {
      updatedParticipants = [
        ...currentState.participants,
        Participant(
          id: -1, // Temporary; next refresh will reconcile
          chatId: chatId,
          userId: request['user_id'] as String?,
          displayName: request['display_name'] as String? ?? '',
          isHost: false,
          isAuthenticated: request['is_authenticated'] as bool? ?? true,
          status: ParticipantStatus.active,
          createdAt: DateTime.now(),
        ),
      ];
    }

    state = AsyncData(currentState.copyWith(
      pendingJoinRequests: updatedRequests,
      participants: updatedParticipants,
    ));

    try {
      await _participantService.approveRequest(requestId);
      // Schedule a refresh to reconcile with server state
      _scheduleRefresh();
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

    final perfCorr =
        PerfLogger.start('host_resume_chat', chatId: chatId);
    try {
      // Pass the same correlation_id to the DB function so its start/end
      // log_perf rows share the ID with the Flutter-side ones.
      await _chatService.hostResumeChat(chatId, correlationId: perfCorr);
      PerfLogger.end(perfCorr,
          action: 'host_resume_chat', chatId: chatId);
      // Realtime will update state automatically
    } catch (e, st) {
      PerfLogger.error(perfCorr, e,
          action: 'host_resume_chat',
          chatId: chatId,
          stackTrace: st);
      // Re-fetch to ensure UI is in sync
      await refresh();
      rethrow;
    }
  }
}
