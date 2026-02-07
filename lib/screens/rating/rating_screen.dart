import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/round.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../../widgets/rating/rating_widget.dart';

/// Provider for grid ranking state - family provider keyed by params
final ratingProvider = AsyncNotifierProvider.autoDispose
    .family<RatingNotifier, RatingState, GridRankingParams>(
  RatingNotifier.new,
);

class RatingScreen extends ConsumerStatefulWidget {
  final int roundId;
  final int participantId;
  final int chatId;
  final bool showPreviousResults;

  const RatingScreen({
    super.key,
    required this.roundId,
    required this.participantId,
    required this.chatId,
    this.showPreviousResults = false,
  });

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  /// Key to access the widget state for adding propositions
  final GlobalKey<RatingWidgetState> _widgetKey = GlobalKey();

  /// Track if we've already popped to prevent double-pop
  bool _hasPopped = false;

  /// Track if we've ever seen the rating phase - prevents popping on stale initial data
  bool _hasSeenRatingPhase = false;

  GridRankingParams get _params => GridRankingParams(
        roundId: widget.roundId,
        participantId: widget.participantId,
      );

  ChatDetailParams get _chatParams => ChatDetailParams(
        chatId: widget.chatId,
        showPreviousResults: widget.showPreviousResults,
      );

  /// Called when a placement is confirmed - fetch the next proposition
  Future<void> _onPlacementConfirmed() async {
    final notifier = ref.read(ratingProvider(_params).notifier);
    final nextProposition = await notifier.fetchNextProposition();

    if (nextProposition != null) {
      _widgetKey.currentState?.addProposition({
        'id': nextProposition.id,
        'content': nextProposition.displayContent, // Use translated content
      });
    } else {
      _widgetKey.currentState?.setNoMorePropositions();
    }
  }

  Future<void> _handleRankingComplete(Map<String, double> rankings) async {
    final notifier = ref.read(ratingProvider(_params).notifier);
    final success = await notifier.submitRankings(rankings);

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      if (success) {
        // Log analytics event
        final chatState = ref.read(chatDetailProvider(_chatParams)).valueOrNull;
        ref.read(analyticsServiceProvider).logRatingCompleted(
          chatId: widget.chatId.toString(),
          roundNumber: chatState?.currentRound?.customId ?? 1,
          propositionsRated: rankings.length,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.rankedSuccessfully(rankings.length)),
            backgroundColor: Colors.green,
          ),
        );
        _hasPopped = true; // Prevent double-pop from phase change detection
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToSaveRankings),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateAsync = ref.watch(ratingProvider(_params));

    // Watch chat state for pause and phase changes
    final chatStateAsync = ref.watch(chatDetailProvider(_chatParams));
    final isPaused = chatStateAsync.valueOrNull?.chat?.isPaused ?? false;
    final currentPhase = chatStateAsync.valueOrNull?.currentRound?.phase;

    // Pop back to chat screen if paused
    if (isPaused && !_hasPopped) {
      _hasPopped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.chatPausedByHost)),
          );
          Navigator.of(context).pop(false);
        }
      });
    }

    // Pop back to chat screen if rating phase has ended
    // currentPhase will be null initially, so only pop if it's explicitly not rating
    // IMPORTANT: Only pop if we've already seen the rating phase at least once.
    // This prevents popping due to stale/race condition data during initial load.
    final stateRoundId = chatStateAsync.valueOrNull?.currentRound?.id;
    final roundMatches = stateRoundId == null || stateRoundId == widget.roundId;

    // Track if we've seen rating phase
    if (currentPhase == RoundPhase.rating && roundMatches) {
      _hasSeenRatingPhase = true;
    }

    // Only pop if: we've seen rating phase, phase is now NOT rating, round matches, haven't popped yet
    if (_hasSeenRatingPhase && currentPhase != null && currentPhase != RoundPhase.rating && roundMatches && !_hasPopped) {
      _hasPopped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.ratingPhaseEnded)),
          );
          Navigator.of(context).pop(false);
        }
      });
    }

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: stateAsync.when(
          data: (state) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.rankPropositions,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.placing,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    '${state.currentPlacing}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    ' / ${state.totalKnown}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (state.isFetchingNext)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          loading: () => Text(
            l10n.rankPropositions,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          error: (_, _) => Text(
            l10n.rankPropositions,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: stateAsync.when(
          data: (state) => RatingWidget(
            key: _widgetKey,
            propositions: state.propositions,
            onRankingComplete: _handleRankingComplete,
            onPlacementConfirmed: _onPlacementConfirmed,
            onUndo: (removedId) {
              // Remove from fetchedIds so it can be re-fetched
              ref.read(ratingProvider(_params).notifier)
                  .removeFromFetched(int.parse(removedId));
            },
            onSaveRankings: (rankings, allPositionsChanged) {
              // Save rankings to database after each placement
              ref.read(ratingProvider(_params).notifier)
                  .saveIntermediateRankings(rankings, allPositionsChanged: allPositionsChanged);
            },
            lazyLoadingMode: true,
            isResuming: state.isResuming,
            onCounterUpdate: (current, total) {
              ref.read(ratingProvider(_params).notifier).updatePlacing(current, total);
            },
          ),
          loading: () => Center(
            child: CircularProgressIndicator(
              color: theme.colorScheme.primary,
            ),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    error.toString(),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.goBack),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
