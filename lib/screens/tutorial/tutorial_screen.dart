import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/env_config.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../widgets/message_card.dart';
import '../../widgets/qr_code_share.dart';
import '../../widgets/rating/rating_model.dart';
import '../../widgets/rating/rating_widget.dart';
import '../chat/widgets/phase_panels.dart';
import '../chat/widgets/previous_round_display.dart';
import '../rating/read_only_results_screen.dart';
import 'models/tutorial_state.dart';
import 'notifiers/tutorial_notifier.dart';
import 'tutorial_data.dart';
import '../home_tour/widgets/spotlight_overlay.dart';
import 'widgets/tutorial_intro_panel.dart';

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
  final VoidCallback? onSkip;

  const TutorialScreen({
    super.key,
    this.onComplete,
    this.onSkip,
  });

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen>
    with SingleTickerProviderStateMixin {
  final _propositionController = TextEditingController();

  // Chat tour: GlobalKeys for measuring widget positions
  final _tourBodyStackKey = GlobalKey();
  final _tourTooltipKey = GlobalKey();
  final _tourTitleKey = GlobalKey();
  final _tourMessageKey = GlobalKey();
  final _tourProposingKey = GlobalKey();
  final _tourParticipantsKey = GlobalKey();

  // Chat tour: animated tooltip position
  double _tourTooltipTop = 0;
  bool _tourMeasured = false;

  // End-tour (consensus/share): GlobalKeys for positioning
  final _endTourStackKey = GlobalKey();
  final _consensusCardKey = GlobalKey();
  double _endTourTooltipTop = 0;
  bool _endTourMeasured = false;

  // Track if tutorial completion is in progress (show loading, block back)
  bool _isCompleting = false;

  // Floating hint overlay: track dismissed hints and bottom area height
  final Set<String> _dismissedHints = {};
  final GlobalKey _bottomAreaKey = GlobalKey();
  double _bottomAreaHeight = 200; // reasonable default

  // Guards to prevent double-opening screens on auto-transitions
  bool _hasAutoOpenedRound1Results = false;
  bool _hasAutoOpenedRound2Rating = false;
  bool _hasAutoOpenedRound2Results = false;
  bool _hasAutoOpenedRound3Rating = false;

  // Transition animation: fade out chat → show transition message → continue
  late final AnimationController _transitionController;
  bool _showTransitionScreen = false;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _transitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showTransitionScreen = true);
      }
    });
  }

  @override
  void dispose() {
    _transitionController.dispose();
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
      if (widget.onSkip != null) {
        widget.onSkip!();
        // Navigate away — router redirect will handle the destination
        if (mounted) context.go('/');
      } else {
        _handleComplete();
      }
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

  void _showTutorialParticipantsSheet() {
    final participants = TutorialData.allParticipants;

    showModalBottomSheet(
      context: context,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final sheetL10n = AppLocalizations.of(modalContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '${sheetL10n.participants} (${participants.length})',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(modalContext),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Participants list
            ...participants.map((p) => ListTile(
              leading: CircleAvatar(child: Text(p.displayName[0])),
              title: Text(p.displayName),
              trailing: p.isHost ? Chip(label: Text(sheetL10n.host)) : null,
            )),
            const SizedBox(height: 16),
          ],
        );
      },
    );
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
    );
    // Dialog is informational only — closing it does not advance the tutorial.
    // The tooltip "Continue" button handles advancement.
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
          onExitTutorial: () {
            Navigator.pop(context);
            _handleSkip();
          },
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

  void _openResultsScreenForRound1(TutorialChatState state) {
    final l10n = AppLocalizations.of(context);
    final translatedResults = state.round1Results.map((p) => Proposition(
      id: p.id,
      roundId: p.roundId,
      participantId: p.participantId,
      content: _translateProposition(p.content, l10n),
      finalRating: p.finalRating,
      createdAt: p.createdAt,
    )).toList();

    // Get translated winner name for the hint
    final winnerName = state.previousRoundWinners.isNotEmpty
        ? _translateProposition(
            state.previousRoundWinners.first.content ?? '', l10n)
        : '';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReadOnlyResultsScreen(
          propositions: translatedResults,
          roundNumber: 1,
          roundId: -1,
          myParticipantId: -1,
          showTutorialHint: true,
          tutorialHintTitle: l10n.tutorialHintRoundResults,
          tutorialWinnerName: winnerName,
          onExitTutorial: () {
            Navigator.pop(context);
            _handleSkip();
          },
        ),
      ),
    ).then((_) {
      // Auto-advance to Round 2 when results screen is dismissed
      if (mounted) {
        ref.read(tutorialChatNotifierProvider.notifier).continueToRound2();
      }
    });
  }

  void _openResultsScreenForRound2(TutorialChatState state) {
    final l10n = AppLocalizations.of(context);
    final translatedResults = state.round2Results.map((p) => Proposition(
      id: p.id,
      roundId: p.roundId,
      participantId: p.participantId,
      content: _translateProposition(p.content, l10n),
      finalRating: p.finalRating,
      createdAt: p.createdAt,
    )).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReadOnlyResultsScreen(
          propositions: translatedResults,
          roundNumber: 2,
          roundId: -2,
          myParticipantId: -1,
          showTutorialHint: true,
          tutorialHintTitle: l10n.tutorialHintYouWon,
          tutorialHintDescription: l10n.tutorialR2ResultsHint,
          onExitTutorial: () {
            Navigator.pop(context);
            _handleSkip();
          },
        ),
      ),
    ).then((_) {
      // Advance to Round 3 when results screen is dismissed
      if (mounted) {
        ref.read(tutorialChatNotifierProvider.notifier).continueToRound3();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tutorialChatNotifierProvider);
    // Watch locale to rebuild when language changes
    ref.watch(localeProvider);

    // Auto-open screens on step transitions
    ref.listen<TutorialChatState>(tutorialChatNotifierProvider, (prev, next) {
      // Auto-open results screen after R1 rating completes
      if (prev?.currentStep != TutorialStep.round1Result &&
          next.currentStep == TutorialStep.round1Result &&
          !_hasAutoOpenedRound1Results) {
        _hasAutoOpenedRound1Results = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openResultsScreenForRound1(next);
          }
        });
      }
      // Auto-open rating screen when transitioning to R2 rating
      if (prev?.currentStep != TutorialStep.round2Rating &&
          next.currentStep == TutorialStep.round2Rating &&
          !_hasAutoOpenedRound2Rating) {
        _hasAutoOpenedRound2Rating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openTutorialRatingScreen(next);
          }
        });
      }
      // Auto-open rating screen when transitioning to R3 rating
      if (prev?.currentStep != TutorialStep.round3Rating &&
          next.currentStep == TutorialStep.round3Rating &&
          !_hasAutoOpenedRound3Rating) {
        _hasAutoOpenedRound3Rating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openTutorialRatingScreen(next);
          }
        });
      }
      // Auto-open results screen after R2 rating completes
      if (prev?.currentStep != TutorialStep.round2Result &&
          next.currentStep == TutorialStep.round2Result &&
          !_hasAutoOpenedRound2Results) {
        _hasAutoOpenedRound2Results = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openResultsScreenForRound2(next);
          }
        });
      }
      // Start fade-out animation when reaching complete step
      if (prev?.currentStep != TutorialStep.complete &&
          next.currentStep == TutorialStep.complete) {
        _transitionController.forward();
      }
    });

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

    // Complete step: fade out chat → show transition message → continue to home
    if (state.currentStep == TutorialStep.complete) {
      return _buildCompletionTransition();
    }

    // Chat tour: dedicated screen with progressive reveal
    if (state.isChatTourStep) {
      return _buildChatTourScreen(state);
    }

    // Check if we should show tutorial-specific panels
    final showTutorialPanel = _shouldShowTutorialPanel(state.currentStep);

    // Show share button at shareDemo step and beyond
    final showShareButton = state.currentStep == TutorialStep.shareDemo ||
        state.currentStep == TutorialStep.complete;

    // End-tour steps: consensus + share demo use dimmed spotlight pattern
    // convergenceContinue is an end-tour step but keeps everything fully visible
    final isEndTour = _isEndTourStep(state.currentStep);
    final dimOpacity = (isEndTour && state.currentStep != TutorialStep.convergenceContinue) ? 0.25 : 1.0;

    return Scaffold(
      appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 4,
              title: AnimatedOpacity(
                opacity: dimOpacity,
                duration: const Duration(milliseconds: 250),
                child: Builder(
                  builder: (context) {
                    final l10n = AppLocalizations.of(context);
                    return Text(
                      l10n.tutorialAppBarTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    );
                  },
                ),
              ),
              actions: [
                // Participants icon (after intro, matching chat screen)
                if (state.currentStep != TutorialStep.intro)
                  AnimatedOpacity(
                    opacity: dimOpacity,
                    duration: const Duration(milliseconds: 250),
                    child: Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context);
                        return IconButton(
                          icon: const Icon(Icons.people),
                          tooltip: l10n.participants,
                          onPressed: isEndTour ? null : _showTutorialParticipantsSheet,
                        );
                      },
                    ),
                  ),
                // Share icon (revealed at shareDemo and beyond)
                // Spotlighted during shareDemo, normal at complete
                if (showShareButton)
                  AnimatedOpacity(
                    opacity: state.currentStep == TutorialStep.shareDemo ? 1.0 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: Builder(
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
                  ),
                // Exit button (always available)
                AnimatedOpacity(
                  opacity: dimOpacity,
                  duration: const Duration(milliseconds: 250),
                  child: Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context);
                      return IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.tutorialSkipMenuItem,
                        onPressed: _handleSkip,
                      );
                    },
                  ),
                ),
              ],
            ),
      body: state.currentStep == TutorialStep.intro
          // Intro: full screen panel (AppBar provides safe area)
          ? _buildTutorialPanel(state)
          // After template selection: Stack with Column + floating hint overlay
          : _buildMainStack(state, dimOpacity, isEndTour, showTutorialPanel),
    );
  }

  /// Build the main content as a Stack: Column layout + floating hint overlay.
  Widget _buildMainStack(
    TutorialChatState state,
    double dimOpacity,
    bool isEndTour,
    bool showTutorialPanel,
  ) {
    // Measure bottom area height after layout for hint positioning
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureBottomArea();
    });

    return Stack(
      children: [
        // Layer 0: existing Column layout (unchanged)
        Column(
          children: [
            // Phase-aware accent strip (matches real chat screen)
            PhaseAccentStrip(phase: state.currentRound?.phase),

            // Chat History — wrapped in Stack for end-tour tooltip
            Expanded(
              child: Stack(
                key: _endTourStackKey,
                children: [
                  Builder(
                    builder: (bodyContext) {
                      final l10n = AppLocalizations.of(bodyContext);
                      final templateKey = state.selectedTemplate;
                      final initialMessage = state.customQuestion ??
                          TutorialTemplate.translateQuestion(templateKey, l10n);

                      if (isEndTour) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _updateEndTourTooltipPosition(state);
                        });
                      }

                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Center(
                            child: AnimatedOpacity(
                              opacity: state.currentStep == TutorialStep.round3Consensus ||
                                      state.currentStep == TutorialStep.convergenceContinue
                                  ? 1.0
                                  : dimOpacity,
                              duration: const Duration(milliseconds: 250),
                              child: MessageCard(
                                label: l10n.initialMessage,
                                content: initialMessage,
                                isPrimary: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...state.consensusItems.asMap().entries.map((entry) {
                            final isSpotlighted =
                                state.currentStep == TutorialStep.round3Consensus ||
                                state.currentStep == TutorialStep.convergenceContinue;
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: AnimatedOpacity(
                                  opacity: isSpotlighted ? 1.0 : dimOpacity,
                                  duration: const Duration(milliseconds: 250),
                                  child: KeyedSubtree(
                                    key: entry.key == state.consensusItems.length - 1
                                        ? _consensusCardKey
                                        : null,
                                    child: MessageCard(
                                      label: l10n.consensusNumber(entry.key + 1),
                                      content: entry.value.displayContent,
                                      isPrimary: true,
                                      isConsensus: true,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                  if (isEndTour && _endTourMeasured)
                    _buildEndTourTooltip(state),
                ],
              ),
            ),

            // Bottom Area - dimmed during end tour, keyed for measurement
            Flexible(
              flex: 0,
              child: KeyedSubtree(
                key: _bottomAreaKey,
                child: AnimatedOpacity(
                  opacity: dimOpacity,
                  duration: const Duration(milliseconds: 250),
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
              ),
            ),
          ],
        ),

        // Layer 1: floating hint overlay
        if (_activeHintId(state) != null)
          _buildFloatingHint(state),
      ],
    );
  }

  // === Chat Tour ===

  /// 3-state opacity for progressive reveal:
  /// before target → 0.0, on target → 1.0, after target → 0.25
  double _chatTourOpacity(TutorialStep current, TutorialStep target) {
    if (current.index < target.index) return 0.0;
    if (current == target) return 1.0;
    return 0.25;
  }

  void _updateChatTourTooltipPosition() {
    final state = ref.read(tutorialChatNotifierProvider);
    final stackBox =
        _tourBodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    double newTop;

    switch (state.currentStep) {
      case TutorialStep.chatTourTitle:
        // Just below AppBar
        newTop = 8;
      case TutorialStep.chatTourParticipants:
        // Just below AppBar (participants button is in the app bar)
        newTop = 8;
      case TutorialStep.chatTourMessage:
        final targetBox =
            _tourMessageKey.currentContext?.findRenderObject() as RenderBox?;
        if (targetBox == null) return;
        final pos = targetBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = pos.dy + targetBox.size.height + 12;
      case TutorialStep.chatTourProposing:
        // Above the proposing input area
        final proposingBox =
            _tourProposingKey.currentContext?.findRenderObject() as RenderBox?;
        if (proposingBox == null) return;
        final proposingPos =
            proposingBox.localToGlobal(Offset.zero, ancestor: stackBox);
        final tooltipBoxP =
            _tourTooltipKey.currentContext?.findRenderObject() as RenderBox?;
        final tooltipH = tooltipBoxP?.size.height ?? 180;
        newTop = proposingPos.dy - tooltipH - 12;
      default:
        return;
    }

    // Clamp within bounds
    final tooltipBox =
        _tourTooltipKey.currentContext?.findRenderObject() as RenderBox?;
    final tooltipH = tooltipBox?.size.height ?? 180;
    final maxTop = stackBox.size.height - tooltipH - 8;
    newTop = newTop.clamp(0.0, maxTop);

    if ((newTop - _tourTooltipTop).abs() > 0.5 || !_tourMeasured) {
      setState(() {
        _tourTooltipTop = newTop;
        _tourMeasured = true;
      });
    }
  }

  Widget _buildChatTourScreen(TutorialChatState state) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);
    final step = state.currentStep;

    // Measure tooltip position after layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateChatTourTooltipPosition();
      }
    });

    // Chat name for title
    final chatName = state.customQuestion != null
        ? l10n.tutorialAppBarTitle
        : TutorialData.chatNameForTemplate(state.selectedTemplate);

    // Initial message (same logic as main build)
    final templateKey = state.selectedTemplate;
    final initialMessage = state.customQuestion ??
        TutorialTemplate.translateQuestion(templateKey, l10n);

    // Tooltip content
    String tourTitle;
    String tourDescription;
    switch (step) {
      case TutorialStep.chatTourTitle:
        tourTitle = l10n.chatTourTitleTitle;
        tourDescription = l10n.chatTourTitleDesc;
      case TutorialStep.chatTourParticipants:
        tourTitle = l10n.chatTourParticipantsTitle;
        tourDescription = l10n.chatTourParticipantsDesc;
      case TutorialStep.chatTourMessage:
        tourTitle = l10n.chatTourMessageTitle;
        tourDescription = l10n.chatTourMessageDesc;
      case TutorialStep.chatTourProposing:
        tourTitle = l10n.chatTourProposingTitle;
        tourDescription = l10n.chatTourProposingDesc;
      default:
        tourTitle = '';
        tourDescription = '';
    }

    final isLastStep =
        state.chatTourStepIndex == TutorialChatState.chatTourTotalSteps - 1;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: KeyedSubtree(
          key: _tourTitleKey,
          child: AnimatedOpacity(
            opacity: _chatTourOpacity(step, TutorialStep.chatTourTitle),
            duration: const Duration(milliseconds: 250),
            child: Text(chatName),
          ),
        ),
        actions: [
          // Participants button
          KeyedSubtree(
            key: _tourParticipantsKey,
            child: AnimatedOpacity(
              opacity:
                  _chatTourOpacity(step, TutorialStep.chatTourParticipants),
              duration: const Duration(milliseconds: 250),
              child: IconButton(
                icon: const Icon(Icons.people_outline),
                tooltip: l10n.participants,
                onPressed: _showTutorialParticipantsSheet,
              ),
            ),
          ),
          // Skip/close button (always visible)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.tutorialSkipMenuItem,
            onPressed: _handleSkip,
          ),
        ],
      ),
      body: SizedBox.expand(
        child: Stack(
          key: _tourBodyStackKey,
          children: [
            // Layer 1: Progressively revealed content
            Positioned.fill(
              child: Column(
                children: [
                  // Initial message card
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: KeyedSubtree(
                      key: _tourMessageKey,
                      child: AnimatedOpacity(
                        opacity: _chatTourOpacity(
                            step, TutorialStep.chatTourMessage),
                        duration: const Duration(milliseconds: 250),
                        child: MessageCard(
                          label: l10n.initialMessage,
                          content: initialMessage,
                          isPrimary: true,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Mock bottom area (proposing input)
                  KeyedSubtree(
                    key: _tourProposingKey,
                    child: AnimatedOpacity(
                      opacity: _chatTourOpacity(
                          step, TutorialStep.chatTourProposing),
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border(
                            top: BorderSide(color: theme.dividerColor),
                          ),
                        ),
                        child: AbsorbPointer(
                          child: ProposingStatePanel(
                            roundCustomId: 1,
                            propositionsPerUser: 1,
                            myPropositions: const [],
                            propositionController: _propositionController,
                            onSubmit: () {},
                            phaseEndsAt: TutorialData.round1().phaseEndsAt,
                            onPhaseExpired: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Layer 2: Animated tooltip overlay
            if (_tourMeasured)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                left: 16,
                right: 16,
                top: _tourTooltipTop,
                child: KeyedSubtree(
                  key: _tourTooltipKey,
                  child: TourTooltipCard(
                    title: tourTitle,
                    description: tourDescription,
                    onNext: () => notifier.nextChatTourStep(),
                    onSkip: () => notifier.skipChatTour(),
                    stepIndex: state.chatTourStepIndex,
                    totalSteps: TutorialChatState.chatTourTotalSteps,
                    nextLabel: isLastStep
                        ? l10n.homeTourFinish
                        : l10n.homeTourNext,
                    skipLabel: l10n.homeTourSkip,
                    stepOfLabel: l10n.homeTourStepOf(
                      state.chatTourStepIndex + 1,
                      TutorialChatState.chatTourTotalSteps,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // === Floating Hint Overlay ===

  /// Determine which hint (if any) should be shown for the current state.
  /// Returns null if no hint is active or it has been dismissed.
  String? _activeHintId(TutorialChatState state) {
    final step = state.currentStep;
    final round = state.currentRound;

    // R2 intro hint: shown when round2Prompt or round2Proposing and user hasn't typed yet
    if ((step == TutorialStep.round2Prompt || step == TutorialStep.round2Proposing) &&
        state.previousRoundWinners.isNotEmpty &&
        state.myPropositions.isEmpty) {
      const id = 'r2_intro';
      if (!_dismissedHints.contains(id)) return id;
    }

    // R3 intro hint: shown when round 3, proposing, user hasn't typed yet
    if (step == TutorialStep.round3Proposing &&
        round?.customId == 3 &&
        state.myPropositions.isEmpty &&
        state.previousRoundWinners.isNotEmpty) {
      const id = 'r3_intro';
      if (!_dismissedHints.contains(id)) return id;
    }

    // R1 rating hint: shown for round 1, rating, not started
    if (round?.phase == RoundPhase.rating &&
        round?.customId == 1 &&
        !state.hasStartedRating &&
        !state.hasRated) {
      const id = 'r1_rating';
      if (!_dismissedHints.contains(id)) return id;
    }

    return null;
  }

  /// Build the floating hint overlay as a Positioned TourTooltipCard.
  Widget _buildFloatingHint(TutorialChatState state) {
    final hintId = _activeHintId(state);
    if (hintId == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    final String title;
    final String description;

    switch (hintId) {
      case 'r2_intro':
        title = l10n.tutorialHintRound2;
        description = _getWinnerIntroMessage(state, l10n);
      case 'r3_intro':
        title = l10n.tutorialHintYouWon;
        final userWinner = state.userProposition2 ?? '';
        final r1Winner = _translateProposition(
          TutorialData.round1WinnerForTemplate(state.selectedTemplate), l10n);
        description = l10n.tutorialRound3PromptTemplate(userWinner, r1Winner);
      case 'r1_rating':
        title = l10n.tutorialHintRateIdeas;
        description = l10n.tutorialRatingPhaseExplanation;
      default:
        return const SizedBox.shrink();
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: _bottomAreaHeight + 8,
      child: GestureDetector(
        onTap: () => setState(() => _dismissedHints.add(hintId)),
        child: TourTooltipCard(
          title: title,
          description: description,
          onNext: () => setState(() => _dismissedHints.add(hintId)),
          onSkip: _handleSkip,
          stepIndex: 0,
          totalSteps: 0,
          nextLabel: l10n.homeTourFinish,
          skipLabel: l10n.tutorialSkipMenuItem,
          stepOfLabel: '',
        ),
      ),
    );
  }

  /// Measure the bottom area height after layout for floating hint positioning.
  void _measureBottomArea() {
    final box = _bottomAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final h = box.size.height;
      if ((h - _bottomAreaHeight).abs() > 1) {
        setState(() => _bottomAreaHeight = h);
      }
    }
  }

  /// Determine if we should show a tutorial-specific panel (not chat-like)
  bool _shouldShowTutorialPanel(TutorialStep step) {
    // Intro uses tutorial panel (no tabbar)
    // Complete is handled separately by _buildCompletionTransition
    return step == TutorialStep.intro;
  }

  /// Whether we're in the end-tour (consensus + convergenceContinue + share demo spotlight steps)
  bool _isEndTourStep(TutorialStep step) {
    return step == TutorialStep.round3Consensus ||
        step == TutorialStep.convergenceContinue ||
        step == TutorialStep.shareDemo;
  }

  /// Phase accent strip matching the real chat screen.

  /// Measure position of consensus card to place tooltip right below it
  void _updateEndTourTooltipPosition(TutorialChatState state) {
    final stackBox =
        _endTourStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    double newTop;

    if (state.currentStep == TutorialStep.round3Consensus ||
        state.currentStep == TutorialStep.convergenceContinue) {
      // Position right below the consensus card
      final consensusBox =
          _consensusCardKey.currentContext?.findRenderObject() as RenderBox?;
      if (consensusBox != null) {
        final consensusPos =
            consensusBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = consensusPos.dy + consensusBox.size.height + 8;
      } else {
        newTop = 8;
      }
    } else {
      // shareDemo: position near top (below where AppBar ends)
      newTop = 8;
    }

    // Clamp to stay within the stack
    final maxTop = stackBox.size.height - 200;
    newTop = newTop.clamp(0.0, maxTop);

    if ((newTop - _endTourTooltipTop).abs() > 0.5 || !_endTourMeasured) {
      setState(() {
        _endTourTooltipTop = newTop;
        _endTourMeasured = true;
      });
    }
  }

  /// Build the TourTooltipCard for consensus / convergenceContinue / share demo steps
  Widget _buildEndTourTooltip(TutorialChatState state) {
    print('[TUTORIAL] _buildEndTourTooltip called with step: ${state.currentStep}');
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);
    final userProp = state.userProposition2 ?? l10n.tutorialYourIdea;

    final String title;
    final String description;
    final int stepIndex;
    final VoidCallback onNext;
    final String nextLabel;

    if (state.currentStep == TutorialStep.round3Consensus) {
      title = l10n.tutorialConsensusReached;
      description = l10n.tutorialWonTwoRounds(userProp);
      stepIndex = 0;
      onNext = () => notifier.continueToConvergenceContinue();
      nextLabel = l10n.continue_;
    } else if (state.currentStep == TutorialStep.convergenceContinue) {
      title = l10n.tutorialProcessContinuesTitle;
      description = l10n.tutorialProcessContinuesDesc;
      stepIndex = 1;
      onNext = () => notifier.continueToShareDemo();
      nextLabel = l10n.continue_;
    } else {
      // shareDemo — "Continue" advances; share icon opens QR dialog
      title = l10n.tutorialShareTitle;
      description = l10n.tutorialShareExplanation;
      stepIndex = 2;
      onNext = () =>
          ref.read(tutorialChatNotifierProvider.notifier).completeTutorial();
      nextLabel = l10n.continue_;
    }

    // convergenceContinue: anchor above the bottom text field area
    if (state.currentStep == TutorialStep.convergenceContinue) {
      return Positioned(
        left: 16,
        right: 16,
        bottom: 8,
        child: TourTooltipCard(
          title: title,
          description: description,
          onNext: onNext,
          onSkip: _handleSkip,
          stepIndex: stepIndex,
          totalSteps: 3,
          nextLabel: nextLabel,
          skipLabel: l10n.homeTourSkip,
          stepOfLabel: l10n.homeTourStepOf(stepIndex + 1, 3),
        ),
      );
    }

    return Positioned(
      left: 16,
      right: 16,
      top: _endTourTooltipTop,
      child: TourTooltipCard(
        title: title,
        description: description,
        onNext: onNext,
        onSkip: _handleSkip,
        stepIndex: stepIndex,
        totalSteps: 3,
        nextLabel: nextLabel,
        skipLabel: l10n.homeTourSkip,
        stepOfLabel: l10n.homeTourStepOf(stepIndex + 1, 3),
      ),
    );
  }

  /// Build the completion transition: fade out → centered message → Continue
  Widget _buildCompletionTransition() {
    final theme = Theme.of(context);

    final l10nOuter = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10nOuter.tutorialSkipMenuItem,
            onPressed: _handleSkip,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _transitionController,
        builder: (context, child) {
          // Phase 1: fade out (0.0 → 1.0 of animation = 1.0 → 0.0 opacity)
          if (!_showTransitionScreen) {
            return Opacity(
              opacity: 1.0 - _transitionController.value,
              child: const SizedBox.expand(),
            );
          }
          // Phase 2: fade in transition message
          return child!;
        },
        child: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                  builder: (context, opacity, child) {
                    return Opacity(
                      opacity: opacity,
                      child: child,
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.tutorialTransitionTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.tutorialTransitionDesc,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _handleComplete,
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(l10n.continue_),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Build the bottom area — no tabs, inline emerging idea + phase panel.
  /// Hints have been moved to the floating overlay (_buildFloatingHint).
  Widget _buildChatBottomArea(TutorialChatState state) {
    final hasPreviousWinner = state.previousRoundWinners.isNotEmpty;
    final isProposing = state.currentRound?.phase == RoundPhase.proposing;
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
          // Inline emerging idea card (during proposing when a winner exists)
          // Hide during end-tour steps (convergenceContinue, shareDemo, complete)
          if (hasPreviousWinner && isProposing &&
              !_isEndTourStep(state.currentStep))
            _buildTutorialWinnerPanel(state),

          // Current phase panel (always visible — textfield or rate button)
          _buildCurrentPhasePanel(state),
        ],
      ),
    );
  }

  /// Get the R2 intro hint — tells the user what to do next.
  String _getWinnerIntroMessage(TutorialChatState state, AppLocalizations l10n) {
    final templateKey = state.selectedTemplate;
    if (templateKey != null && templateKey != 'classic') {
      final winner = _translateProposition(
        TutorialData.round1WinnerForTemplate(templateKey), l10n);
      return l10n.tutorialRound2PromptSimplifiedTemplate(winner);
    }
    return l10n.tutorialRound2PromptSimplified;
  }

  /// Builds a PreviousWinnerPanel for the tutorial, translating winner content
  /// and providing custom results navigation.
  Widget _buildTutorialWinnerPanel(TutorialChatState state) {
    if (state.previousRoundWinners.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final winner = state.previousRoundWinners.first;

    // Translate the winner content for display
    final translatedWinners = [
      RoundWinner(
        id: winner.id,
        roundId: winner.roundId,
        propositionId: winner.propositionId,
        content: _translateProposition(winner.content ?? '', l10n),
        globalScore: winner.globalScore,
        rank: winner.rank,
        createdAt: winner.createdAt,
      ),
    ];

    // Determine which round's results to show
    final winnerRoundId = winner.roundId;
    List<Proposition>? resultsToShow;
    int roundNumber = 1;
    if (winnerRoundId == -1 && state.round1Results.isNotEmpty) {
      resultsToShow = state.round1Results;
      roundNumber = 1;
    } else if (winnerRoundId == -2 && state.round2Results.isNotEmpty) {
      resultsToShow = state.round2Results;
      roundNumber = 2;
    }

    return PreviousWinnerPanel(
      previousRoundWinners: translatedWinners,
      currentWinnerIndex: 0,
      isSoleWinner: true,
      consecutiveSoleWins: 1,
      confirmationRoundsRequired: state.chat.confirmationRoundsRequired,
      currentRoundCustomId: state.currentRound?.customId,
      onWinnerIndexChanged: (_) {},
      showResultsButton: resultsToShow != null,
      onViewResults: resultsToShow != null
          ? () => _openResultsScreen(resultsToShow!, roundNumber)
          : null,
    );
  }

  /// Open the read-only results screen for the given round.
  void _openResultsScreen(List<Proposition> results, int roundNumber) {
    final l10n = AppLocalizations.of(context);
    final translatedResults = results.map((p) => Proposition(
      id: p.id,
      roundId: p.roundId,
      participantId: p.participantId,
      content: _translateProposition(p.content, l10n),
      finalRating: p.finalRating,
      createdAt: p.createdAt,
    )).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReadOnlyResultsScreen(
          propositions: translatedResults,
          roundNumber: roundNumber,
          roundId: -roundNumber,
          myParticipantId: -1,
          onExitTutorial: () {
            Navigator.pop(context);
            _handleSkip();
          },
        ),
      ),
    );
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
        // Hints moved to floating overlay (_buildFloatingHint)
        return ProposingStatePanel(
          roundCustomId: state.currentRound!.customId,
          propositionsPerUser: state.chat.propositionsPerUser,
          myPropositions: state.myPropositions,
          propositionController: _propositionController,
          onSubmit: _submitProposition,
          phaseEndsAt: state.currentRound!.phaseEndsAt,
          onPhaseExpired: () {}, // No-op for tutorial
        );
      case RoundPhase.rating:
        // Hints moved to floating overlay (_buildFloatingHint)
        return RatingStatePanel(
          roundCustomId: state.currentRound!.customId,
          hasRated: state.hasRated,
          hasStartedRating: state.hasStartedRating,
          propositionCount: state.propositions.length,
          onStartRating: () => _openTutorialRatingScreen(state),
          phaseEndsAt: state.currentRound!.phaseEndsAt,
          onPhaseExpired: () {}, // No-op for tutorial
          isHost: true,
        );
    }
  }

  /// Build tutorial-specific panel (intro only)
  Widget _buildTutorialPanel(TutorialChatState state) {
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);

    if (state.currentStep == TutorialStep.intro) {
      return TutorialIntroPanel(
        onSelect: (templateKey) {
          notifier.selectTemplate(templateKey);
        },
        onSkip: _handleSkip,
      );
    }

    return const SizedBox.shrink();
  }
}

/// Tutorial rating screen (uses real RatingWidget)
class _TutorialRatingScreen extends StatefulWidget {
  final List<Proposition> propositions;
  final VoidCallback onComplete;
  final VoidCallback? onExitTutorial;
  final bool showHints;

  const _TutorialRatingScreen({
    required this.propositions,
    required this.onComplete,
    this.onExitTutorial,
    this.showHints = false,
  });

  @override
  State<_TutorialRatingScreen> createState() => _TutorialRatingScreenState();
}

class _TutorialRatingScreenState extends State<_TutorialRatingScreen> {
  RatingPhase _currentPhase = RatingPhase.binary;
  bool _dismissedRatingHint = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final propsForRating = widget.propositions
        .map((p) => {
              'id': p.id,
              'content': p.content,
            })
        .toList();

    // Determine active hint
    final String? hintTitle;
    final String? hintDescription;
    final bool hasInlineIcons;

    if (_dismissedRatingHint) {
      hintTitle = null;
      hintDescription = null;
      hasInlineIcons = false;
    } else if (widget.showHints && _currentPhase == RatingPhase.binary) {
      hintTitle = l10n.tutorialHintCompare;
      hintDescription = l10n.tutorialRatingBinaryHint;
      hasInlineIcons = true;
    } else if (widget.showHints && _currentPhase == RatingPhase.positioning) {
      hintTitle = l10n.tutorialHintPosition;
      hintDescription = l10n.tutorialRatingPositioningHint;
      hasInlineIcons = true;
    } else {
      hintTitle = null;
      hintDescription = null;
      hasInlineIcons = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tutorialRateIdeas),
        actions: [
          if (widget.onExitTutorial != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.tutorialSkipMenuItem,
              onPressed: widget.onExitTutorial,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Layer 0: full-size rating widget (no layout shift)
          Positioned.fill(
            child: RatingWidget(
              propositions: propsForRating,
              onRankingComplete: (_) => widget.onComplete(),
              lazyLoadingMode: false,
              isResuming: false,
              onPhaseChanged: widget.showHints
                  ? (phase) {
                      if (mounted) {
                        setState(() {
                          _currentPhase = phase;
                          _dismissedRatingHint = false; // Reset on phase change
                        });
                      }
                    }
                  : null,
            ),
          ),
          // Layer 1: floating hint overlay
          if (hintTitle != null && hintDescription != null)
            Positioned(
              left: 16,
              right: 16,
              top: 8,
              child: GestureDetector(
                onTap: () => setState(() => _dismissedRatingHint = true),
                child: TourTooltipCard(
                  title: hintTitle,
                  description: hintDescription,
                  descriptionWidget: hasInlineIcons
                      ? Text.rich(
                          _buildInlineHintSpans(
                            hintDescription,
                            Theme.of(context),
                            Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : null,
                  onNext: () => setState(() => _dismissedRatingHint = true),
                  onSkip: widget.onExitTutorial ?? () {},
                  stepIndex: 0,
                  totalSteps: 1,
                  nextLabel: l10n.homeTourFinish,
                  skipLabel: l10n.tutorialSkipMenuItem,
                  stepOfLabel: '',
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Parse marker tokens and build an InlineSpan with inline icon widgets.
  InlineSpan _buildInlineHintSpans(String text, ThemeData theme, TextStyle? textStyle) {
    final markerPattern = RegExp(r'\[(swap|check|up|down|undo|zoomin|zoomout)\]');
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
    final outlineColor = theme.colorScheme.outline;
    const undoColor = Color(0xFF8B0000);

    final IconData icon;
    final Color bgColor;
    final Color iconColor;
    final Color borderColor;

    switch (marker) {
      case 'swap':
        icon = Icons.swap_vert;
        bgColor = theme.colorScheme.surface;
        iconColor = primaryColor;
        borderColor = primaryColor;
      case 'check':
        icon = Icons.check;
        bgColor = primaryColor;
        iconColor = Colors.white;
        borderColor = Colors.transparent;
      case 'up':
        icon = Icons.arrow_upward;
        bgColor = theme.colorScheme.surface;
        iconColor = primaryColor;
        borderColor = primaryColor;
      case 'down':
        icon = Icons.arrow_downward;
        bgColor = theme.colorScheme.surface;
        iconColor = primaryColor;
        borderColor = primaryColor;
      case 'undo':
        icon = Icons.undo;
        bgColor = theme.colorScheme.surface;
        iconColor = undoColor.withAlpha(128);
        borderColor = undoColor.withAlpha(128);
      case 'zoomin':
        icon = Icons.zoom_in;
        bgColor = theme.colorScheme.surface;
        iconColor = outlineColor;
        borderColor = outlineColor.withAlpha(128);
      case 'zoomout':
        icon = Icons.zoom_out;
        bgColor = theme.colorScheme.surface;
        iconColor = outlineColor;
        borderColor = outlineColor.withAlpha(128);
      default:
        icon = Icons.help_outline;
        bgColor = theme.colorScheme.surface;
        iconColor = primaryColor;
        borderColor = primaryColor;
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: borderColor == Colors.transparent
              ? null
              : Border.all(color: borderColor, width: 1.5),
        ),
        child: Icon(
          icon,
          size: 12,
          color: iconColor,
        ),
      ),
    );
  }
}

