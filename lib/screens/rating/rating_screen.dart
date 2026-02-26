import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/error_view.dart';
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

  /// Track if skip is in progress
  bool _isSkipping = false;

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

  Future<void> _handleSkipRating() async {
    if (_isSkipping) return;
    setState(() => _isSkipping = true);

    try {
      final notifier = ref.read(chatDetailProvider(_chatParams).notifier);
      await notifier.skipRating();

      if (mounted) {
        _hasPopped = true;
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        context.showErrorMessage(l10n.failedToSubmit(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isSkipping = false);
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

        context.showSuccessSnackBar(l10n.rankedSuccessfully(rankings.length));
        _hasPopped = true; // Prevent double-pop from phase change detection
        Navigator.of(context).pop(true);
      } else {
        context.showErrorMessage(l10n.failedToSaveRankings);
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
    final canSkipRating = chatStateAsync.valueOrNull?.canSkipRating ?? false;

    // Pop back to chat screen if paused
    if (isPaused && !_hasPopped) {
      _hasPopped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          context.showInfoSnackBar(l10n.chatPausedByHost);
          Navigator.of(context).pop(false);
        }
      });
    }

    // Pop back to chat screen if this round completed (new round started).
    // We detect this by checking if stateRoundId changed to a different round.
    // DO NOT pop based on phase changes within the same round — Realtime events
    // can arrive out of order (e.g. INSERT with phase=proposing arrives after
    // UPDATE with phase=rating), causing a brief phase flicker that triggers
    // a false pop.
    final stateRoundId = chatStateAsync.valueOrNull?.currentRound?.id;

    // Track if we've seen rating phase (for this round)
    if (currentPhase == RoundPhase.rating && stateRoundId == widget.roundId) {
      _hasSeenRatingPhase = true;
    }

    // Pop when: we've seen rating phase AND round changed (our round completed)
    final roundChanged = stateRoundId != null && stateRoundId != widget.roundId;
    final cycleEnded = _hasSeenRatingPhase && stateRoundId == null && currentPhase == null;

    if (_hasSeenRatingPhase && (roundChanged || cycleEnded) && !_hasPopped) {
      _hasPopped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          context.showInfoSnackBar(l10n.ratingPhaseEnded);
          Navigator.of(context).pop(false);
        }
      });
    }

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
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
        actions: [
          if (canSkipRating)
            TextButton(
              onPressed: _isSkipping ? null : _handleSkipRating,
              child: _isSkipping
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : Text(l10n.skip),
            ),
        ],
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
          error: (error, _) => ErrorView(
            message: error.toString(),
            onRetry: () => Navigator.of(context).pop(),
            actionLabel: l10n.goBack,
            actionIcon: Icons.arrow_back,
          ),
        ),
      ),
    );
  }
}
