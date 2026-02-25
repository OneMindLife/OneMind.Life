import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env_config.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../widgets/language_selector.dart';
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
import 'widgets/tutorial_progress_dots.dart';

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

  // Chat tour: GlobalKeys for measuring widget positions
  final _tourBodyStackKey = GlobalKey();
  final _tourTooltipKey = GlobalKey();
  final _tourTitleKey = GlobalKey();
  final _tourMessageKey = GlobalKey();
  final _tourProposingKey = GlobalKey();
  final _tourParticipantsKey = GlobalKey();
  final _tourShareKey = GlobalKey();

  // Chat tour: animated tooltip position
  double _tourTooltipTop = 0;
  bool _tourMeasured = false;

  // UI toggle state (same as ChatScreen)
  bool _showPreviousWinner = false;
  int _currentWinnerIndex = 0;
  int? _lastWinnerRoundId;

  // Tutorial-specific: track if user has clicked Continue to unlock phase tab
  bool _phaseTabUnlocked = false;

  // Two-step flow: first Continue button, then tap-tab instruction
  bool _hintContinueClicked = false;

  // Track if tutorial completion is in progress (show loading, block back)
  bool _isCompleting = false;

  // Guards to prevent double-opening screens on auto-transitions
  bool _hasAutoOpenedRound1Results = false;
  bool _hasAutoOpenedRound2Rating = false;
  bool _hasAutoOpenedRound3Rating = false;

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
          isRound2: state.currentStep == TutorialStep.round2Rating,
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
          tutorialWinnerName: winnerName,
        ),
      ),
    );
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

    // Chat tour: dedicated screen with progressive reveal
    if (state.isChatTourStep) {
      return _buildChatTourScreen(state);
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
      appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context);
                  return Text(l10n.tutorialAppBarTitle);
                },
              ),
              actions: [
                // Language selector on intro screen
                if (state.currentStep == TutorialStep.intro)
                  const LanguageSelector(compact: true),
                // Participants and share icons (after intro, matching chat screen)
                if (state.currentStep != TutorialStep.intro) ...[
                  Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context);
                      return IconButton(
                        icon: const Icon(Icons.people_outline),
                        tooltip: l10n.participants,
                        onPressed: () {},
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context);
                      return IconButton(
                        key: const Key('tutorial-share-button'),
                        icon: const Icon(Icons.ios_share),
                        tooltip: l10n.tutorialShareTooltip,
                        onPressed: showShareButton ? _showDemoQrCode : () {},
                      );
                    },
                  ),
                ],
                // Exit button (not on intro - skip is in panel)
                if (state.currentStep != TutorialStep.intro)
                  Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context);
                      return IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.tutorialSkipMenuItem,
                        onPressed: _handleSkip,
                      );
                    },
                  ),
              ],
            ),
      body: state.currentStep == TutorialStep.intro
          // Intro: full screen panel (AppBar provides safe area)
          ? _buildTutorialPanel(state)
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
                          Center(
                            child: _buildMessageCard(
                              l10n.initialMessage,
                              initialMessage,
                              isPrimary: true,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Consensus Items
                          ...state.consensusItems.asMap().entries.map((entry) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildMessageCard(
                                  l10n.consensusNumber(entry.key + 1),
                                  entry.value.displayContent,
                                  isPrimary: true,
                                ),
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
      case TutorialStep.chatTourParticipants:
        // Just below AppBar
        newTop = 8;
      case TutorialStep.chatTourShare:
        // Just below AppBar
        newTop = 8;
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
        // Debug: print dimensions of tour elements
        final stackBox = _tourBodyStackKey.currentContext?.findRenderObject() as RenderBox?;
        final messageBox = _tourMessageKey.currentContext?.findRenderObject() as RenderBox?;
        final proposingBox = _tourProposingKey.currentContext?.findRenderObject() as RenderBox?;
        final tooltipBox = _tourTooltipKey.currentContext?.findRenderObject() as RenderBox?;
        print('=== CHAT TOUR DEBUG ===');
        print('Step: ${state.currentStep}');
        print('Stack size: ${stackBox?.size}');
        print('Message size: ${messageBox?.size}');
        print('Proposing size: ${proposingBox?.size}');
        print('Tooltip size: ${tooltipBox?.size}');
        if (stackBox != null && proposingBox != null) {
          final proposingPos = proposingBox.localToGlobal(Offset.zero, ancestor: stackBox);
          print('Proposing top in stack: ${proposingPos.dy}');
        }
        if (stackBox != null && messageBox != null) {
          final messagePos = messageBox.localToGlobal(Offset.zero, ancestor: stackBox);
          print('Message top in stack: ${messagePos.dy}');
        }
        print('Tooltip top: $_tourTooltipTop');
        print('========================');
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
      case TutorialStep.chatTourMessage:
        tourTitle = l10n.chatTourMessageTitle;
        tourDescription = l10n.chatTourMessageDesc;
      case TutorialStep.chatTourProposing:
        tourTitle = l10n.chatTourProposingTitle;
        tourDescription = l10n.chatTourProposingDesc;
      case TutorialStep.chatTourParticipants:
        tourTitle = l10n.chatTourParticipantsTitle;
        tourDescription = l10n.chatTourParticipantsDesc;
      case TutorialStep.chatTourShare:
        tourTitle = l10n.chatTourShareTitle;
        tourDescription = l10n.chatTourShareDesc;
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
                onPressed: () {},
              ),
            ),
          ),
          // Share button
          KeyedSubtree(
            key: _tourShareKey,
            child: AnimatedOpacity(
              opacity: _chatTourOpacity(step, TutorialStep.chatTourShare),
              duration: const Duration(milliseconds: 250),
              child: IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: l10n.shareQrCode,
                onPressed: () {},
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
                  TutorialProgressDots(currentStep: step),
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
                        child: _buildMessageCard(
                          l10n.initialMessage,
                          initialMessage,
                          isPrimary: true,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Mock bottom area (tab bar + proposing input)
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Tab bar label
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                ),
                              ),
                              child: Text(
                                l10n.yourProposition,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            // Proposing input
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      enabled: false,
                                      decoration: InputDecoration(
                                        hintText: l10n.shareYourIdea,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        filled: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: null,
                                    child: Text(l10n.submit),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

  /// Determine if we should show a tutorial-specific panel (not chat-like)
  bool _shouldShowTutorialPanel(TutorialStep step) {
    // Intro, consensus, and shareDemo use tutorial panels (no tabbar)
    return step == TutorialStep.intro ||
        step == TutorialStep.round3Consensus ||
        step == TutorialStep.shareDemo ||
        step == TutorialStep.complete;
  }

  /// Check if current step is a result step (shows tabs + message + continue)
  bool _isResultStep(TutorialStep step) {
    return step == TutorialStep.round1Result ||
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

  /// Build an educational hint banner for the tutorial.
  /// Optionally includes a Continue button inside the hint card.
  Widget _buildEducationalHint(String text, {
    IconData icon = Icons.lightbulb_outline,
    VoidCallback? onContinue,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (onContinue != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(l10n.continue_),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEducationalHintWithCountdown(
    String text,
    DateTime endsAt, {
    String Function(String)? timeTemplate,
  }) {
    final l10n = AppLocalizations.of(context);
    return _TutorialProposingHint(
      text: text,
      endsAt: endsAt,
      timeRemainingTemplate: timeTemplate ?? (time) => l10n.tutorialTimeRemaining(time),
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

    // Phase tab is highlighted only after user clicks Continue in the hint
    final isInActionStep = isResultStep || (isEducationalStep && !_phaseTabUnlocked);
    final isPhaseTabHighlighted = isInActionStep && _hintContinueClicked;

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
          _buildToggleTabs(state, showPreviousWinnerTab,
            isPhaseTabHighlighted: isPhaseTabHighlighted,
            isPhaseTabLocked: isInActionStep && !_hintContinueClicked,
            onPhaseTabAction: isPhaseTabHighlighted ? () {
              if (isResultStep) {
                _handleResultContinue(state);
              } else if (isEducationalStep) {
                _handleEducationalContinue();
              }
            } : null,
          ),

          // For result steps: two-step hint flow
          if (isResultStep && !_hintContinueClicked)
            _buildEducationalHint(
              _getResultMessage(state, l10n),
              icon: Icons.emoji_events_outlined,
              onContinue: () => setState(() => _hintContinueClicked = true),
            ),
          if (isResultStep && _hintContinueClicked)
            _buildEducationalHint(
              l10n.tutorialResultTapTabHint(_getPhaseTabLabel(state)),
              icon: Icons.touch_app_outlined,
            ),

          // Content based on toggle
          _showPreviousWinner && showPreviousWinnerTab
              ? _buildPreviousWinnerPanel(state, isEducationalStep: isEducationalStep)
              : _buildCurrentPhasePanel(state),
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
    } else if (state.currentStep == TutorialStep.round2Result) {
      final userProp = state.userProposition2 ?? l10n.tutorialYourIdea;
      return l10n.tutorialRound2Result(userProp);
    }
    return '';
  }

  void _handleResultContinue(TutorialChatState state) {
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);

    if (state.currentStep == TutorialStep.round1Result) {
      setState(() {
        _phaseTabUnlocked = true;
        _showPreviousWinner = false;
        _hintContinueClicked = false;
      });
      notifier.continueToRound2();
    } else if (state.currentStep == TutorialStep.round2Result) {
      // Round 3 - go directly to proposing (single click, no carry forward step)
      setState(() {
        _phaseTabUnlocked = true;
        _showPreviousWinner = false;
        _hintContinueClicked = false;
      });
      notifier.continueToRound3();
    }
  }

  Widget _buildToggleTabs(TutorialChatState state, bool hasPreviousWinner, {
    bool isPhaseTabHighlighted = false,
    bool isPhaseTabLocked = false,
    VoidCallback? onPhaseTabAction,
  }) {
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
          // Current Phase Tab (highlighted during result/educational steps)
          Expanded(
            child: GestureDetector(
              onTap: isPhaseTabLocked
                  ? null
                  : onPhaseTabAction ?? (hasPreviousWinner
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
                child: isPhaseTabHighlighted
                    ? _PulsingTabLabel(
                        label: _getPhaseTabLabel(state),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                        highlightColor: theme.colorScheme.primary,
                      )
                    : Text(
                        _getPhaseTabLabel(state),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight:
                              !isFirstSelected ? FontWeight.bold : FontWeight.normal,
                          color: !isFirstSelected
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
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

    // Show "See All Results" button when we have results
    final showResultsButton = translatedResults != null && translatedResults.isNotEmpty;

    // Determine round number from winner's roundId (-1=Round 1, -2=Round 2, -3=Round 3)
    final previousRoundNumber = winnerRoundId != null ? -winnerRoundId : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Educational hint: two-step flow
        if (showEducationalContent && !_hintContinueClicked)
          _buildEducationalHint(
            _getEducationalMessage(state, l10n),
            icon: Icons.tips_and_updates_outlined,
            onContinue: () => setState(() => _hintContinueClicked = true),
          ),
        if (showEducationalContent && _hintContinueClicked)
          _buildEducationalHint(
            l10n.tutorialTapTabHint(_getPhaseTabLabel(state)),
            icon: Icons.touch_app_outlined,
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
        ),
      ],
    );
  }

  String _getEducationalMessage(TutorialChatState state, AppLocalizations l10n) {
    if (state.currentStep == TutorialStep.round2Prompt) {
      final templateKey = state.selectedTemplate;
      if (templateKey != null && templateKey != 'classic') {
        final winner = _translateProposition(
          TutorialData.round1WinnerForTemplate(templateKey), l10n);
        return l10n.tutorialRound2PromptSimplifiedTemplate(winner);
      }
      return l10n.tutorialRound2PromptSimplified;
    }
    return '';
  }

  void _handleEducationalContinue() {
    setState(() {
      _phaseTabUnlocked = true;
      _showPreviousWinner = false;
      _hintContinueClicked = false;
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
        // Show proposing hint only for Round 1 when user hasn't submitted yet
        final isFirstRound = state.currentRound?.customId == 1;
        final showProposingHint = state.myPropositions.isEmpty && isFirstRound;
        final isRound2Prompt = state.currentStep == TutorialStep.round2Prompt;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProposingHint)
              _buildEducationalHintWithCountdown(
                l10n.tutorialProposingHint,
                state.currentRound!.phaseEndsAt!,
              ),
            if (isRound2Prompt)
              _buildEducationalHint(
                _getEducationalMessage(state, l10n),
                icon: Icons.tips_and_updates_outlined,
              ),
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
        final isFirstRound = state.currentRound?.customId == 1;
        final showRatingHint = isFirstRound && !state.hasStartedRating && !state.hasRated;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showRatingHint)
              _buildEducationalHintWithCountdown(
                l10n.tutorialRatingPhaseExplanation,
                state.currentRound!.phaseEndsAt!,
                timeTemplate: (time) => l10n.tutorialRatingTimeRemaining(time),
              ),
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
          onSelect: (templateKey) {
            notifier.selectTemplate(templateKey);
          },
          onSkip: _handleSkip,
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
  final bool isRound2;

  const _TutorialRatingScreen({
    required this.propositions,
    required this.onComplete,
    this.showHints = false,
    this.isRound2 = false,
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
          // Round 2: only show carry-forward hint when positioning starts
          if (!widget.showHints && widget.isRound2 && _currentPhase == RatingPhase.positioning)
            _buildHint(context, l10n.tutorialRatingCarryForwardHint),
          Expanded(
            child: RatingWidget(
              propositions: propsForRating,
              onRankingComplete: (_) => widget.onComplete(),
              lazyLoadingMode: false,
              isResuming: false,
              onPhaseChanged: (widget.showHints || widget.isRound2)
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

/// Educational hint with a live countdown as a second sentence.
class _TutorialProposingHint extends StatefulWidget {
  final String text;
  final DateTime endsAt;
  final String Function(String time) timeRemainingTemplate;

  const _TutorialProposingHint({
    required this.text,
    required this.endsAt,
    required this.timeRemainingTemplate,
  });

  @override
  State<_TutorialProposingHint> createState() => _TutorialProposingHintState();
}

class _TutorialProposingHintState extends State<_TutorialProposingHint> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    final remaining = widget.endsAt.difference(DateTime.now());
    if (mounted) {
      setState(() {
        _remaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.colorScheme.primaryContainer.withAlpha(100);
    final borderColor = theme.colorScheme.primary.withAlpha(80);
    final contentColor = theme.colorScheme.onPrimaryContainer;
    final timeText = widget.timeRemainingTemplate(_formatDuration(_remaining));

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
            Icons.lightbulb_outline,
            size: 20,
            color: contentColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${widget.text} $timeText',
              style: theme.textTheme.bodySmall?.copyWith(
                color: contentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsing tab label — text with a pulsing underline bar to draw attention.
class _PulsingTabLabel extends StatefulWidget {
  final String label;
  final TextStyle? style;
  final Color highlightColor;

  const _PulsingTabLabel({
    required this.label,
    required this.highlightColor,
    this.style,
  });

  @override
  State<_PulsingTabLabel> createState() => _PulsingTabLabelState();
}

class _PulsingTabLabelState extends State<_PulsingTabLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: widget.style,
            ),
            const SizedBox(height: 2),
            Container(
              height: 3,
              width: 40,
              decoration: BoxDecoration(
                color: widget.highlightColor.withAlpha(
                  (80 + 175 * _controller.value).toInt(),
                ),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        );
      },
    );
  }
}
