import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/locale_provider.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/proposition_service.dart';

/// State for grid ranking screen
class RatingState extends Equatable {
  final List<Map<String, dynamic>> propositions;
  final Set<int> fetchedIds;
  final int totalKnown;
  final int currentPlacing;
  final bool isFetchingNext;
  final bool isComplete;
  /// True if resuming from saved rankings (propositions include 'position' field)
  final bool isResuming;

  const RatingState({
    this.propositions = const [],
    this.fetchedIds = const {},
    this.totalKnown = 0,
    this.currentPlacing = 0,
    this.isFetchingNext = false,
    this.isComplete = false,
    this.isResuming = false,
  });

  RatingState copyWith({
    List<Map<String, dynamic>>? propositions,
    Set<int>? fetchedIds,
    int? totalKnown,
    int? currentPlacing,
    bool? isFetchingNext,
    bool? isComplete,
    bool? isResuming,
  }) {
    return RatingState(
      propositions: propositions ?? this.propositions,
      fetchedIds: fetchedIds ?? this.fetchedIds,
      totalKnown: totalKnown ?? this.totalKnown,
      currentPlacing: currentPlacing ?? this.currentPlacing,
      isFetchingNext: isFetchingNext ?? this.isFetchingNext,
      isComplete: isComplete ?? this.isComplete,
      isResuming: isResuming ?? this.isResuming,
    );
  }

  @override
  List<Object?> get props => [
        propositions,
        fetchedIds,
        totalKnown,
        currentPlacing,
        isFetchingNext,
        isComplete,
        isResuming,
      ];
}

/// Parameters for creating a RatingNotifier
class GridRankingParams extends Equatable {
  final int roundId;
  final int participantId;

  const GridRankingParams({
    required this.roundId,
    required this.participantId,
  });

  @override
  List<Object?> get props => [roundId, participantId];
}

/// Notifier for managing grid ranking state using AsyncNotifier pattern
class RatingNotifier extends AutoDisposeFamilyAsyncNotifier<RatingState, GridRankingParams> {
  late PropositionService _propositionService;
  late int _roundId;
  late int _participantId;
  late String _languageCode;

  @override
  Future<RatingState> build(GridRankingParams arg) async {
    _roundId = arg.roundId;
    _participantId = arg.participantId;

    // Get the proposition service (auth is automatic via JWT)
    _propositionService = ref.watch(propositionServiceProvider);

    // Get the user's language preference
    _languageCode = ref.watch(localeProvider).languageCode;

    // Load initial propositions
    return _loadInitialPropositions();
  }

  /// Load initial propositions - checks for saved rankings first
  Future<RatingState> _loadInitialPropositions() async {
    // First check if user has existing rankings (resume from saved)
    final existingRankings = await _propositionService.getExistingGridRankings(
      roundId: _roundId,
      participantId: _participantId,
      languageCode: _languageCode,
    );

    if (existingRankings.isNotEmpty) {
      return _resumeFromSavedRankings(existingRankings);
    }

    // No existing rankings - start fresh with binary comparison
    return _loadFreshPropositions();
  }

  /// Resume from saved rankings
  Future<RatingState> _resumeFromSavedRankings(
    List<Map<String, dynamic>> savedRankings,
  ) async {
    // Track fetched IDs from saved rankings
    final fetchedIds = <int>{};
    for (final r in savedRankings) {
      fetchedIds.add(r['id'] as int);
    }

    // Check if there are more propositions to load
    final remainingCount = await _propositionService.getRemainingPropositionCount(
      roundId: _roundId,
      participantId: _participantId,
      excludeIds: fetchedIds.toList(),
    );

    // If all propositions are ranked, mark as complete
    final isComplete = remainingCount == 0;

    return RatingState(
      propositions: savedRankings,
      fetchedIds: fetchedIds,
      totalKnown: savedRankings.length + remainingCount,
      currentPlacing: savedRankings.length,
      isComplete: isComplete,
      isResuming: true,
    );
  }

  /// Load fresh propositions for binary comparison (no saved state)
  Future<RatingState> _loadFreshPropositions() async {
    final propositions = await _propositionService.getInitialPropositionsForGridRanking(
      roundId: _roundId,
      participantId: _participantId,
      languageCode: _languageCode,
    );

    if (propositions.length < 2) {
      throw Exception('Not enough propositions to rank (need at least 2)');
    }

    // Track fetched IDs
    final fetchedIds = <int>{};
    for (final p in propositions) {
      fetchedIds.add(p.id);
    }

    // Check if there are more propositions to load
    final remainingCount = await _propositionService.getRemainingPropositionCount(
      roundId: _roundId,
      participantId: _participantId,
      excludeIds: fetchedIds.toList(),
    );

    return RatingState(
      propositions: propositions
          .map((p) => {
                'id': p.id,
                'content': p.displayContent,
              })
          .toList(),
      fetchedIds: fetchedIds,
      totalKnown: propositions.length + remainingCount,
      isResuming: false,
    );
  }

  /// Fetch the next proposition for ranking
  Future<Proposition?> fetchNextProposition() async {
    final currentState = state.valueOrNull;
    if (currentState == null || currentState.isFetchingNext) return null;

    state = AsyncData(currentState.copyWith(isFetchingNext: true));

    try {
      final nextProposition = await _propositionService.getNextPropositionForGridRanking(
        roundId: _roundId,
        participantId: _participantId,
        excludeIds: currentState.fetchedIds.toList(),
        languageCode: _languageCode,
      );

      if (nextProposition != null) {
        final newFetchedIds = {...currentState.fetchedIds, nextProposition.id};
        state = AsyncData(currentState.copyWith(
          fetchedIds: newFetchedIds,
          isFetchingNext: false,
        ));
        return nextProposition;
      } else {
        state = AsyncData(currentState.copyWith(
          isFetchingNext: false,
          isComplete: true,
        ));
        return null;
      }
    } catch (e) {
      state = AsyncData(currentState.copyWith(
        isFetchingNext: false,
        isComplete: true,
      ));
      return null;
    }
  }

  /// Update the current placing counter
  void updatePlacing(int current, int total) {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncData(currentState.copyWith(
      currentPlacing: current,
      totalKnown: total > currentState.totalKnown ? total : currentState.totalKnown,
    ));
  }

  /// Submit final rankings
  Future<bool> submitRankings(Map<String, double> rankings) async {
    try {
      await _propositionService.submitGridRankings(
        roundId: _roundId,
        rankings: rankings,
        participantId: _participantId,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Remove a proposition ID from fetchedIds (called after undo)
  void removeFromFetched(int propositionId) {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    final newFetchedIds = {...currentState.fetchedIds};
    newFetchedIds.remove(propositionId);

    state = AsyncData(currentState.copyWith(
      fetchedIds: newFetchedIds,
      isComplete: false, // May have more to fetch now
    ));
  }

  /// Save intermediate rankings (called after each placement)
  /// If allPositionsChanged is true, updates all rankings; otherwise just upserts
  Future<void> saveIntermediateRankings(
    Map<String, double> rankings, {
    required bool allPositionsChanged,
  }) async {
    if (rankings.isEmpty) return;

    try {
      await _propositionService.submitGridRankings(
        roundId: _roundId,
        rankings: rankings,
        participantId: _participantId,
      );
    } catch (e) {
      // Don't throw - we don't want to interrupt the user's flow
      // The final submit will retry anyway
    }
  }
}
