import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env_config.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../widgets/qr_code_share.dart';
import '../../widgets/rating/rating_model.dart';
import '../../widgets/rating/rating_widget.dart';
import '../chat/widgets/phase_panels.dart';
import '../chat/widgets/previous_round_display.dart';
import 'models/tutorial_state.dart';
import 'notifiers/tutorial_notifier.dart';
import 'tutorial_data.dart';
import 'widgets/tutorial_intro_panel.dart';
import 'widgets/tutorial_progress_dots.dart';
import 'widgets/tutorial_template_panel.dart';

/// Provider for tutorial chat state (new version using real ChatScreen layout)
/// Uses autoDispose so state resets when tutorial screen is closed
final tutorialChatNotifierProvider = StateNotifierProvider.autoDispose<
    TutorialChatNotifier, TutorialChatState>((ref) {
  return TutorialChatNotifier();
});

/// Legacy provider for backwards compatibility with existing tests
final tutorialNotifierProvider =
    StateNotifierProvider<TutorialNotifier, TutorialState>((ref) {
  return TutorialNotifier();
});

/// Tutorial screen that mirrors the real ChatScreen layout
class TutorialScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;

  const TutorialScreen({
    super.key,
    this.onComplete,
  });

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _propositionController = TextEditingController();

  // UI toggle state (same as ChatScreen)
  bool _showPreviousWinner = false;
  int _currentWinnerIndex = 0;
  int? _lastWinnerRoundId;

  // Tutorial-specific: track if user has clicked Continue to unlock phase tab
  bool _phaseTabUnlocked = false;

  // Track if tutorial completion is in progress (show loading, block back)
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _propositionController.dispose();
    super.dispose();
  }

  void _handleSkip() {
    _showSkipConfirmation();
  }

  Future<void> _showSkipConfirmation() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tutorialSkipConfirmTitle),
        content: Text(l10n.tutorialSkipConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.tutorialSkipConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.tutorialSkipConfirmYes),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _handleComplete();
    }
  }

  void _handleComplete() {
    if (_isCompleting) return;
    _isCompleting = true;
    if (mounted) setState(() {});

    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showDemoQrCode() {
    final state = ref.read(tutorialChatNotifierProvider);
    final chatName = state.selectedTemplate != null
        ? TutorialData.chatNameForTemplate(state.selectedTemplate)
        : TutorialData.chatName;
    QrCodeShareDialog.show(
      context,
      chatName: chatName,
      inviteCode: TutorialData.demoInviteCode,
      // Tutorial code URL redirects to tutorial via router
      deepLinkUrl: '${EnvConfig.webAppUrl}/join/${TutorialData.demoInviteCode}',
      // Show prominent Continue button to make it clear users need to tap to proceed
      showContinueButton: true,
    ).then((_) {
      // After dialog is closed, complete the tutorial
      if (mounted) _handleComplete();
    });
  }

  void _submitProposition() {
    final content = _propositionController.text.trim();
    if (content.isEmpty) return;

    final state = ref.read(tutorialChatNotifierProvider);
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);
    final l10n = AppLocalizations.of(context);

    // Check for duplicates - get existing propositions for current round
    final existingProps = _getExistingPropositionsForRound(state, l10n);
    final normalizedContent = content.toLowerCase().trim();

    final isDuplicate = existingProps.any(
      (prop) => prop.toLowerCase().trim() == normalizedContent,
    );

    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tutorialDuplicateProposition),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (state.currentStep == TutorialStep.round1Proposing) {
      notifier.submitRound1Proposition(content);
    } else if (state.currentStep == TutorialStep.round2Proposing ||
               state.currentStep == TutorialStep.round2Prompt) {
      // Note: round2Prompt is the step after Continue from round 1 result
      // Both round2Prompt and round2Proposing show the proposing panel
      notifier.submitRound2Proposition(content);
    } else if (state.currentStep == TutorialStep.round3Proposing) {
      notifier.submitRound3Proposition(content);
    }

    _propositionController.clear();
  }

  /// Translate proposition content from English key to localized string.
  /// Covers all template propositions; user-submitted text passes through unchanged.
  String _translateProposition(String englishContent, AppLocalizations l10n) {
    return TutorialTemplate.translateProp(englishContent, l10n);
  }

  /// Get existing propositions for current round (for duplicate detection)
  List<String> _getExistingPropositionsForRound(TutorialChatState state, AppLocalizations l10n) {
    final templateKey = state.selectedTemplate;
    if (state.currentStep == TutorialStep.round1Proposing) {
      return TutorialData.round1Props(templateKey);
    } else if (state.currentStep == TutorialStep.round2Proposing ||
               state.currentStep == TutorialStep.round2Prompt) {
      return TutorialData.round2Props(templateKey);
    } else if (state.currentStep == TutorialStep.round3Proposing) {
      // Include the user's carried forward proposition
      final carried = state.userProposition2 ?? '';
      return [carried, ...TutorialData.round3Props(templateKey)];
    }
    return [];
  }

  void _openTutorialRatingScreen(TutorialChatState state) {
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);
    final l10n = AppLocalizations.of(context);
    notifier.markRatingStarted();

    // Filter out user's own propositions - users can't rate their own
    final userParticipantId = state.myParticipant.id;
    final propositionsToRate = state.propositions
        .where((p) => p.participantId != userParticipantId)
        .toList();

    // Translate proposition content to current locale
    final translatedPropositions = propositionsToRate.map((p) => Proposition(
      id: p.id,
      roundId: p.roundId,
      participantId: p.participantId,
      content: _translateProposition(p.content, l10n),
      carriedFromId: p.carriedFromId,
      createdAt: p.createdAt,
    )).toList();

    // Navigate to rating screen
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _TutorialRatingScreen(
          propositions: translatedPropositions,
          showHints: state.currentStep == TutorialStep.round1Rating,
          onComplete: () {
            // Complete the rating based on current step
            final currentState = ref.read(tutorialChatNotifierProvider);
            if (currentState.currentStep == TutorialStep.round1Rating) {
              notifier.completeRound1Rating();
            } else if (currentState.currentStep == TutorialStep.round2Rating) {
              notifier.completeRound2Rating();
            } else if (currentState.currentStep == TutorialStep.round3Rating) {
              notifier.completeRound3Rating();
            }
            Navigator.pop(context, true);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tutorialChatNotifierProvider);
    // Watch locale to rebuild when language changes
    ref.watch(localeProvider);

    // Show blank screen while tutorial completion is in progress.
    // This is only visible briefly (~300ms) before GoRouter navigates to Home.
    // Using PopScope to prevent back navigation during completion.
    if (_isCompleting) {
      return const PopScope(
        canPop: false,
        child: Scaffold(
          body: SizedBox.shrink(),
        ),
      );
    }

    // Auto-switch to Previous Winner tab when new winners arrive
    if (state.previousRoundWinners.isNotEmpty) {
      final currentRoundId = state.previousRoundWinners.first.roundId;
      if (_lastWinnerRoundId != currentRoundId) {
        _lastWinnerRoundId = currentRoundId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showPreviousWinner) {
            setState(() => _showPreviousWinner = true);
          }
        });
      }
    }

    // Check if we should show tutorial-specific panels
    final showTutorialPanel = _shouldShowTutorialPanel(state.currentStep);

    // Show share button only at shareDemo step
    final showShareButton = state.currentStep == TutorialStep.shareDemo;

    return Scaffold(
      // Hide app bar on intro and template selection - panels have their own navigation
      appBar: (state.currentStep == TutorialStep.intro ||
              state.currentStep == TutorialStep.templateSelection)
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              actions: [
                // Share button - only shown at shareDemo step
                if (showShareButton)
                  Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context);
                      return IconButton(
                        key: const Key('tutorial-share-button'),
                        icon: const Icon(Icons.ios_share),
                        tooltip: l10n.tutorialShareTooltip,
                        onPressed: _showDemoQrCode,
                      );
                    },
                  ),
                // 3-dot menu with Skip option
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'skip') {
                      _handleSkip();
                    }
                  },
                  itemBuilder: (context) {
                    final l10n = AppLocalizations.of(context);
                    return [
                      PopupMenuItem<String>(
                        value: 'skip',
                        child: Text(l10n.tutorialSkipMenuItem),
                      ),
                    ];
                  },
                ),
              ],
            ),
      body: (state.currentStep == TutorialStep.intro ||
              state.currentStep == TutorialStep.templateSelection)
          // Intro/Template Selection: full screen with SafeArea, no app bar
          ? SafeArea(
              child: _buildTutorialPanel(state),
            )
          // After template selection: Column with progress dots, chat history, bottom area
          : Column(
              children: [
                // Progress dots (not shown on complete)
                if (state.currentStep != TutorialStep.complete)
                  TutorialProgressDots(currentStep: state.currentStep),

                // Chat History (initial message + educational messages + consensus items)
                Expanded(
                  child: Builder(
                    builder: (bodyContext) {
                      final l10n = AppLocalizations.of(bodyContext);
                      // Use template-specific question (translated), or localized default
                      final templateKey = state.selectedTemplate;
                      final initialMessage = state.customQuestion ??
                          TutorialTemplate.translateQuestion(templateKey, l10n);

                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Initial Message (the tutorial question)
                          _buildMessageCard(
                            l10n.initialMessage,
                            initialMessage,
                            isPrimary: true,
                          ),
                          const SizedBox(height: 16),

                          // Consensus Items
                          ...state.consensusItems.asMap().entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildMessageCard(
                                l10n.consensusNumber(entry.key + 1),
                                entry.value.displayContent,
                                isPrimary: true,
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),

                // Bottom Area - tutorial panel or chat-like bottom area
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: SingleChildScrollView(
                      child: showTutorialPanel
                          ? _buildTutorialPanel(state)
                          : _buildChatBottomArea(state),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Determine if we should show a tutorial-specific panel (not chat-like)
  bool _shouldShowTutorialPanel(TutorialStep step) {
    // Intro, template selection, consensus, and shareDemo use tutorial panels (no tabbar)
    return step == TutorialStep.intro ||
        step == TutorialStep.templateSelection ||
        step == TutorialStep.round3Consensus ||
        step == TutorialStep.shareDemo ||
        step == TutorialStep.complete;
  }

  /// Check if current step is a result step (shows tabs + message + continue)
  bool _isResultStep(TutorialStep step) {
    return step == TutorialStep.round1Result ||
        step == TutorialStep.round1SeeResults ||
        step == TutorialStep.round2Result;
  }

  /// Check if current step is an educational step (prompt)
  /// where the phase tab is locked until Continue is clicked
  bool _isEducationalStep(TutorialStep step) {
    return step == TutorialStep.round2Prompt;
  }

  Widget _buildMessageCard(String label, String content,
      {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPrimary
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: isPrimary
            ? Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 4,
                ),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(content),
        ],
      ),
    );
  }

  /// Build an educational hint banner for the tutorial
  Widget _buildEducationalHint(String text, {IconData icon = Icons.lightbulb_outline}) {
    final theme = Theme.of(context);
    // Use a soft blue/primary tint for tutorial hints (not tertiary which can look red)
    final backgroundColor = theme.colorScheme.primaryContainer.withAlpha(100);
    final borderColor = theme.colorScheme.primary.withAlpha(80);
    final contentColor = theme.colorScheme.onPrimaryContainer;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: contentColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: contentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the chat-like bottom area (tabs + phase panels)
  Widget _buildChatBottomArea(TutorialChatState state) {
    final l10n = AppLocalizations.of(context);
    final hasPreviousWinner = state.previousRoundWinners.isNotEmpty;
    final isRatingPhase = state.currentRound?.phase == RoundPhase.rating;
    final isResultStep = _isResultStep(state.currentStep);
    final isEducationalStep = _isEducationalStep(state.currentStep);

    // Hide Previous Winner tab during rating (same as real ChatScreen)
    // But show it during result steps and educational steps (only if tab still locked)
    // Once user clicks Continue on educational step, hide Previous Winner tab during rating
    final showPreviousWinnerTab = hasPreviousWinner &&
        (!isRatingPhase || isResultStep || (isEducationalStep && !_phaseTabUnlocked));

    // During result and educational steps, phase tab is locked until Continue is clicked
    final isPhaseTabLocked = isResultStep || (isEducationalStep && !_phaseTabUnlocked);

    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar
          _buildToggleTabs(state, showPreviousWinnerTab, isPhaseTabLocked: isPhaseTabLocked),

          // For result steps, show hint ABOVE the winner card
          if (isResultStep)
            _buildEducationalHint(
              _getResultMessage(state, l10n),
              icon: Icons.emoji_events_outlined,
            ),

          // Content based on toggle
          _showPreviousWinner && showPreviousWinnerTab
              ? _buildPreviousWinnerPanel(state, isEducationalStep: isEducationalStep)
              : _buildCurrentPhasePanel(state),

          // For result steps, add Continue button below
          // But for round1SeeResults, only show Continue after grid has been viewed
          if (isResultStep &&
              (state.currentStep != TutorialStep.round1SeeResults ||
               state.hasViewedRound1Grid)) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _handleResultContinue(state),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l10n.continue_),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  String _getResultMessage(TutorialChatState state, AppLocalizations l10n) {
    if (state.currentStep == TutorialStep.round1Result) {
      final templateKey = state.selectedTemplate;
      if (templateKey != null && templateKey != 'classic') {
        final winner = _translateProposition(
          TutorialData.round1WinnerForTemplate(templateKey), l10n);
        return l10n.tutorialRound1ResultTemplate(winner);
      }
      return l10n.tutorialRound1Result;
    } else if (state.currentStep == TutorialStep.round1SeeResults) {
      // Different message depending on whether user has viewed the grid
      if (state.hasViewedRound1Grid) {
        return l10n.tutorialSeeResultsContinueHint;
      } else {
        return l10n.tutorialSeeResultsHint;
      }
    } else if (state.currentStep == TutorialStep.round2Result) {
      final userProp = state.userProposition2 ?? l10n.tutorialYourIdea;
      return l10n.tutorialRound2Result(userProp);
    }
    return '';
  }

  void _handleResultContinue(TutorialChatState state) {
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);

    if (state.currentStep == TutorialStep.round1Result) {
      // First Continue: go to See Results step
      notifier.continueToSeeResults();
    } else if (state.currentStep == TutorialStep.round1SeeResults) {
      // Second Continue (after viewing grid): go to Round 2
      setState(() {
        _phaseTabUnlocked = true;
        _showPreviousWinner = false;
      });
      notifier.continueToRound2();
    } else if (state.currentStep == TutorialStep.round2Result) {
      // Round 3 - go directly to proposing (single click, no carry forward step)
      setState(() {
        _phaseTabUnlocked = true;
        _showPreviousWinner = false;
      });
      notifier.continueToRound3();
    }
  }

  Widget _buildToggleTabs(TutorialChatState state, bool hasPreviousWinner, {bool isPhaseTabLocked = false}) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isFirstSelected = _showPreviousWinner && hasPreviousWinner;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // Previous Winner Tab
          if (hasPreviousWinner)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showPreviousWinner = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isFirstSelected
                        ? theme.colorScheme.surface
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.previousWinner,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight:
                          isFirstSelected ? FontWeight.bold : FontWeight.normal,
                      color: isFirstSelected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          // Current Phase Tab (can be locked during educational steps)
          Expanded(
            child: GestureDetector(
              // Disable tap if locked or if no previous winner (nothing to toggle)
              onTap: isPhaseTabLocked ? null : (hasPreviousWinner
                  ? () => setState(() => _showPreviousWinner = false)
                  : null),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: !isFirstSelected
                      ? theme.colorScheme.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(hasPreviousWinner ? 0 : 12),
                    topRight: const Radius.circular(12),
                  ),
                ),
                child: Text(
                  _getPhaseTabLabel(state),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight:
                        !isFirstSelected ? FontWeight.bold : FontWeight.normal,
                    color: isPhaseTabLocked
                        ? theme.colorScheme.onSurfaceVariant.withAlpha(128)
                        : (!isFirstSelected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPhaseTabLabel(TutorialChatState state) {
    final l10n = AppLocalizations.of(context);

    // During result steps, show "Your Proposition" tab (what user submitted)
    if (_isResultStep(state.currentStep)) {
      return state.myPropositions.length > 1
          ? l10n.yourPropositions
          : l10n.yourProposition;
    }

    if (state.currentRound == null) return l10n.waiting;
    switch (state.currentRound!.phase) {
      case RoundPhase.waiting:
        return l10n.waiting;
      case RoundPhase.proposing:
        if (state.myPropositions.isEmpty) return l10n.yourProposition;
        return l10n.yourPropositions;
      case RoundPhase.rating:
        return state.hasRated ? l10n.done : l10n.rate;
    }
  }

  Widget _buildPreviousWinnerPanel(TutorialChatState state, {bool isEducationalStep = false}) {
    final l10n = AppLocalizations.of(context);

    // Only show educational content if phase tab is still locked (user hasn't clicked Continue yet)
    final showEducationalContent = isEducationalStep && !_phaseTabUnlocked;

    // Show "See Results" button only during round1SeeResults step (for tutorial hint)
    final isRound1SeeResultsStep = state.currentStep == TutorialStep.round1SeeResults;

    // Translate winner content to current locale
    final translatedWinners = state.previousRoundWinners.map((w) => RoundWinner(
      id: w.id,
      roundId: w.roundId,
      propositionId: w.propositionId,
      rank: w.rank,
      createdAt: w.createdAt,
      content: _translateProposition(w.content ?? '', l10n),
    )).toList();

    // Determine which round's results to show based on the winner's round
    // Winner roundId: -1 = Round 1, -2 = Round 2, -3 = Round 3
    final winnerRoundId = state.previousRoundWinners.isNotEmpty
        ? state.previousRoundWinners.first.roundId
        : null;

    List<Proposition>? resultsToShow;
    if (winnerRoundId == -1 && state.round1Results.isNotEmpty) {
      resultsToShow = state.round1Results;
    } else if (winnerRoundId == -2 && state.round2Results.isNotEmpty) {
      resultsToShow = state.round2Results;
    } else if (winnerRoundId == -3 && state.round3Results.isNotEmpty) {
      resultsToShow = state.round3Results;
    }

    // Translate results for grid display
    final translatedResults = resultsToShow?.map((p) => Proposition(
      id: p.id,
      roundId: p.roundId,
      participantId: p.participantId,
      content: _translateProposition(p.content, l10n),
      finalRating: p.finalRating,
      createdAt: p.createdAt,
    )).toList();

    // Show "See All Results" button when we have results, BUT not during round1Result
    // (we want to explicitly tell them to click it first in round1SeeResults)
    final hasPassedFirstResultStep = state.currentStep != TutorialStep.round1Result;
    final showResultsButton = hasPassedFirstResultStep &&
        translatedResults != null && translatedResults.isNotEmpty;

    // Determine round number from winner's roundId (-1=Round 1, -2=Round 2, -3=Round 3)
    final previousRoundNumber = winnerRoundId != null ? -winnerRoundId : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Educational hint ABOVE the winner card
        if (showEducationalContent)
          _buildEducationalHint(
            _getEducationalMessage(state, l10n),
            icon: Icons.tips_and_updates_outlined,
          ),
        PreviousWinnerPanel(
          previousRoundWinners: translatedWinners,
          currentWinnerIndex: _currentWinnerIndex,
          isSoleWinner: state.isSoleWinner,
          consecutiveSoleWins: state.consecutiveSoleWins,
          confirmationRoundsRequired: state.chat.confirmationRoundsRequired,
          currentRoundCustomId: state.currentRound?.customId,
          onWinnerIndexChanged: (index) =>
              setState(() => _currentWinnerIndex = index),
          showResultsButton: showResultsButton,
          previousRoundResults: translatedResults,
          previousRoundId: winnerRoundId,
          previousRoundNumber: previousRoundNumber,
          myParticipantId: -1,
          onResultsViewed: isRound1SeeResultsStep ? () {
            // Mark that user has viewed the grid when they return
            ref.read(tutorialChatNotifierProvider.notifier).markRound1GridViewed();
          } : null,
          showTutorialHintOnResults: isRound1SeeResultsStep,
        ),
        // Continue button (only if not yet clicked)
        if (showEducationalContent) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleEducationalContinue,
                icon: const Icon(Icons.arrow_forward),
                label: Text(l10n.continue_),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  String _getEducationalMessage(TutorialChatState state, AppLocalizations l10n) {
    if (state.currentStep == TutorialStep.round2Prompt) {
      final templateKey = state.selectedTemplate;
      if (templateKey != null && templateKey != 'classic') {
        final winner = _translateProposition(
          TutorialData.round1WinnerForTemplate(templateKey), l10n);
        return l10n.tutorialRound2PromptTemplate(winner);
      }
      return l10n.tutorialRound2Prompt;
    }
    return '';
  }

  void _handleEducationalContinue() {
    setState(() {
      _phaseTabUnlocked = true;
      _showPreviousWinner = false;
    });
  }

  Widget _buildCurrentPhasePanel(TutorialChatState state) {
    if (state.currentRound == null) {
      // Tutorial auto-starts, so show 0 participants remaining
      return WaitingStatePanel(
        participantCount: state.participants.length,
        autoStartParticipantCount: state.participants.length,
      );
    }

    switch (state.currentRound!.phase) {
      case RoundPhase.waiting:
        // Tutorial auto-advances, so show 0 participants remaining
        return WaitingStatePanel(
          participantCount: state.participants.length,
          autoStartParticipantCount: state.participants.length,
        );
      case RoundPhase.proposing:
        final l10n = AppLocalizations.of(context);
        // Show proposing hint only when user hasn't submitted yet
        // Round 1: explain what to submit
        // Round 2: explain they're challenging the winner (first time seeing it)
        // Round 3: no hint needed (they already understand)
        final isFirstRound = state.currentRound?.customId == 1;
        final isSecondRound = state.currentRound?.customId == 2;
        final showProposingHint = state.myPropositions.isEmpty && (isFirstRound || isSecondRound);
        final proposingHintText = isSecondRound
            ? l10n.tutorialProposingHintWithWinner
            : l10n.tutorialProposingHint;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProposingHint)
              _buildEducationalHint(proposingHintText),
            ProposingStatePanel(
              roundCustomId: state.currentRound!.customId,
              propositionsPerUser: state.chat.propositionsPerUser,
              myPropositions: state.myPropositions,
              propositionController: _propositionController,
              onSubmit: _submitProposition,
              phaseEndsAt: state.currentRound!.phaseEndsAt,
              onPhaseExpired: () {}, // No-op for tutorial
            ),
          ],
        );
      case RoundPhase.rating:
        final l10n = AppLocalizations.of(context);
        // Show rating hint only in Round 1 (user already learned about hidden submissions)
        final isFirstRound = state.currentRound?.customId == 1;
        final showRatingHint = isFirstRound && !state.hasStartedRating && !state.hasRated;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showRatingHint)
              _buildEducationalHint(l10n.tutorialRatingHint),
            RatingStatePanel(
              roundCustomId: state.currentRound!.customId,
              hasRated: state.hasRated,
              hasStartedRating: state.hasStartedRating,
              propositionCount: state.propositions.length,
              onStartRating: () => _openTutorialRatingScreen(state),
              phaseEndsAt: state.currentRound!.phaseEndsAt,
              onPhaseExpired: () {}, // No-op for tutorial
              isHost: true,
            ),
          ],
        );
    }
  }

  /// Build tutorial-specific panels (intro, consensus, share)
  Widget _buildTutorialPanel(TutorialChatState state) {
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);
    final theme = Theme.of(context);

    switch (state.currentStep) {
      case TutorialStep.intro:
        return TutorialIntroPanel(
          onStart: () {
            notifier.nextStep();
          },
          onSkip: _handleSkip,
        );

      case TutorialStep.templateSelection:
        return TutorialTemplatePanel(
          onSelect: (templateKey) {
            notifier.selectTemplate(templateKey);
          },
          onBack: () {
            notifier.startTutorial(); // Go back to intro
          },
        );

      case TutorialStep.round3Consensus:
        final l10n = AppLocalizations.of(context);
        final userProp = state.userProposition2 ?? l10n.tutorialYourIdea;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 48,
                color: Colors.green.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.tutorialConsensusReached,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tutorialWonTwoRounds(userProp),
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.tutorialAddedToChat,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    notifier.continueToShareDemo();
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l10n.continue_),
                ),
              ),
            ],
          ),
        );

      case TutorialStep.shareDemo:
        final l10n = AppLocalizations.of(context);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.ios_share,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.tutorialShareTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.tutorialShareExplanation,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

/// Tutorial rating screen (uses real RatingWidget)
class _TutorialRatingScreen extends StatefulWidget {
  final List<Proposition> propositions;
  final VoidCallback onComplete;
  final bool showHints;

  const _TutorialRatingScreen({
    required this.propositions,
    required this.onComplete,
    this.showHints = false,
  });

  @override
  State<_TutorialRatingScreen> createState() => _TutorialRatingScreenState();
}

class _TutorialRatingScreenState extends State<_TutorialRatingScreen> {
  RatingPhase _currentPhase = RatingPhase.binary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final propsForRating = widget.propositions
        .map((p) => {
              'id': p.id,
              'content': p.content,
            })
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tutorialRateIdeas),
      ),
      body: Column(
        children: [
          // Educational hint based on current phase
          if (widget.showHints && _currentPhase == RatingPhase.binary)
            _buildHint(context, l10n.tutorialRatingBinaryHint),
          if (widget.showHints && _currentPhase == RatingPhase.positioning)
            _buildHint(context, l10n.tutorialRatingPositioningHint),
          Expanded(
            child: RatingWidget(
              propositions: propsForRating,
              onRankingComplete: (_) => widget.onComplete(),
              lazyLoadingMode: false,
              isResuming: false,
              onPhaseChanged: widget.showHints
                  ? (phase) {
                      if (mounted) setState(() => _currentPhase = phase);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Build a hint with inline button icon previews.
  /// Parses [swap], [check], [up], [down] markers in the text and replaces
  /// them with inline WidgetSpan icons matching the actual rating buttons.
  Widget _buildHint(BuildContext context, String text) {
    final theme = Theme.of(context);
    final backgroundColor = theme.colorScheme.primaryContainer.withAlpha(100);
    final borderColor = theme.colorScheme.primary.withAlpha(80);
    final contentColor = theme.colorScheme.onPrimaryContainer;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: contentColor);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 20, color: contentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              _buildInlineHintSpans(text, theme, textStyle),
            ),
          ),
        ],
      ),
    );
  }

  /// Parse marker tokens and build an InlineSpan with inline icon widgets.
  InlineSpan _buildInlineHintSpans(String text, ThemeData theme, TextStyle? textStyle) {
    final markerPattern = RegExp(r'\[(swap|check|up|down)\]');
    final children = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in markerPattern.allMatches(text)) {
      // Add text before this marker
      if (match.start > lastEnd) {
        children.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      // Add inline icon widget for the marker
      final marker = match.group(1)!;
      children.add(_inlineIcon(marker, theme));
      lastEnd = match.end;
    }

    // Add remaining text after last marker
    if (lastEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastEnd)));
    }

    return TextSpan(style: textStyle, children: children);
  }

  /// Create an inline WidgetSpan icon for a marker token.
  WidgetSpan _inlineIcon(String marker, ThemeData theme) {
    final primaryColor = theme.colorScheme.primary;
    final IconData icon;
    final bool filled;

    switch (marker) {
      case 'swap':
        icon = Icons.swap_vert;
        filled = false;
      case 'check':
        icon = Icons.check;
        filled = true;
      case 'up':
        icon = Icons.arrow_upward;
        filled = false;
      case 'down':
        icon = Icons.arrow_downward;
        filled = false;
      default:
        icon = Icons.help_outline;
        filled = false;
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: filled ? primaryColor : theme.colorScheme.surface,
          shape: BoxShape.circle,
          border: filled ? null : Border.all(color: primaryColor, width: 1.5),
        ),
        child: Icon(
          icon,
          size: 12,
          color: filled ? Colors.white : primaryColor,
        ),
      ),
    );
  }
}
