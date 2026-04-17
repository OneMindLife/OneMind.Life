import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/env_config.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../config/app_colors.dart';
import '../../models/models.dart';
import '../../widgets/message_card.dart';
import '../../widgets/proposition_content_card.dart';
import '../../widgets/qr_code_share.dart';
import '../../widgets/positioning_controls_demo.dart';
import '../../widgets/rating_controls_demo.dart';
import '../../widgets/round_phase_bar.dart';
import '../../widgets/round_winner_item.dart';
import '../../providers/providers.dart';
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

/// Calculate finger animation start position: 80px from target toward screen center.
Offset fingerStartPos(Offset target, Size screenSize) {
  final center = Offset(screenSize.width / 2, screenSize.height / 2);
  final direction = center - target;
  final distance = direction.distance;
  if (distance < 1) return Offset(target.dx, target.dy + 80);
  final normalized = direction / distance;
  return target + normalized * 80;
}

/// Build rich text replacing [proposing] and [rating] markers with inline phase chips.
/// Used across tutorial widgets (chat tour, leaderboard overlay).
Widget buildPhaseChipRichText(String text, AppLocalizations l10n, BuildContext context) {
  final theme = Theme.of(context);
  final spans = <InlineSpan>[];
  final markers = {
    '[proposing]': (AppColors.proposing, l10n.proposing),
    '[rating]': (AppColors.rating, l10n.rating),
  };
  var remaining = text;
  while (remaining.isNotEmpty) {
    int earliest = remaining.length;
    String? foundMarker;
    for (final m in markers.keys) {
      final idx = remaining.indexOf(m);
      if (idx != -1 && idx < earliest) {
        earliest = idx;
        foundMarker = m;
      }
    }
    if (foundMarker == null) {
      spans.add(TextSpan(text: remaining));
      break;
    }
    if (earliest > 0) spans.add(TextSpan(text: remaining.substring(0, earliest)));
    final (color, label) = markers[foundMarker]!;
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.white, fontWeight: FontWeight.bold,
        )),
      ),
    ));
    remaining = remaining.substring(earliest + foundMarker.length);
  }
  return Text.rich(TextSpan(style: theme.textTheme.bodyMedium, children: spans));
}

/// Provider for tutorial chat state (new version using real ChatScreen layout)
/// Uses autoDispose so state resets when tutorial screen is closed
final tutorialChatNotifierProvider = StateNotifierProvider.autoDispose<
    TutorialChatNotifier, TutorialChatState>((ref) {
  final analytics = ref.watch(analyticsServiceProvider);
  return TutorialChatNotifier(analytics: analytics);
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
  final bool skipIntro;

  const TutorialScreen({
    super.key,
    this.onComplete,
    this.onSkip,
    this.skipIntro = false,
  });

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen>
    with TickerProviderStateMixin {
  final _propositionController = TextEditingController();
  final _propositionFocusNode = FocusNode();

  // Chat tour: GlobalKeys for measuring widget positions
  final _tourBodyStackKey = GlobalKey();
  final _tourTooltipKey = GlobalKey();
  final _tourTitleKey = GlobalKey();
  final _tourMessageKey = GlobalKey();
  final _tourPlaceholderKey = GlobalKey();
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

  // convergenceContinue staged fade-in
  bool _ccPlaceholderReady = false;
  bool _ccDialogReady = false;

  // Track if tutorial completion is in progress (show loading, block back)
  bool _isCompleting = false;

  // Floating hint overlay: track dismissed hints and bottom area height
  final Set<String> _dismissedHints = {};
  String? _lastActiveHintId;
  final GlobalKey _bottomAreaKey = GlobalKey();
  final GlobalKey _winnerPanelKey = GlobalKey();
  final GlobalKey _mainStackKey = GlobalKey();
  final GlobalKey _shareButtonKey = GlobalKey();
  double _bottomAreaHeight = 200; // reasonable default
  double? _winnerPanelBottom; // measured bottom edge of winner panel in stack

  // Guards to prevent double-opening screens on auto-transitions
  bool _hasAutoOpenedRound1Results = false;
  bool _hasAutoOpenedRound2Rating = false;
  bool _hasAutoOpenedRound2Results = false;
  bool _hasAutoOpenedRound3Rating = false;

  // Share demo: finger → tap → QR dialog → close
  // 0=idle, 1=finger animating, 2=tap hint, 3=QR open
  int _shareDemoStep = 0;
  late final AnimationController _shareFingerController;
  bool _shareFingerDone = false;
  OverlayEntry? _shareOverlay;

  // Fresh timer start times — set when timer unfreezes so it starts from full 5min
  DateTime? _ratingTimerStart;
  DateTime? _proposingTimerStart;

  // Transition animation: fade out chat → show transition message → continue
  late final AnimationController _transitionController;
  bool _showTransitionScreen = false;

  // Intro → chat tour transition animation
  late final AnimationController _introFadeController;
  bool _introFadingOut = false;  // true while intro fades out
  bool _chatTourFadingIn = false;  // true while chat tour fades in (title + X only)
  bool _chatTourTooltipReady = false;  // true after chat tour fade-in, tooltip can appear

  // Tooltip fade controller — handles sequential fade-out → fade-in between steps
  late final AnimationController _tooltipFadeController;
  bool _tooltipTransitioning = false;

  // Floating hint fade controller — sequential fade-out → fade-in between hints
  late final AnimationController _hintFadeController;
  bool _hintTransitioning = false;

  // Participants finger animation
  late final AnimationController _participantsFingerController;
  bool _participantsFingerDone = false;

  // Convergence finger animation (tap consensus card)
  late final AnimationController _convergenceFingerController;
  bool _convergenceFingerDone = false;
  int _convergenceDialogStep = 0; // 0=first dialog, 1=finger, 2=second dialog
  bool _submitTooltipReady = false;

  // Chat tour phases sub-step: 0=both chips, 1=only proposing
  int _phasesSubStep = 0;

  // Chat tour placeholder sub-step: 0=card only (no text), 1=text fades in
  int _placeholderSubStep = 0;

  // Chat tour progress sub-step: 0=explain, 1=animate to 100%
  int _progressSubStep = 0;


  // R1 result flow: placeholder highlight → cycle history
  late final AnimationController _r1ResultFingerController;
  int _r1ResultDialogStep = 0; // 0=winner dialog, 1=finger, 2=tap dialog
  bool _r1ResultFingerDone = false;

  // R2 result flow: "You Won!" → cycle history → results
  bool _r2ResultHintReady = false;
  late final AnimationController _r2ResultFingerController;
  int _r2ResultDialogStep = 0; // 0=winner dialog, 1=finger, 2=tap dialog
  bool _r2ResultFingerDone = false;

  // Frozen timer: shows ~5:00, stored once so it doesn't reset on rebuild
  late final DateTime _frozenTimerEnd = DateTime.now().add(const Duration(minutes: 5, seconds: 1));

  // Guard against double-tap opening multiple leaderboard sheets
  bool _isLeaderboardSheetOpen = false;

  // Leaderboard tour progressive-reveal step (persists across sheet rebuilds)
  final _leaderboardTourStep = ValueNotifier<int>(-1);

  // Post-R1 leaderboard reveal
  // 0=idle, 1=finger animating, 2=tap hint showing, 3=sheet open
  int _r1LeaderboardStep = 0;
  late final AnimationController _r1LeaderboardFingerController;
  bool _r1LeaderboardFingerDone = false;

  @override
  void initState() {
    super.initState();
    TutorialTts.preload(); // Preload timing JSONs before first dialog
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _transitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showTransitionScreen = true);
      }
    });
    _introFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _tooltipFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1.0, // start fully visible
    );
    _hintFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );
    _participantsFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _convergenceFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _r1ResultFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _r2ResultFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _r1LeaderboardFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _shareFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Reset tutorial state so a fresh screen always starts from intro.
    // This handles Android back button + re-open: Riverpod provider state
    // survives across navigations but widget-local flags (_chatTourTooltipReady
    // etc.) reset to defaults, causing a mismatch where the chat tour UI
    // renders without the tooltip or TTS.
    // Deferred to post-frame because StateNotifier can't be mutated during build.
    if (!widget.skipIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final currentStep = ref.read(tutorialChatNotifierProvider).currentStep;
          // Only reset if we're still on the intro (play) screen.
          // If the widget remounts mid-tour (router rebuild), don't reset.
          if (currentStep == TutorialStep.intro) {
            ref.read(tutorialChatNotifierProvider.notifier).resetTutorial();
          } else {
            // Restore widget-local state for resumed tour
            _chatTourTooltipReady = true;
            _chatTourFadingIn = false;
            _introFadeController.value = 1.0;
            setState(() {});
          }
        }
      });
    }

    // Skip the intro/play button — select template immediately so
    // the first frame never shows the play button, then replicate the
    // staged fade: chat name fades in first, then tooltip after.
    if (widget.skipIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_chatTourFadingIn) return;
        ref.read(tutorialChatNotifierProvider.notifier).selectTemplate('saturday');
        // Fade in full screen, then dim and show intro dialog
        setState(() {
          _chatTourFadingIn = true;
          _chatTourTooltipReady = false;
        });
        _introFadeController.reset();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          _introFadeController.forward().then((_) {
            if (!mounted) return;
            setState(() => _chatTourFadingIn = false);
            Future.delayed(const Duration(milliseconds: 400), () {
              if (!mounted) return;
              _tooltipFadeController.value = 0.0;
              setState(() => _chatTourTooltipReady = true);
              _tooltipFadeController.forward();
            });
          });
        });
      });
    }
  }

  @override
  void dispose() {
    TutorialTts.stop('line248');
    _transitionController.dispose();
    _participantsFingerController.dispose();
    _convergenceFingerController.dispose();
    _r1ResultFingerController.dispose();
    _r2ResultFingerController.dispose();
    _r1LeaderboardFingerController.dispose();
    _shareFingerController.dispose();
    _shareOverlay?.remove();
    _introFadeController.dispose();
    _tooltipFadeController.dispose();
    _hintFadeController.dispose();
    _propositionController.dispose();
    _propositionFocusNode.dispose();
    _leaderboardTourStep.dispose();
    super.dispose();
  }

  /// Animate intro → chat tour: fade out intro, select template, fade in chat tour, then show tooltip
  void _startIntroToChatTourTransition(String templateKey, {bool skipFadeOut = false}) {
    if (_introFadingOut) return; // guard against double-tap

    // When coming from HTML play screen, skip the intro fade-out entirely
    // (the HTML overlay was covering the Flutter intro, so no need to animate it away)
    if (skipFadeOut) {
      ref.read(tutorialChatNotifierProvider.notifier).selectTemplate(templateKey);
      setState(() {
        _chatTourFadingIn = true;
        _chatTourTooltipReady = false;
      });
      _introFadeController.reset();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _introFadeController.forward().then((_) {
          if (!mounted) return;
          setState(() => _chatTourFadingIn = false);
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            _tooltipFadeController.value = 0.0;
            setState(() => _chatTourTooltipReady = true);
            _tooltipFadeController.forward();
          });
        });
      });
      return;
    }

    setState(() => _introFadingOut = true);
    _introFadeController.forward().then((_) {
      if (!mounted) return;
      // Select template (switches step to chatTourIntro)
      ref.read(tutorialChatNotifierProvider.notifier).selectTemplate(templateKey);
      setState(() {
        _introFadingOut = false;
        _chatTourFadingIn = true;
        _chatTourTooltipReady = false;
      });
      // Fade in full chat screen, then dim and show intro dialog
      _introFadeController.reset();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _introFadeController.forward().then((_) {
          if (!mounted) return;
          // Dim the screen first (no tooltip yet)
          setState(() => _chatTourFadingIn = false);
          // Pause so user absorbs the dimmed screen before dialog appears
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            _tooltipFadeController.value = 0.0;
            setState(() => _chatTourTooltipReady = true);
            _tooltipFadeController.forward();
          });
        });
      });
    });
  }

  /// Fade out tooltip → advance step → fade in new tooltip
  void _advanceChatTourStep() {
    if (_tooltipTransitioning) return;
    final currentStep = ref.read(tutorialChatNotifierProvider).currentStep;

    // Phases step sub-step: first dialog shows both chips, second shows only proposing
    if (currentStep == TutorialStep.chatTourPhases && _phasesSubStep == 0) {
      setState(() => _tooltipTransitioning = true);
      _tooltipFadeController.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _phasesSubStep = 1;
          _tooltipTransitioning = false;
        });
        _tooltipFadeController.forward();
      });
      return;
    }

    // Placeholder step sub-step: first shows card, second fades in text
    if (currentStep == TutorialStep.chatTourPlaceholder && _placeholderSubStep == 0) {
      setState(() => _tooltipTransitioning = true);
      _tooltipFadeController.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _placeholderSubStep = 1;
          _tooltipTransitioning = false;
        });
        _tooltipFadeController.forward();
      });
      return;
    }

    // Progress step sub-step: first explains, second animates to 100%
    if (currentStep == TutorialStep.chatTourProgress && _progressSubStep == 0) {
      setState(() => _tooltipTransitioning = true);
      _tooltipFadeController.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _progressSubStep = 1;
          _tooltipTransitioning = false;
        });
        _tooltipFadeController.forward();
      });
      return;
    }

    setState(() => _tooltipTransitioning = true);
    // Fade out
    _tooltipFadeController.reverse().then((_) {
      if (!mounted) return;
      // Advance the step (notifier triggers rebuild with new opacity values)
      ref.read(tutorialChatNotifierProvider.notifier).nextChatTourStep();
      setState(() => _tooltipTransitioning = false);

      // For participants step: play finger animation first, then show tooltip
      final nextStep = ref.read(tutorialChatNotifierProvider).currentStep;
      if (nextStep == TutorialStep.chatTourParticipants) {
        setState(() => _participantsFingerDone = false);
        _participantsFingerController.reset();
        _participantsFingerController.forward().then((_) {
          if (!mounted) return;
          setState(() => _participantsFingerDone = true);
          _tooltipFadeController.value = 0.0;
          _tooltipFadeController.forward();
        });
      } else if (nextStep == TutorialStep.chatTourSubmit) {
        _submitTooltipReady = false;
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            setState(() => _submitTooltipReady = true);
            _tooltipFadeController.forward();
            _propositionFocusNode.requestFocus();
          }
        });
      } else {
        // Element appears first, then tooltip fades in after delay
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            _tooltipFadeController.forward();
          }
        });
      }
    });
  }

  /// Dismiss a floating hint with fade-out → fade-in animation.
  void _dismissHintAnimated(String hintId) {
    if (_hintTransitioning) return;
    TutorialTts.stop('line364');
    setState(() => _hintTransitioning = true);
    _hintFadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _dismissedHints.add(hintId);
        _hintTransitioning = false;
      });
      _hintFadeController.forward();
    });
  }

  void _handleSkip() {
    _showSkipConfirmation();
  }

  /// Show skip confirmation dialog in any context. Returns true if confirmed.
  /// Used by pushed screens (rating, results) to show the dialog locally
  /// instead of popping back to the tutorial screen first.
  static Future<bool> showSkipDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tutorialSkipConfirmTitle),
        content: Text(l10n.tutorialSkipConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tutorialSkipConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tutorialSkipConfirmYes),
          ),
        ],
      ),
    );
    return confirmed == true;
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

  /// Show round-by-round winners for the tutorial convergence.
  void _showTutorialCycleHistory(
    BuildContext context,
    TutorialChatState state,
    int convergenceNumber, {
    bool showOngoingPlaceholder = false,
    bool showConvergenceHint = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final templateKey = state.selectedTemplate;
    final userProp = state.userProposition2 ?? l10n.tutorialYourIdea;
    final r1Winner = TutorialData.round1WinnerForTemplate(templateKey);

    final allRounds = [
      {'number': 1, 'winners': [r1Winner]},
      {'number': 2, 'winners': [userProp]},
      {'number': 3, 'winners': [userProp]},
    ];

    // Completed rounds: current round - 1, unless current round has results too
    final currentRoundId = state.currentRound?.customId ?? 1;
    final currentRoundDone = state.hasRated ||
        state.currentStep == TutorialStep.round3Consensus ||
        state.currentStep == TutorialStep.convergenceContinue ||
        state.currentStep == TutorialStep.shareDemo ||
        state.currentStep == TutorialStep.complete;
    final completedRoundCount = currentRoundDone ? currentRoundId : currentRoundId - 1;
    final rounds = allRounds.take(completedRoundCount).toList();

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (_, __, ___) => _TutorialCycleHistoryPage(
          convergenceNumber: convergenceNumber,
          rounds: rounds,
          showOngoingPlaceholder: showOngoingPlaceholder,
          showConvergenceHint: showConvergenceHint,
          state: state,
          templateKey: templateKey,
          userProp: userProp,
          onSkip: _handleSkip,
        ),
      ),
    ).then((_) {
      // Advance to convergenceContinue only after cycle history is popped
      if (mounted && showConvergenceHint) {
        ref.read(tutorialChatNotifierProvider.notifier)
            .continueToConvergenceContinue();
      }
    });
  }

  OverlayEntry? _closeHintOverlay;

  void _showLeaderboardTourOverlay(GlobalKey closeButtonKey, ValueNotifier<int> tourStep) {
    // Guard against being called multiple times (sheet builder can rebuild)
    if (_closeHintOverlay != null) return;

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || !_isLeaderboardSheetOpen) return;
      if (_closeHintOverlay != null) return; // Double-check after delay

      _closeHintOverlay = OverlayEntry(
        builder: (overlayContext) => _LeaderboardTourOverlayWidget(
          closeButtonKey: closeButtonKey,
          tourStep: tourStep,
          onDismiss: () {
            _closeHintOverlay?.remove();
            _closeHintOverlay = null;
          },
        ),
      );
      Overlay.of(context).insert(_closeHintOverlay!);
    });
  }

  Future<void> _showTutorialParticipantsSheet() {
    final state = ref.read(tutorialChatNotifierProvider);
    final participants = TutorialData.allParticipants;
    final myParticipantId = state.myParticipant.id;
    final isChatTour = state.isChatTourStep;
    // No "Done" tags during chat tour — nobody has acted yet
    final isInPhase = !isChatTour &&
        (state.currentRound?.phase == RoundPhase.proposing ||
         state.currentRound?.phase == RoundPhase.rating);

    // Hardcoded rankings per round for tutorial
    // Round 1: no data yet (dash)
    // Round 2: Alex #1, You #2, Sam #3, Jordan #4
    // Round 3+: You #1, Alex #2, Sam #3, Jordan #4
    final roundId = state.currentRound?.customId ?? 1;
    final Map<int, String> rankings; // participant_id → rank display
    if (roundId <= 1) {
      // No rankings yet
      rankings = {for (final p in participants) p.id: '—'};
    } else if (roundId == 2) {
      // After R1: Alex won, user lost
      rankings = {
        -2: '#1',  // Alex
        myParticipantId: '#2',  // You
        -3: '#3',  // Sam
        -4: '#4',  // Jordan
      };
    } else {
      // After R2+: User won
      rankings = {
        myParticipantId: '#1',  // You
        -2: '#2',  // Alex
        -3: '#3',  // Sam
        -4: '#4',  // Jordan
      };
    }
    // Sort participants by rank
    final sortedParticipants = List<Participant>.from(participants)
      ..sort((a, b) {
        final ra = rankings[a.id] ?? '—';
        final rb = rankings[b.id] ?? '—';
        if (ra == '—' && rb == '—') return 0;
        if (ra == '—') return 1;
        if (rb == '—') return -1;
        return ra.compareTo(rb);
      });

    // Reset tour step for fresh progressive reveal
    _leaderboardTourStep.value = -1;

    return showModalBottomSheet(
      context: context,
      isDismissible: !isChatTour, // prevent dismissing by tapping outside during tour
      enableDrag: !isChatTour,    // prevent drag-to-dismiss during tour
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final sheetL10n = AppLocalizations.of(modalContext);

        final closeButtonKey = GlobalKey();

        final sheetContent = Column(
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
                  Icon(Icons.leaderboard, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${sheetL10n.leaderboard} (${participants.length})',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    key: closeButtonKey,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(modalContext),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Participants list (sorted by rank)
            ...sortedParticipants.map((p) {
              final isUser = p.id == myParticipantId;
              final hasActed = isInPhase && !isUser;
              final rank = rankings[p.id] ?? '—';
              return Opacity(
                opacity: hasActed || !isInPhase ? 1.0 : 0.5,
                child: ListTile(
                  leading: CircleAvatar(child: Text(rank)),
                  title: Text(p.displayName),
                  subtitle: hasActed
                      ? Text(
                          sheetL10n.done,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : null,
                  trailing: null,
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        );

        if (!isChatTour) return sheetContent;

        // Chat tour: use persistent ValueNotifier to control progressive reveal
        // Only init overlay on first build (not on sheet rebuilds)
        if (_leaderboardTourStep.value == -1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            _showLeaderboardTourOverlay(closeButtonKey, _leaderboardTourStep);
          });
        }

        return ValueListenableBuilder<int>(
          valueListenable: _leaderboardTourStep,
          builder: (_, step, __) {
            final showNames = step >= 0; // names fade in at step 0
            final showRanks = step >= 1; // ranks fade in at step 1
            final showDashes = step >= 2; // switch to dashes at step 2
            final showDone = step >= 3;  // "Done" tags on NPCs at step 3
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
                      Icon(Icons.leaderboard, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${sheetL10n.leaderboard} (${participants.length})',
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: step >= 5 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IgnorePointer(
                          ignoring: step < 6,
                          child: IconButton(
                            key: closeButtonKey,
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(modalContext),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ...sortedParticipants.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  final rank = showDashes ? '—' : '#${i + 1}';
                  return AnimatedOpacity(
                    opacity: showNames ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    child: ListTile(
                      leading: AnimatedOpacity(
                        opacity: showRanks ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: CircleAvatar(
                            key: ValueKey(rank),
                            child: Text(rank),
                          ),
                        ),
                      ),
                      title: Text(p.displayName),
                      subtitle: p.id != myParticipantId
                          ? AnimatedOpacity(
                              opacity: showDone ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 400),
                              child: Text(
                                sheetL10n.done,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : null,
                      trailing: null,
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            );
          },
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

  Widget _buildShareFingerOverlay() {
    // Find the share button by GlobalKey
    final shareBox = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (shareBox == null || !shareBox.attached) return const SizedBox.shrink();
    final targetPos = shareBox.localToGlobal(
      Offset(shareBox.size.width / 2, shareBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(targetPos, screenSize);

    return AnimatedBuilder(
      animation: _shareFingerController,
      builder: (context, _) {
        final t = _shareFingerController.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetPos, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          opacity = 1.0;
          pos = targetPos;
          scale = 0.78;
        } else if (t < 0.7) {
          opacity = 1.0;
          pos = targetPos;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = targetPos;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  void _startShareDemo() {
    if (_shareDemoStep != 0) return;
    setState(() {
      _shareDemoStep = 1;
      _shareFingerDone = false;
    });
    _shareFingerController.reset();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _shareFingerController.forward().then((_) {
        if (!mounted) return;
        setState(() {
          _shareFingerDone = true;
          _shareDemoStep = 2;
        });
        _hintFadeController.value = 0.0;
        _hintFadeController.forward();
      });
    });
  }

  void _onShareIconTap() {
    if (_shareDemoStep != 2) return;
    TutorialTts.stop('share_tap');
    _dismissedHints.add('share_tap');
    setState(() => _shareDemoStep = 3);

    final state = ref.read(tutorialChatNotifierProvider);
    final chatName = state.selectedTemplate != null
        ? TutorialData.chatNameForTemplate(state.selectedTemplate)
        : TutorialData.chatName;
    final l10n = AppLocalizations.of(context);

    final closeButtonKey = GlobalKey();
    final shareDialogKey = GlobalKey();
    final dialogStep = ValueNotifier<int>(-1);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<int>(
        valueListenable: dialogStep,
        builder: (context, step, _) => KeyedSubtree(
          key: shareDialogKey,
          child: QrCodeShareDialog(
            chatName: chatName,
            inviteCode: TutorialData.demoInviteCode,
            deepLinkUrl: '${EnvConfig.webAppUrl}/join/${TutorialData.demoInviteCode}',
            closeButtonKey: closeButtonKey,
            closeVisible: step >= 1,
            closeEnabled: step >= 2,
            onClose: () => Navigator.pop(dialogContext),
          ),
        ),
      ),
    ).then((_) {
      // Dialog closed — advance to complete
      _shareOverlay?.remove();
      _shareOverlay = null;
      if (mounted) {
        ref.read(tutorialChatNotifierProvider.notifier).completeTutorial();
      }
    });

    // Show overlay dialog after QR dialog settles
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _shareOverlay = OverlayEntry(
        builder: (overlayContext) => _ShareOverlayWidget(
          closeButtonKey: closeButtonKey,
          shareDialogKey: shareDialogKey,
          dialogStep: dialogStep,
          l10n: l10n,
        ),
      );
      Overlay.of(context).insert(_shareOverlay!);
      dialogStep.value = 0;
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

  void _skipRound3Proposing() {
    _dismissedHints.add('r3_replace');
    ref.read(tutorialChatNotifierProvider.notifier).beginRound3Rating();
  }

  void _openTutorialRatingScreen(TutorialChatState state) {
    // Dismiss rating button hint first (removes card from tree),
    // then stop TTS — prevents text disappearing before card does.
    if (!_dismissedHints.contains('r1_rating_button')) {
      _dismissedHints.add('r1_rating_button');
      setState(() {});
    }
    TutorialTts.stop('line818');
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);
    final l10n = AppLocalizations.of(context);
    // Delay markRatingStarted past the full fade transition (1200ms)
    // so the button text doesn't flash from "Start Rating" to "Continue Rating"
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) notifier.markRatingStarted();
    });

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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Sequential: old fades out (0→0.5), new fades in (0.5→1)
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (pushedContext, animation, secondaryAnimation) => _TutorialRatingScreen(
          propositions: translatedPropositions,
          showHints: state.currentStep == TutorialStep.round1Rating,
          carriedWinnerName: state.currentStep == TutorialStep.round2Rating
              ? _getR1WinnerText(state, AppLocalizations.of(pushedContext))
              : null,
          onExitTutorial: () async {
            final confirmed = await _TutorialScreenState.showSkipDialog(pushedContext);
            if (confirmed && pushedContext.mounted) {
              Navigator.pop(pushedContext);
              _handleSkip();
            }
          },
          onComplete: () {
            // Complete the rating
            final currentState = ref.read(tutorialChatNotifierProvider);
            if (currentState.currentStep == TutorialStep.round1Rating) {
              notifier.completeRound1Rating();
              // Pop back to chat screen — R1 result flow happens there
              Navigator.pop(context);
            } else if (currentState.currentStep == TutorialStep.round2Rating) {
              notifier.completeRound2Rating();
              // Pop back to chat screen — R2 result flow happens there
              Navigator.pop(context);
            } else if (currentState.currentStep == TutorialStep.round3Rating) {
              notifier.completeRound3Rating();
              // R3 goes to consensus, not results — just pop
              Navigator.pop(context, true);
            }
          },
        ),
      ),
    );
  }

  /// Push results screen replacing the rating screen (no chat screen flash).
  void _pushResultsReplacement(BuildContext ratingContext, TutorialChatState state) {
    final l10n = AppLocalizations.of(context);

    List<Proposition> results;
    int roundNumber;
    String? hintTitle;
    String? hintDescription;
    String? winnerName;

    if (state.currentStep == TutorialStep.round1Result) {
      results = state.round1Results;
      roundNumber = 1;
      winnerName = state.previousRoundWinners.isNotEmpty
          ? _translateProposition(state.previousRoundWinners.first.content ?? '', l10n)
          : '';
      hintTitle = l10n.tutorialHintRoundResults;
    } else if (state.currentStep == TutorialStep.round2Result) {
      results = state.round2Results;
      roundNumber = 2;
      hintTitle = l10n.tutorialHintYouWon;
      hintDescription = l10n.tutorialR2ResultsHint;
    } else {
      return;
    }

    final translatedResults = results.map((p) => Proposition(
      id: p.id,
      roundId: p.roundId,
      participantId: p.participantId,
      content: _translateProposition(p.content, l10n),
      finalRating: p.finalRating,
      createdAt: p.createdAt,
    )).toList();

    Navigator.pushReplacement(
      ratingContext,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (pushedContext, animation, secondaryAnimation) => ReadOnlyResultsScreen(
          propositions: translatedResults,
          roundNumber: roundNumber,
          roundId: -roundNumber,
          myParticipantId: -1,
          showTutorialHint: true,
          tutorialHintTitle: hintTitle,
          tutorialHintDescription: hintDescription,
          tutorialWinnerName: winnerName,
          onExitTutorial: () async {
            final confirmed = await _TutorialScreenState.showSkipDialog(pushedContext);
            if (confirmed && pushedContext.mounted) {
              Navigator.pop(pushedContext);
              _handleSkip();
            }
          },
        ),
      ),
    ).then((_) {
      // When R2 results screen is popped, advance to R3
      if (!mounted) return;
      final currentState = ref.read(tutorialChatNotifierProvider);
      if (currentState.currentStep == TutorialStep.round2Result) {
        ref.read(tutorialChatNotifierProvider.notifier).continueToRound3();
      }
    });
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Sequential: old fades out (0→0.5), new fades in (0.5→1)
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (pushedContext, animation, secondaryAnimation) => ReadOnlyResultsScreen(
          propositions: translatedResults,
          roundNumber: 1,
          roundId: -1,
          myParticipantId: -1,
          showTutorialHint: true,
          tutorialHintTitle: l10n.tutorialHintRoundResults,
          tutorialWinnerName: winnerName,
          onExitTutorial: () async {
            final confirmed = await _TutorialScreenState.showSkipDialog(pushedContext);
            if (confirmed && pushedContext.mounted) {
              Navigator.pop(pushedContext);
              _handleSkip();
            }
          },
        ),
      ),
    ).then((_) {
      // Auto-advance to Round 2 when results screen is dismissed
      if (mounted) {
        ref.read(tutorialChatNotifierProvider.notifier).continueToRound2();
        // Trigger fade-in for the first R2 hint
        _hintFadeController.value = 0.0;
        _hintFadeController.forward();
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Sequential: old fades out (0→0.5), new fades in (0.5→1)
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (pushedContext, animation, secondaryAnimation) => ReadOnlyResultsScreen(
          propositions: translatedResults,
          roundNumber: 2,
          roundId: -2,
          myParticipantId: -1,
          showTutorialHint: true,
          tutorialHintTitle: l10n.tutorialHintYouWon,
          tutorialHintDescription: l10n.tutorialR2ResultsHint,
          onExitTutorial: () async {
            final confirmed = await _TutorialScreenState.showSkipDialog(pushedContext);
            if (confirmed && pushedContext.mounted) {
              Navigator.pop(pushedContext);
              _handleSkip();
            }
          },
        ),
      ),
    ).then((_) {
      // Advance to Round 3 when results screen is dismissed
      if (mounted) {
        ref.read(tutorialChatNotifierProvider.notifier).continueToRound3();
        _hintFadeController.value = 0.0;
        _hintFadeController.forward();
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
      // R1 results: handled by _pushResultsReplacement from rating onComplete
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
      // R1 result: show placeholder highlight flow on chat screen
      if (prev?.currentStep != TutorialStep.round1Result &&
          next.currentStep == TutorialStep.round1Result) {
        setState(() {
          _r1ResultFingerDone = false;
          _r1ResultDialogStep = 0;
        });
        _r1ResultFingerController.reset();
        _hintFadeController.value = 0.0;
        _hintFadeController.forward();
      }
      // R2 result: show "You Won!" dialog then cycle history flow
      if (prev?.currentStep != TutorialStep.round2Result &&
          next.currentStep == TutorialStep.round2Result) {
        setState(() {
          _r2ResultHintReady = false;
          _r2ResultFingerDone = false;
          _r2ResultDialogStep = 0;
        });
        _r2ResultFingerController.reset();
        _hintFadeController.value = 0.0;
        _hintFadeController.forward();
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _r2ResultHintReady = true);
        });
      }
      // Convergence: show dialog 1 first, then finger, then dialog 2
      if (prev?.currentStep != TutorialStep.round3Consensus &&
          next.currentStep == TutorialStep.round3Consensus) {
        setState(() {
          _convergenceFingerDone = false;
          _convergenceDialogStep = 0; // Show first dialog immediately
        });
        _convergenceFingerController.reset();
      }
      // convergenceContinue: staged fade-in (delay → placeholder → dialog)
      if (prev?.currentStep != TutorialStep.convergenceContinue &&
          next.currentStep == TutorialStep.convergenceContinue) {
        setState(() {
          _ccPlaceholderReady = false;
          _ccDialogReady = false;
        });
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _ccPlaceholderReady = true);
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) setState(() => _ccDialogReady = true);
          });
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
    final activeHintForDim = _activeHintId(state);
    // Dim AppBar during spotlight hints
    final dimAppBar = (isEndTour)
        || activeHintForDim == 'r1_result_winner'
        || activeHintForDim == 'r1_result_finger'
        || activeHintForDim == 'r1_result_tap'
        || activeHintForDim == 'r2_winner'
        || activeHintForDim == 'r2_new_round'
        || activeHintForDim == 'r2_replace'
        || activeHintForDim == 'r2_result_won'
        || activeHintForDim == 'r2_result_finger'
        || activeHintForDim == 'r2_result_tap'
        || activeHintForDim == 'r3_intro'
        || activeHintForDim == 'r3_new_round'
        || activeHintForDim == 'r3_replace';
    // Dim title only (leaderboard icon stays bright) during leaderboard tap
    final dimTitle = dimAppBar || activeHintForDim == 'r1_leaderboard_tap';
    final dimOpacity = dimAppBar ? 0.25 : 1.0;
    final titleDimOpacity = dimTitle ? 0.25 : 1.0;
    // Bottom area: dim fully during winner hints/end-tour
    final bottomDimOpacity = isEndTour
        || activeHintForDim == 'r1_result_finger'
        || activeHintForDim == 'r1_result_tap'
        || activeHintForDim == 'r1_leaderboard_tap'
        || activeHintForDim == 'r2_winner'
        || activeHintForDim == 'r2_result_won'
        || activeHintForDim == 'r2_result_finger'
        || activeHintForDim == 'r2_result_tap'
        || activeHintForDim == 'r3_intro'
        ? 0.25 : 1.0;

    final l10n = AppLocalizations.of(context);
    final chatName = state.customQuestion != null
        ? l10n.tutorialAppBarTitle
        : state.selectedTemplate == null
            ? l10n.tutorialAppBarTitle
            : TutorialData.chatNameForTemplate(state.selectedTemplate);

    final scaffold = Scaffold(
      appBar: AppBar(
              automaticallyImplyLeading: false,
              title: AnimatedOpacity(
                opacity: titleDimOpacity,
                duration: const Duration(milliseconds: 250),
                child: Text(chatName),
              ),
              actions: [
                // Participants icon (after intro, matching chat tour)
                if (state.currentStep != TutorialStep.intro)
                  KeyedSubtree(
                    key: _tourParticipantsKey,
                    child: AnimatedOpacity(
                    opacity: dimOpacity,
                    duration: const Duration(milliseconds: 250),
                    child: AbsorbPointer(
                      absorbing: _r1LeaderboardStep == 1,
                      child: IconButton(
                        icon: const Icon(Icons.leaderboard),
                        tooltip: l10n.leaderboard,
                        onPressed: isEndTour ? null : () {
                          if (_r1LeaderboardStep == 2) {
                            _onR1LeaderboardIconTap();
                          } else {
                            _showTutorialParticipantsSheet();
                          }
                        },
                      ),
                    ),
                  ),
                  ),
                // Share icon (revealed at shareDemo and beyond)
                // Spotlighted during shareDemo, normal at complete
                if (showShareButton)
                  AnimatedOpacity(
                    opacity: state.currentStep == TutorialStep.shareDemo ? 1.0 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: AbsorbPointer(
                      absorbing: _shareDemoStep != 2, // Only tappable during share demo tap hint
                      child: Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context);
                        return IconButton(
                          key: _shareButtonKey,
                          icon: const Icon(Icons.ios_share),
                          tooltip: l10n.tutorialShareTooltip,
                          onPressed: _shareDemoStep == 2 ? _onShareIconTap : _showDemoQrCode,
                        );
                      },
                    ),
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
                        icon: const Icon(Icons.exit_to_app),
                        tooltip: l10n.tutorialSkipMenuItem,
                        onPressed: _handleSkip,
                      );
                    },
                  ),
                ),
              ],
            ),
      body: state.currentStep == TutorialStep.intro && !widget.skipIntro
          // Intro: full screen panel with fade-out animation
          ? FadeTransition(
              opacity: _introFadingOut
                  ? Tween<double>(begin: 1.0, end: 0.0).animate(_introFadeController)
                  : const AlwaysStoppedAnimation(1.0),
              child: _buildTutorialPanel(state),
            )
          // After template selection (or skipIntro): Stack with Column + floating hint overlay
          : _buildMainStack(state, dimOpacity, bottomDimOpacity, isEndTour, showTutorialPanel, activeHintForDim),
    );

    // R1 result finger animation overlay (taps winner panel)
    if (state.currentStep == TutorialStep.round1Result && _r1ResultDialogStep == 1) {
      return Stack(
        children: [
          scaffold,
          _buildWinnerPanelFingerOverlay(_r1ResultFingerController),
        ],
      );
    }

    // R2 result finger animation overlay (taps winner panel)
    if (state.currentStep == TutorialStep.round2Result && _r2ResultDialogStep == 1) {
      return Stack(
        children: [
          scaffold,
          _buildWinnerPanelFingerOverlay(_r2ResultFingerController),
        ],
      );
    }

    // Post-R1 leaderboard finger animation overlay (taps leaderboard icon)
    if (_r1LeaderboardStep == 1 && !_r1LeaderboardFingerDone) {
      return Stack(
        children: [
          scaffold,
          _buildR1LeaderboardFingerOverlay(),
        ],
      );
    }

    // Convergence finger animation overlay (above AppBar, like participants finger)
    if (state.currentStep == TutorialStep.round3Consensus && _convergenceDialogStep == 1) {
      return Stack(
        children: [
          scaffold,
          _buildConvergenceFingerOverlay(),
        ],
      );
    }

    // Share demo finger animation overlay
    if (state.currentStep == TutorialStep.shareDemo && _shareDemoStep == 1 && !_shareFingerDone) {
      return Stack(
        children: [
          scaffold,
          _buildShareFingerOverlay(),
        ],
      );
    }

    return scaffold;
  }

  /// Build the main content as a Stack: Column layout + floating hint overlay.
  Widget _buildMainStack(
    TutorialChatState state,
    double dimOpacity,
    double bottomDimOpacity,
    bool isEndTour,
    bool showTutorialPanel,
    String? activeHintForDim,
  ) {
    // Measure bottom area height after layout for hint positioning
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _measureBottomArea();
        _measureWinnerPanel();
      }
    });

    return Stack(
      key: _mainStackKey,
      children: [
        // Layer 0: existing Column layout (unchanged)
        Column(
          children: [
            // Phase-aware accent strip — always in tree to prevent layout shift,
            // fades in when proposing phase first appears.
            // Bright during r1_rating_phase (explaining phase change), dimmed during other hints.
            AnimatedOpacity(
              opacity: state.currentRound?.phase == null ? 0.0
                  : (activeHintForDim != null && activeHintForDim != 'r1_rating_phase' && activeHintForDim != 'r1_rating_button') ? 0.25
                  : 1.0,
              duration: const Duration(milliseconds: 300),
              child: PhaseAccentStrip(phase: state.currentRound?.phase ?? RoundPhase.proposing),
            ),

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

                      final tutorialMessageChildren = [
                          Center(
                            child: KeyedSubtree(
                              key: _tourMessageKey,
                              child: AnimatedOpacity(
                                opacity: state.currentStep == TutorialStep.round3Consensus
                                    ? 1.0
                                    : state.currentStep == TutorialStep.convergenceContinue
                                        ? (_ccPlaceholderReady ? 1.0 : 0.0)
                                        : dimOpacity,
                                duration: const Duration(milliseconds: 250),
                                child: MessageCard(
                                  label: l10n.initialMessage,
                                  content: initialMessage,
                                  isPrimary: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...state.consensusItems.asMap().entries.map((entry) {
                            final isSpotlighted =
                                state.currentStep == TutorialStep.round3Consensus ||
                                (state.currentStep == TutorialStep.convergenceContinue && _ccPlaceholderReady);
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
                                    child: AbsorbPointer(
                                      absorbing: state.currentStep == TutorialStep.round3Consensus && _convergenceDialogStep == 1,
                                      child: GestureDetector(
                                      onTap: () {
                                        final isConsensusStep =
                                            state.currentStep == TutorialStep.round3Consensus;
                                        // Open cycle history (continueToConvergenceContinue
                                        // is called in .then() when cycle history is popped)
                                        _showTutorialCycleHistory(
                                          context, state, entry.key + 1,
                                          showConvergenceHint: isConsensusStep,
                                        );
                                      },
                                      child: MessageCard(
                                        label: l10n.consensusNumber(entry.key + 1),
                                        content: entry.value.displayContent,
                                        isPrimary: true,
                                        isConsensus: true,
                                      ),
                                    ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),

                          // Inline Previous Winner or placeholder
                          if (!_isEndTourStep(state.currentStep) ||
                              state.currentStep == TutorialStep.convergenceContinue ||
                              state.currentStep == TutorialStep.shareDemo)
                            AnimatedOpacity(
                              opacity: state.currentStep == TutorialStep.convergenceContinue
                                  ? (_ccPlaceholderReady ? 1.0 : 0.0)
                                  : state.currentStep == TutorialStep.shareDemo
                                      ? 0.25
                                      : 1.0,
                              duration: const Duration(milliseconds: 400),
                              child: state.previousRoundWinners.isNotEmpty
                                  ? KeyedSubtree(
                                      key: _winnerPanelKey,
                                      child: _buildTutorialWinnerPanel(state),
                                    )
                                  : KeyedSubtree(
                                      key: _winnerPanelKey,
                                      child: _buildTopCandidatePlaceholder(),
                                    ),
                            ),
                      ];

                      // Per-element dimming based on active hint
                      final activeHint = _activeHintId(state);
                      final dimMessages = activeHint == 'r1_rating_phase' ||
                          activeHint == 'r1_rating_button';
                      final isConvergenceContinue =
                          state.currentStep == TutorialStep.convergenceContinue;
                      final dimAll = activeHint == 'r1_leaderboard_tap';
                      final spotlightWinner = activeHint == 'r1_result_winner' ||
                          activeHint == 'r1_result_finger' ||
                          activeHint == 'r1_result_tap' ||
                          activeHint == 'r2_result_finger' ||
                          activeHint == 'r2_result_tap' ||
                          activeHint == 'r2_winner' ||
                          activeHint == 'r2_replace' ||
                          activeHint == 'r2_result_won' ||
                          activeHint == 'r3_intro' ||
                          activeHint == 'r3_replace' ||
                          isConvergenceContinue;
                      final dimAllMessages = activeHint == 'r2_new_round' ||
                          activeHint == 'r3_new_round';

                      // Wrap each child with appropriate opacity
                      final dimmedChildren = tutorialMessageChildren.map((child) {
                        // During r2_winner or r2_replace, only the winner panel stays bright
                        if (spotlightWinner) {
                          // Check if child is the winner panel (may be wrapped in AnimatedOpacity)
                          final isWinnerPanel = (child is KeyedSubtree &&
                              child.key == _winnerPanelKey) ||
                              (child is AnimatedOpacity &&
                               child.child is KeyedSubtree &&
                               (child.child as KeyedSubtree).key == _winnerPanelKey);
                          return AnimatedOpacity(
                            opacity: isWinnerPanel ? 1.0 : 0.25,
                            duration: const Duration(milliseconds: 250),
                            child: child,
                          );
                        }
                        // Dim everything (all messages + winner panel)
                        if (dimAll) {
                          return AnimatedOpacity(
                            opacity: 0.25,
                            duration: const Duration(milliseconds: 250),
                            child: child,
                          );
                        }
                        return child;
                      }).toList();

                      return AnimatedOpacity(
                        opacity: (dimMessages || dimAllMessages) ? 0.25 : 1.0,
                        duration: const Duration(milliseconds: 250),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              children: dimmedChildren,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (isEndTour && _endTourMeasured &&
                      (state.currentStep != TutorialStep.round3Consensus || _convergenceDialogStep != 1) &&
                      (state.currentStep != TutorialStep.convergenceContinue || _ccDialogReady))
                    _buildEndTourTooltip(state),
                ],
              ),
            ),

            // Bottom Area - dimmed during end tour / r2_winner, self-managed otherwise
            Flexible(
              flex: 0,
              child: KeyedSubtree(
                key: _bottomAreaKey,
                child: AbsorbPointer(
                  absorbing: activeHintForDim != null && activeHintForDim != 'r1_rating_button',
                  child: AnimatedOpacity(
                    opacity: bottomDimOpacity,
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
  /// When tooltip is fading out, current element dims to 0.25 with it.
  double _chatTourOpacity(TutorialStep current, TutorialStep target) {
    // Intro step: full opacity throughout (dialog overlays, no dimming)
    if (current == TutorialStep.chatTourIntro) return 1.0;
    // Submit step: only text field is bright, everything else dimmed.
    // During tooltip transition out (about to leave chat tour), restore all to 1.0.
    if (current == TutorialStep.chatTourSubmit) {
      if (_tooltipTransitioning) return 1.0; // seamless exit
      if (target == TutorialStep.chatTourSubmit) return 1.0; // text field
      return 0.25; // everything else dimmed
    }
    if (current.index < target.index) return 0.0;
    if (current == target) {
      return _tooltipTransitioning ? 0.25 : 1.0;
    }
    return 0.25;
  }

  void _updateChatTourTooltipPosition() {
    final state = ref.read(tutorialChatNotifierProvider);
    final stackBox =
        _tourBodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    double newTop;

    switch (state.currentStep) {
      case TutorialStep.chatTourIntro:
        // Center at ~40% from top — avoids measurement jitter
        newTop = stackBox.size.height * 0.35;
      case TutorialStep.chatTourTitle:
        // Just below AppBar
        newTop = 8;
      case TutorialStep.chatTourMessage:
        final targetBox =
            _tourMessageKey.currentContext?.findRenderObject() as RenderBox?;
        if (targetBox == null) return;
        final pos = targetBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = pos.dy + targetBox.size.height + 12;
      case TutorialStep.chatTourPlaceholder:
        final placeholderBox =
            _tourPlaceholderKey.currentContext?.findRenderObject() as RenderBox?;
        if (placeholderBox == null) return;
        final placeholderPos =
            placeholderBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = placeholderPos.dy + placeholderBox.size.height + 12;
      case TutorialStep.chatTourParticipants:
        // Just below AppBar (leaderboard button is in the app bar)
        newTop = 8;
      case TutorialStep.chatTourRound:
      case TutorialStep.chatTourPhases:
      case TutorialStep.chatTourProgress:
      case TutorialStep.chatTourTimer:
        // Above the status bar
        final barBox =
            _tourProposingKey.currentContext?.findRenderObject() as RenderBox?;
        if (barBox == null) return;
        final barPos =
            barBox.localToGlobal(Offset.zero, ancestor: stackBox);
        final tooltipBoxB =
            _tourTooltipKey.currentContext?.findRenderObject() as RenderBox?;
        final tooltipHB = tooltipBoxB?.size.height ?? 180;
        newTop = barPos.dy - tooltipHB - 12;
      case TutorialStep.chatTourSubmit:
        // Same position as proposing (above the bottom area)
        final submitBox =
            _tourProposingKey.currentContext?.findRenderObject() as RenderBox?;
        if (submitBox == null) return;
        final submitPos =
            submitBox.localToGlobal(Offset.zero, ancestor: stackBox);
        final tooltipBoxS =
            _tourTooltipKey.currentContext?.findRenderObject() as RenderBox?;
        final tooltipHS = tooltipBoxS?.size.height ?? 180;
        newTop = submitPos.dy - tooltipHS - 12;
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
    Widget? tourDescriptionWidget;
    switch (step) {
      case TutorialStep.chatTourIntro:
        tourTitle = l10n.chatTourIntroTitle;
        tourDescription = l10n.chatTourIntroDesc;
      case TutorialStep.chatTourTitle:
        tourTitle = l10n.chatTourTitleTitle;
        tourDescription = l10n.chatTourTitleDesc;
      case TutorialStep.chatTourParticipants:
        tourTitle = l10n.chatTourParticipantsTitle;
        tourDescription = l10n.chatTourParticipantsDesc;
        // Replace [leaderboard] marker with inline icon
        final desc = l10n.chatTourParticipantsDesc;
        final parts = desc.split('[leaderboard]');
        if (parts.length == 2) {
          tourDescriptionWidget = Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(text: parts[0]),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Icons.leaderboard,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                TextSpan(text: parts[1]),
              ],
            ),
          );
        }
      case TutorialStep.chatTourMessage:
        tourTitle = l10n.chatTourMessageTitle;
        tourDescription = l10n.chatTourMessageDesc;
      case TutorialStep.chatTourPlaceholder:
        tourTitle = l10n.chatTourPlaceholderTitle;
        tourDescription = _placeholderSubStep == 0
            ? l10n.chatTourPlaceholderDesc
            : l10n.chatTourPlaceholderDesc2;
      case TutorialStep.chatTourRound:
        tourTitle = l10n.chatTourRoundTitle;
        tourDescription = l10n.chatTourRoundDesc;
      case TutorialStep.chatTourPhases:
        tourTitle = l10n.chatTourPhasesTitle;
        final phasesRichDesc = _phasesSubStep == 0
            ? l10n.chatTourPhasesDesc
            : l10n.chatTourPhasesDesc2;
        // TTS-friendly
        tourDescription = phasesRichDesc
            .replaceAll('[proposing]', l10n.proposing)
            .replaceAll('[rating]', l10n.rating);
        tourDescriptionWidget = buildPhaseChipRichText(phasesRichDesc, l10n, context);
      case TutorialStep.chatTourProgress:
        tourTitle = l10n.chatTourProgressTitle;
        tourDescription = _progressSubStep == 0
            ? l10n.chatTourProgressDesc
            : l10n.chatTourProgressDesc2;
      case TutorialStep.chatTourTimer:
        tourTitle = l10n.chatTourTimerTitle;
        tourDescription = l10n.chatTourTimerDesc;
      case TutorialStep.chatTourSubmit:
        tourTitle = l10n.chatTourSubmitTitle;
        tourDescription = l10n.chatTourSubmitDesc;
      default:
        tourTitle = '';
        tourDescription = '';
    }

    final isLastStep =
        state.chatTourStepIndex == TutorialChatState.chatTourTotalSteps - 1;

    // Whether the tooltip should be visible (hidden during fade-in and intro pre-dim)
    final showTooltip = _chatTourTooltipReady &&
        !_chatTourFadingIn &&
        (step != TutorialStep.chatTourTitle || _chatTourTooltipReady) &&
        !(step == TutorialStep.chatTourParticipants && !_participantsFingerDone) &&
        !(step == TutorialStep.chatTourSubmit && !_submitTooltipReady);

    final scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: KeyedSubtree(
          key: _tourTitleKey,
          child: _chatTourFadingIn
              ? FadeTransition(
                  opacity: _introFadeController,
                  child: Text(chatName),
                )
              : AnimatedOpacity(
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
              child: AbsorbPointer(
                absorbing: (step == TutorialStep.chatTourParticipants && !_participantsFingerDone)
                    || (_r1LeaderboardStep == 1), // Block during finger animation
                child: IconButton(
                  icon: const Icon(Icons.leaderboard),
                  tooltip: l10n.leaderboard,
                  onPressed: () {
                  // R1 leaderboard reveal: user taps icon after prompt
                  if (_r1LeaderboardStep == 2) {
                    _onR1LeaderboardIconTap();
                    return;
                  }
                  // Guard against double-tap opening multiple sheets
                  if (_isLeaderboardSheetOpen) return;
                  _isLeaderboardSheetOpen = true;
                  // Stop any playing TTS and fade out tooltip
                  TutorialTts.stop('line1776');
                  _tooltipFadeController.reverse();
                  _showTutorialParticipantsSheet().then((_) {
                    _isLeaderboardSheetOpen = false;
                    // Remove close hint overlay if still showing
                    _closeHintOverlay?.remove();
                    _closeHintOverlay = null;
                    // Auto-advance after sheet closes during chat tour
                    if (mounted) {
                      final s = ref.read(tutorialChatNotifierProvider);
                      if (s.currentStep == TutorialStep.chatTourParticipants) {
                        _advanceChatTourStep();
                      }
                    }
                  });
                },
              ),
              ),
            ),
          ),
          // Skip/close button (shown immediately, before chat name fades in)
          if (_chatTourFadingIn)
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: l10n.tutorialSkipMenuItem,
              onPressed: _handleSkip,
            )
          else
            AnimatedOpacity(
              opacity: (step == TutorialStep.chatTourSubmit && _tooltipTransitioning) ? 1.0 : 0.25,
              duration: const Duration(milliseconds: 250),
              child: IconButton(
                icon: const Icon(Icons.exit_to_app),
                tooltip: l10n.tutorialSkipMenuItem,
                onPressed: _handleSkip,
              ),
            ),
        ],
      ),
      body: SizedBox.expand(
        child: Stack(
          key: _tourBodyStackKey,
          children: [
            // Layer 1: Progressively revealed content
            Positioned.fill(
              child: FadeTransition(
                opacity: _introFadeController,
                child: Column(
                children: [
                  // Phase accent strip — fades in at chatTourPhases sub-step 1,
                  // bright during phases step, dimmed during later steps,
                  // restored to 1.0 only at final step transition for seamless scaffold swap
                  AnimatedOpacity(
                    opacity: step.index < TutorialStep.chatTourPhases.index
                        || (step == TutorialStep.chatTourPhases && _phasesSubStep == 0)
                        ? 0.0
                        : (step == TutorialStep.chatTourPhases && _phasesSubStep == 1)
                            || (step == TutorialStep.chatTourSubmit && _tooltipTransitioning)
                            ? 1.0
                            : 0.25,
                    duration: const Duration(milliseconds: 300),
                    child: PhaseAccentStrip(phase: RoundPhase.proposing),
                  ),
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
                  // Placeholder for current top candidate
                  KeyedSubtree(
                    key: _tourPlaceholderKey,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: AnimatedOpacity(
                        opacity: step == TutorialStep.chatTourPlaceholder ||
                                step == TutorialStep.chatTourSubmit
                            ? 1.0
                            : _chatTourOpacity(step, TutorialStep.chatTourPlaceholder),
                      duration: const Duration(milliseconds: 250),
                      child: PropositionContentCard(
                        content: '...',
                        label: l10n.chatTourPlaceholderTitle,
                        contentOpacity: step == TutorialStep.chatTourPlaceholder && _placeholderSubStep == 0
                            ? 0.0 : 1.0,
                        borderColor: AppColors.consensus,
                        glowColor: AppColors.consensus,
                      ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Round phase status bar (progressive reveal per section)
                  KeyedSubtree(
                    key: _tourProposingKey,
                    child: RoundPhaseBar(
                      roundNumber: 1,
                      isProposing: true,
                      // Intro: show full bar (timer + progress). Otherwise progressive reveal.
                      phaseEndsAt: step == TutorialStep.chatTourIntro
                          || step.index >= TutorialStep.chatTourTimer.index
                          ? TutorialData.round1().phaseEndsAt : null,
                      reserveSpace: true,
                      reservePhaseEndsAt: TutorialData.round1().phaseEndsAt,
                      frozenTimer: true,
                      frozenTimerDuration: const Duration(minutes: 5),
                      participationPercent:
                          step == TutorialStep.chatTourIntro
                              ? 0
                              : step.index >= TutorialStep.chatTourProgress.index
                                  ? (step == TutorialStep.chatTourProgress && _progressSubStep == 1 ? 100 : 0)
                                  : null,
                      animateProgress: step == TutorialStep.chatTourProgress && _progressSubStep == 1,
                      // Intro: single phase chip (proposing only). Tour: both chips before phases step.
                      showInactivePhase: step != TutorialStep.chatTourIntro
                          && (step.index < TutorialStep.chatTourPhases.index
                              || (step == TutorialStep.chatTourPhases && _phasesSubStep == 0)),
                      highlightAllPhases: step == TutorialStep.chatTourPhases && _phasesSubStep == 0,
                      roundOpacity: _chatTourOpacity(
                          step, TutorialStep.chatTourRound),
                      phasesOpacity: _chatTourOpacity(
                          step, TutorialStep.chatTourPhases),
                      progressOpacity: step == TutorialStep.chatTourProgress
                          ? 1.0 : null,
                      timerOpacity: _chatTourOpacity(
                          step, TutorialStep.chatTourTimer),
                    ),
                  ),
                  // Text field (submit area — no phase bar, shown separately above)
                  AnimatedOpacity(
                    opacity: _chatTourOpacity(
                        step, TutorialStep.chatTourSubmit),
                    duration: const Duration(milliseconds: 250),
                    child: AbsorbPointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ProposingStatePanel(
                          roundCustomId: 1,
                          propositionsPerUser: 1,
                          myPropositions: const [],
                          propositionController: _propositionController,
                          focusNode: _propositionFocusNode,
                          onSubmit: () {},
                          phaseEndsAt: TutorialData.round1().phaseEndsAt,
                          onPhaseExpired: () {},
                          showPhaseBar: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
            // Layer 2: Tooltip overlay — fades out/in between steps
            if ((_tourMeasured || step == TutorialStep.chatTourIntro) && showTooltip)
              Positioned(
                left: 16,
                right: 16,
                top: _tourTooltipTop,
                child: FadeTransition(
                  opacity: _tooltipFadeController,
                  child: NotificationListener<SizeChangedLayoutNotification>(
                    onNotification: (_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _updateChatTourTooltipPosition();
                      });
                      return true;
                    },
                    child: SizeChangedLayoutNotifier(
                      child: KeyedSubtree(
                        key: _tourTooltipKey,
                        child: step == TutorialStep.chatTourParticipants
                          // No button — user taps the icon in AppBar
                          ? NoButtonTtsCard(title: tourTitle, description: tourDescription, descriptionWidget: tourDescriptionWidget)
                          : TourTooltipCard(
                          title: tourTitle,
                          description: tourDescription,
                          descriptionWidget: tourDescriptionWidget,
                          onNext: _advanceChatTourStep,
                          onSkip: () => notifier.skipChatTour(),
                          stepIndex: state.chatTourStepIndex,
                          totalSteps: TutorialChatState.chatTourTotalSteps,
                          nextLabel: isLastStep
                              ? l10n.homeTourFinish
                              : l10n.homeTourNext,
                          autoAdvance: true,
                          skipLabel: l10n.homeTourSkip,
                          stepOfLabel: l10n.homeTourStepOf(
                            state.chatTourStepIndex + 1,
                            TutorialChatState.chatTourTotalSteps,
                          ),
                          skipResetOnDescriptionChange: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Layer 3: Participants finger animation
          ],
        ),
      ),
    );

    // Wrap scaffold in Stack for finger overlay (needs to render above AppBar)
    if (step == TutorialStep.chatTourParticipants && !_participantsFingerDone) {
      return Stack(
        children: [
          scaffold,
          _buildParticipantsFingerOverlay(),
        ],
      );
    }

    return scaffold;
  }

  /// Finger animation pointing at and tapping the participants button.
  Widget _buildParticipantsFingerOverlay() {
    final participantsBox =
        _tourParticipantsKey.currentContext?.findRenderObject() as RenderBox?;
    if (participantsBox == null) return const SizedBox.shrink();

    // Use global screen coordinates since overlay is above AppBar
    final buttonGlobal = participantsBox.localToGlobal(
      Offset(participantsBox.size.width / 2, participantsBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(buttonGlobal, screenSize);
    final buttonPos = buttonGlobal;

    return AnimatedBuilder(
      animation: _participantsFingerController,
      builder: (context, _) {
        final t = _participantsFingerController.value;
        // Timeline: 0-0.2 fade in, 0.2-0.5 glide to button, 0.5-0.6 tap, 0.6-0.7 release, 0.7-1.0 fade out
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          // Fade in at start position
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          // Glide to button
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, buttonPos, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          // Press
          opacity = 1.0;
          pos = buttonPos;
          scale = 0.78;
        } else if (t < 0.7) {
          // Release
          opacity = 1.0;
          pos = buttonPos;
          scale = 1.0;
        } else {
          // Fade out
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = buttonPos;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Finger animation pointing at and tapping the convergence consensus card.
  Widget _buildWinnerPanelFingerOverlay(AnimationController controller) {
    final winnerBox =
        _winnerPanelKey.currentContext?.findRenderObject() as RenderBox?;
    if (winnerBox == null) return const SizedBox.shrink();

    final cardGlobal = winnerBox.localToGlobal(
      Offset(winnerBox.size.width / 2, winnerBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(cardGlobal, screenSize);
    final targetPos = cardGlobal;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetPos, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          opacity = 1.0;
          pos = targetPos;
          scale = 0.78;
        } else if (t < 0.7) {
          opacity = 1.0;
          pos = targetPos;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = targetPos;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConvergenceFingerOverlay() {
    final consensusBox =
        _consensusCardKey.currentContext?.findRenderObject() as RenderBox?;
    if (consensusBox == null) return const SizedBox.shrink();

    final cardGlobal = consensusBox.localToGlobal(
      Offset(consensusBox.size.width / 2, consensusBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(cardGlobal, screenSize);
    final targetPos = cardGlobal;

    return AnimatedBuilder(
      animation: _convergenceFingerController,
      builder: (context, _) {
        final t = _convergenceFingerController.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetPos, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          opacity = 1.0;
          pos = targetPos;
          scale = 0.78;
        } else if (t < 0.7) {
          opacity = 1.0;
          pos = targetPos;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = targetPos;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  // === Floating Hint Overlay ===

  /// Determine which hint (if any) should be shown for the current state.
  /// Returns null if no hint is active or it has been dismissed.
  String? _activeHintId(TutorialChatState state) {
    final step = state.currentStep;
    final round = state.currentRound;

    // R1 result: placeholder highlight flow
    if (step == TutorialStep.round1Result) {
      if (_r1ResultDialogStep == 0) {
        const id = 'r1_result_winner';
        if (!_dismissedHints.contains(id)) return id;
      }
      // Step 1 = finger animation (dim only, no dialog)
      if (_r1ResultDialogStep == 1 && _r1LeaderboardStep == 0) {
        return 'r1_result_finger';
      }
      // Step 2 = tap dialog
      if (_r1ResultDialogStep >= 2 && _r1LeaderboardStep == 0) {
        const id = 'r1_result_tap';
        if (!_dismissedHints.contains(id)) return id;
      }
      if (_r1LeaderboardStep == 2) {
        return 'r1_leaderboard_tap';
      }
    }

    // R2 result: "You Won!" → finger → tap → cycle history
    if (step == TutorialStep.round2Result) {
      if (_r2ResultDialogStep == 0 && _r2ResultHintReady) {
        const id = 'r2_result_won';
        if (!_dismissedHints.contains(id)) return id;
      }
      // Step 1 = finger animation (dim only, no dialog)
      if (_r2ResultDialogStep == 1) {
        return 'r2_result_finger';
      }
      // Step 2 = tap dialog
      if (_r2ResultDialogStep >= 2) {
        const id = 'r2_result_tap';
        if (!_dismissedHints.contains(id)) return id;
      }
    }

    // R2 sequential hints: new round → replace winner (r2_winner dropped, explained in R1)
    if ((step == TutorialStep.round2Prompt || step == TutorialStep.round2Proposing) &&
        state.previousRoundWinners.isNotEmpty &&
        state.myPropositions.isEmpty) {
      const id1 = 'r2_new_round';
      if (!_dismissedHints.contains(id1)) return id1;
      const id3 = 'r2_replace';
      if (!_dismissedHints.contains(id3)) return id3;
    }

    // R3 sequential hints: new round → replace winner (r3_intro dropped, merged into R2 result)
    if (step == TutorialStep.round3Proposing &&
        round?.customId == 3 &&
        state.myPropositions.isEmpty &&
        state.previousRoundWinners.isNotEmpty) {
      const id2 = 'r3_new_round';
      if (!_dismissedHints.contains(id2)) return id2;
      const id3 = 'r3_replace';
      if (!_dismissedHints.contains(id3)) return id3;
    }

    // R1 rating phase hint: explains phase changed to rating
    if (round?.phase == RoundPhase.rating &&
        round?.customId == 1 &&
        !state.hasStartedRating &&
        !state.hasRated) {
      const id = 'r1_rating_phase';
      if (!_dismissedHints.contains(id)) return id;
      // R1 rating button hint: instructs to click Start Rating
      const id2 = 'r1_rating_button';
      if (!_dismissedHints.contains(id2)) return id2;
    }

    // Share demo tap hint
    if (step == TutorialStep.shareDemo && _shareDemoStep == 2) {
      return 'share_tap';
    }

    return null;
  }

  /// Build the floating hint overlay as a Positioned TourTooltipCard.
  Widget _buildFloatingHint(TutorialChatState state) {
    final hintId = _activeHintId(state);
    if (hintId == null) {
      _lastActiveHintId = null;
      return const SizedBox.shrink();
    }

    // Fade in when a new hint first appears
    if (hintId != _lastActiveHintId && !_hintTransitioning) {
      _lastActiveHintId = hintId;
      _hintFadeController.value = 0.0;
      _hintFadeController.forward();
    }

    final l10n = AppLocalizations.of(context);

    final String title;
    final String description;
    Widget? descriptionWidget;

    switch (hintId) {
      case 'r1_result_winner':
        title = l10n.tutorialR1ResultWinnerTitle;
        description = l10n.tutorialR1ResultWinnerDesc;
      case 'r1_result_tap':
        title = l10n.tutorialR1ResultTapTitle;
        description = l10n.tutorialR1ResultTapDesc;
      case 'r1_leaderboard_tap':
        title = l10n.leaderboard;
        description = l10n.tutorialR1LeaderboardTapDesc;
        final lbParts = description.split('[leaderboard]');
        if (lbParts.length >= 2) {
          final spans = <InlineSpan>[];
          for (var i = 0; i < lbParts.length; i++) {
            if (lbParts[i].isNotEmpty) spans.add(TextSpan(text: lbParts[i]));
            if (i < lbParts.length - 1) {
              spans.add(WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.leaderboard, size: 18,
                    color: Theme.of(context).colorScheme.onSurface),
              ));
            }
          }
          descriptionWidget = Text.rich(
            TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: spans),
          );
        }
      case 'r2_winner':
        final winner = _getR1WinnerText(state, l10n);
        title = l10n.tutorialHintR1Winner;
        description = l10n.tutorialHintR1WinnerDesc(winner);
      case 'r2_new_round':
        title = l10n.tutorialHintNewRound;
        description = l10n.tutorialHintNewRoundDesc;
      case 'r2_replace':
        title = l10n.tutorialHintReplaceWinner;
        description = l10n.tutorialHintReplaceWinnerDesc;
      case 'r2_result_won':
        title = l10n.tutorialHintYouWon;
        description = l10n.tutorialR2ResultsHint;
      case 'r2_result_tap':
        title = l10n.tutorialR1ResultTapTitle;
        description = l10n.tutorialR1ResultTapDesc;
      case 'r3_intro':
        title = l10n.tutorialHintYouWon;
        final userWinner = state.userProposition2 ?? '';
        final r1Winner = _translateProposition(
          TutorialData.round1WinnerForTemplate(state.selectedTemplate), l10n);
        description = l10n.tutorialRound3PromptTemplate(userWinner, r1Winner);
      case 'r3_new_round':
        title = l10n.tutorialHintNewRound3;
        description = l10n.tutorialHintNewRound3Desc;
      case 'r3_replace':
        title = l10n.tutorialHintR3Replace;
        description = l10n.tutorialHintR3ReplaceDesc;
        // Render [skip] as inline skip_next icon
        final descText = l10n.tutorialHintR3ReplaceDesc;
        final skipParts = descText.split('[skip]');
        if (skipParts.length >= 2) {
          final spans = <InlineSpan>[];
          for (var i = 0; i < skipParts.length; i++) {
            if (skipParts[i].isNotEmpty) {
              spans.add(TextSpan(text: skipParts[i]));
            }
            if (i < skipParts.length - 1) {
              spans.add(WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: AbsorbPointer(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton.filled(
                      onPressed: () {},
                      icon: const Icon(Icons.skip_next, size: 22),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ));
            }
          }
          descriptionWidget = Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: spans,
            ),
          );
        }
      case 'share_tap':
        title = l10n.tutorialShareTitle;
        description = l10n.tutorialShareTapDesc;
      case 'r1_rating_phase':
        title = l10n.tutorialRatingPhaseTitle;
        description = l10n.tutorialRatingPhaseHint;
      case 'r1_rating_button':
        title = l10n.tutorialHintRateIdeas;
        description = l10n.tutorialRatingButtonHint; // TTS-friendly
        final btnDesc = l10n.tutorialRatingButtonHintRich;
        final btnParts = btnDesc.split('[startRating]');
        if (btnParts.length >= 2) {
          final btnSpans = <InlineSpan>[];
          for (var i = 0; i < btnParts.length; i++) {
            if (btnParts[i].isNotEmpty) btnSpans.add(TextSpan(text: btnParts[i]));
            if (i < btnParts.length - 1) {
              btnSpans.add(WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: AbsorbPointer(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.how_to_vote_outlined, size: 20),
                    label: Text(l10n.startRating),
                  ),
                ),
              ));
            }
          }
          descriptionWidget = Text.rich(
            TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: btnSpans),
          );
        }
      default:
        return const SizedBox.shrink();
    }

    // Hints that instruct user to tap something: no button, NoButtonTtsCard
    final isActionHint = hintId == 'r1_rating_button'
        || hintId == 'r1_result_tap' || hintId == 'r2_result_tap'
        || hintId == 'r1_leaderboard_tap' || hintId == 'share_tap';

    // R1 result winner: custom onNext to start finger animation
    final isR1ResultWinner = hintId == 'r1_result_winner';

    final tooltipCard = FadeTransition(
      key: ValueKey('hintFade_$hintId'),
      opacity: _hintFadeController,
      child: isActionHint
          ? NoButtonTtsCard(title: title, description: description, descriptionWidget: descriptionWidget)
          : GestureDetector(
              onTap: () {
                if (isR1ResultWinner) {
                  _startR1ResultFingerAnimation();
                } else {
                  _dismissHintAnimated(hintId);
                }
              },
              child: TourTooltipCard(
                title: title,
                description: description,
                descriptionWidget: descriptionWidget,
                onNext: () {
                  if (isR1ResultWinner) {
                    _startR1ResultFingerAnimation();
                  } else if (hintId == 'r2_result_won') {
                    _startR2ResultFingerAnimation();
                  } else {
                    _dismissHintAnimated(hintId);
                  }
                },
                onSkip: _handleSkip,
                stepIndex: 0,
                totalSteps: 0,
                nextLabel: (hintId == 'r2_replace' || hintId == 'r3_replace')
                    ? l10n.homeTourFinish
                    : l10n.homeTourNext,
                autoAdvance: true,
                skipLabel: l10n.tutorialSkipMenuItem,
                stepOfLabel: '',
              ),
            ),
    );

    // Position hint based on type
    if ((hintId == 'r1_result_winner' || hintId == 'r1_result_tap'
        || hintId == 'r2_result_won' || hintId == 'r2_result_tap') &&
        _winnerPanelBottom != null) {
      return Positioned(
        left: 16,
        right: 16,
        top: _winnerPanelBottom!,
        child: tooltipCard,
      );
    }
    if (hintId == 'r1_leaderboard_tap' || hintId == 'share_tap') {
      // Below the app bar, near the icon
      return Positioned(
        left: 16,
        right: 16,
        top: 8,
        child: tooltipCard,
      );
    }
    if ((hintId == 'r2_winner' || hintId == 'r3_intro') &&
        _winnerPanelBottom != null) {
      // Right below the placeholder/winner panel
      return Positioned(
        left: 16,
        right: 16,
        top: _winnerPanelBottom!,
        child: tooltipCard,
      );
    }
    if (hintId == 'r2_new_round') {
      // Above the bottom area (near the round phase bar)
      return Positioned(
        left: 16,
        right: 16,
        bottom: _bottomAreaHeight + 8,
        child: tooltipCard,
      );
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: _bottomAreaHeight + 8,
      child: tooltipCard,
    );
  }


  void _startR1ResultFingerAnimation() {
    setState(() => _r1ResultDialogStep = 1);
    _dismissedHints.add('r1_result_winner');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _r1ResultFingerController.forward().then((_) {
          if (mounted) {
            setState(() {
              _r1ResultFingerDone = true;
              _r1ResultDialogStep = 2;
            });
            _hintFadeController.value = 0.0;
            _hintFadeController.forward();
          }
        });
      }
    });
  }

  void _startR2ResultFingerAnimation() {
    setState(() => _r2ResultDialogStep = 1);
    _dismissedHints.add('r2_result_won');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _r2ResultFingerController.forward().then((_) {
          if (mounted) {
            setState(() {
              _r2ResultFingerDone = true;
              _r2ResultDialogStep = 2;
            });
            _hintFadeController.value = 0.0;
            _hintFadeController.forward();
          }
        });
      }
    });
  }

  void _showR2CycleHistory(BuildContext context, TutorialChatState state) {
    _dismissedHints.add('r2_result_tap');
    final l10n = AppLocalizations.of(context);
    final templateKey = state.selectedTemplate;
    final r1Winner = _translateProposition(
      TutorialData.round1WinnerForTemplate(templateKey), l10n);
    final userProp = state.userProposition2 ?? 'My idea';

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (_, __, ___) => _TutorialR2CycleHistoryPage(
          r1Winner: r1Winner,
          r2Winner: userProp,
          userProp1: state.userProposition1 ?? 'My idea',
          userProp2: userProp,
          templateKey: templateKey,
          onSkip: _handleSkip,
        ),
      ),
    ).then((_) {
      // When cycle history is popped, advance to Round 3
      if (mounted) {
        ref.read(tutorialChatNotifierProvider.notifier).continueToRound3();
        _hintFadeController.value = 0.0;
        _hintFadeController.forward();
      }
    });
  }

  void _showR1CycleHistory(BuildContext context, TutorialChatState state) {
    _dismissedHints.add('r1_result_tap');
    final l10n = AppLocalizations.of(context);
    final templateKey = state.selectedTemplate;
    final r1Winner = _translateProposition(
      TutorialData.round1WinnerForTemplate(templateKey), l10n);
    final userProp1 = state.userProposition1 ?? 'My idea';

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (_, __, ___) => _TutorialR1CycleHistoryPage(
          r1Winner: r1Winner,
          userProp1: userProp1,
          templateKey: templateKey,
          onSkip: _handleSkip,
        ),
      ),
    ).then((_) {
      // When cycle history is popped, show leaderboard reveal before R2
      if (mounted) {
        _startR1LeaderboardReveal();
      }
    });
  }

  Widget _buildR1LeaderboardFingerOverlay() {
    final iconBox =
        _tourParticipantsKey.currentContext?.findRenderObject() as RenderBox?;
    if (iconBox == null) return const SizedBox.shrink();

    final iconGlobal = iconBox.localToGlobal(
      Offset(iconBox.size.width / 2, iconBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(iconGlobal, screenSize);

    return AnimatedBuilder(
      animation: _r1LeaderboardFingerController,
      builder: (context, _) {
        final t = _r1LeaderboardFingerController.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, iconGlobal, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          opacity = 1.0;
          pos = iconGlobal;
          scale = 0.78;
        } else if (t < 0.7) {
          opacity = 1.0;
          pos = iconGlobal;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = iconGlobal;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  void _startR1LeaderboardReveal() {
    setState(() {
      _r1LeaderboardStep = 1;
      _r1LeaderboardFingerDone = false;
    });
    _r1LeaderboardFingerController.reset();
    // Brief delay before finger starts
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _r1LeaderboardFingerController.forward().then((_) {
        if (!mounted) return;
        setState(() {
          _r1LeaderboardFingerDone = true;
          _r1LeaderboardStep = 2;
        });
        _hintFadeController.value = 0.0;
        _hintFadeController.forward();
      });
    });
  }

  void _onR1LeaderboardIconTap() {
    if (_r1LeaderboardStep != 2) return;
    if (_isLeaderboardSheetOpen) return;
    _isLeaderboardSheetOpen = true;
    TutorialTts.stop('line2684');
    _dismissedHints.add('r1_leaderboard_tap');
    setState(() => _r1LeaderboardStep = 3);
    _showR1LeaderboardSheet();
  }

  OverlayEntry? _r1LeaderboardOverlay;

  void _showR1LeaderboardSheet() {
    final state = ref.read(tutorialChatNotifierProvider);
    final participants = TutorialData.allParticipants;
    final myParticipantId = state.myParticipant.id;
    final l10n = AppLocalizations.of(context);

    // R1 rankings: Alex #1 (winner), user #2, Sam #3, Jordan #4
    final rankings = <int, String>{
      -2: '#1',  // Alex
      myParticipantId: '#2',
      -3: '#3',
      -4: '#4',
    };
    final sortedParticipants = List<Participant>.from(participants)
      ..sort((a, b) {
        final ra = rankings[a.id] ?? '—';
        final rb = rankings[b.id] ?? '—';
        if (ra == '—' && rb == '—') return 0;
        if (ra == '—') return 1;
        if (rb == '—') return -1;
        return ra.compareTo(rb);
      });

    final closeButtonKey = GlobalKey();
    // 0=explain dialog, 1=transition, 2=done dialog, 3=dismissed
    final dialogStep = ValueNotifier<int>(-1);

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final sheetL10n = AppLocalizations.of(modalContext);

        return ValueListenableBuilder<int>(
          valueListenable: dialogStep,
          builder: (context, step, _) {
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
                      Icon(Icons.leaderboard, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${sheetL10n.leaderboard} (${participants.length})',
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: step >= 1 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IgnorePointer(
                          ignoring: step < 2,
                          child: IconButton(
                            key: closeButtonKey,
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(modalContext),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Participants list with rankings
                ...sortedParticipants.map((p) {
                  final rank = rankings[p.id] ?? '—';
                  return ListTile(
                    leading: CircleAvatar(child: Text(rank)),
                    title: Text(p.displayName),
                    trailing: null,
                  );
                }),
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Remove overlay and advance to Round 2
      _isLeaderboardSheetOpen = false;
      _r1LeaderboardOverlay?.remove();
      _r1LeaderboardOverlay = null;
      if (mounted) {
        setState(() => _r1LeaderboardStep = 0);
        _hintFadeController.value = 0.0;
        // Small delay so sheet dismissal animation completes before hint fades in
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          ref.read(tutorialChatNotifierProvider.notifier).continueToRound2();
          // Delay hint fade so textfield + status bar settle first
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) _hintFadeController.forward();
          });
        });
      }
    });

    // Show overlay dialogs above the sheet (delay so sheet settles)
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted || !_isLeaderboardSheetOpen) return;
      _r1LeaderboardOverlay = OverlayEntry(
        builder: (overlayContext) => _R1LeaderboardOverlayWidget(
          closeButtonKey: closeButtonKey,
          dialogStep: dialogStep,
          l10n: l10n,
        ),
      );
      Overlay.of(context).insert(_r1LeaderboardOverlay!);
      dialogStep.value = 0;
    });
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

  /// Measure the winner panel's bottom edge relative to the main stack.
  void _measureWinnerPanel() {
    final winnerBox =
        _winnerPanelKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox =
        _mainStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (winnerBox == null || stackBox == null) return;
    final pos = winnerBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final bottom = pos.dy + winnerBox.size.height + 12;
    if (_winnerPanelBottom == null || (bottom - _winnerPanelBottom!).abs() > 1) {
      setState(() => _winnerPanelBottom = bottom);
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
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);
    final userProp = state.userProposition2 ?? l10n.tutorialYourIdea;

    final String title;
    final String description;
    final int stepIndex;
    final VoidCallback onNext;
    final String nextLabel;

    if (state.currentStep == TutorialStep.round3Consensus) {
      if (_convergenceDialogStep == 0) {
        // Dialog 1: won 2 rounds, added permanently
        title = l10n.tutorialConsensusReached;
        description = l10n.tutorialWonTwoRounds;
        return Positioned(
          left: 16,
          right: 16,
          top: _endTourTooltipTop,
          child: TourTooltipCard(
            key: const ValueKey('consensus_dialog1'),
            title: title,
            description: description,
            onNext: () {
              // Start finger animation, then show dialog 2
              setState(() => _convergenceDialogStep = 1);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _convergenceFingerController.forward().then((_) {
                    if (mounted) {
                      setState(() {
                        _convergenceFingerDone = true;
                        _convergenceDialogStep = 2;
                      });
                    }
                  });
                }
              });
            },
            onSkip: _handleSkip,
            stepIndex: 0,
            totalSteps: 2,
            nextLabel: l10n.homeTourNext,
            skipLabel: l10n.tutorialSkipMenuItem,
            stepOfLabel: '',
          ),
        );
      } else if (_convergenceDialogStep == 2) {
        // Dialog 2: convergence explanation — no button, tap card
        title = l10n.tutorialConsensusReached;
        description = l10n.tutorialConvergenceExplain;
        return Positioned(
          left: 16,
          right: 16,
          top: _endTourTooltipTop,
          child: NoButtonTtsCard(key: const ValueKey('consensus_dialog2'), title: title, description: description),
        );
      } else {
        // Step 1: finger animation playing, no dialog
        return const SizedBox.shrink();
      }
    } else if (state.currentStep == TutorialStep.convergenceContinue) {
      title = l10n.tutorialProcessContinuesTitle;
      description = l10n.tutorialProcessContinuesDesc;
      stepIndex = 1;
      onNext = () => notifier.continueToShareDemo();
      nextLabel = l10n.continue_;
    } else {
      // shareDemo — handled by _shareDemoStep state machine, no static tooltip
      if (_shareDemoStep == 0) {
        _startShareDemo();
      }
      return const SizedBox.shrink();
    }

    // convergenceContinue: below the placeholder card
    if (state.currentStep == TutorialStep.convergenceContinue &&
        _winnerPanelBottom != null) {
      return Positioned(
        left: 16,
        right: 16,
        top: _winnerPanelBottom!,
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
        key: ValueKey('endTour_${state.currentStep}'),
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
            icon: const Icon(Icons.exit_to_app),
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
                  duration: const Duration(milliseconds: 300),
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
                      FilledButton.icon(
                        onPressed: _handleComplete,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(l10n.continue_),
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
    final activeHint = _activeHintId(state);
    final isNewRoundHint = activeHint == 'r2_new_round' ||
        activeHint == 'r3_new_round';
    final isReplaceHint = activeHint == 'r2_replace' ||
        activeHint == 'r3_replace';

    // During new_round / replace hints: split RoundPhaseBar from panel
    // so each can have independent opacity
    if ((isNewRoundHint || isReplaceHint) &&
        state.currentRound?.phase == RoundPhase.proposing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // RoundPhaseBar: bright during r2_new_round, dim during r2_replace
          AnimatedOpacity(
            opacity: isNewRoundHint ? 1.0 : 0.25,
            duration: const Duration(milliseconds: 250),
            child: Builder(builder: (_) {
              // Show 0% during hints, animate to 75% after both hints dismissed
              final pct = (isNewRoundHint || isReplaceHint) ? 0
                  : state.participants.isNotEmpty
                      ? (((state.participants.length - 1) + (state.myPropositions.where((p) => !p.isCarriedForward).isNotEmpty ? 1 : 0)) * 100 /
                          state.participants.length).round()
                      : 0;
              // Freeze timer during hints, start fresh 5min countdown after dismiss
              final useRealTimer = !isNewRoundHint && !isReplaceHint;
              if (isNewRoundHint) _proposingTimerStart = null; // Reset for new round
              if (useRealTimer && _proposingTimerStart == null) {
                _proposingTimerStart = DateTime.now().add(const Duration(minutes: 5));
              }
              return RoundPhaseBar(
                roundNumber: state.currentRound!.customId,
                isProposing: true,
                phaseEndsAt: useRealTimer
                    ? _proposingTimerStart!
                    : _frozenTimerEnd,
                frozenTimer: !useRealTimer,
                frozenTimerDuration: const Duration(minutes: 5),
                participationPercent: pct,
                animateProgress: true,
              );
            }),
          ),
          // Text field area (bright during replace hints, dim during new_round)
          // Blocked during all new_round + replace hints until dismissed
          AbsorbPointer(
            absorbing: isNewRoundHint || isReplaceHint,
            child: AnimatedOpacity(
            opacity: isReplaceHint ? 1.0 : 0.25,
            duration: const Duration(milliseconds: 250),
            child: Builder(builder: (_) {
              final isR3 = state.currentRound!.customId == 3;
              return ProposingStatePanel(
                roundCustomId: state.currentRound!.customId,
                propositionsPerUser: state.chat.propositionsPerUser,
                myPropositions: state.myPropositions,
                propositionController: _propositionController,
                onSubmit: _submitProposition,
                phaseEndsAt: state.currentRound!.phaseEndsAt,
                onPhaseExpired: () {},
                showPhaseBar: false,
                onSkip: isR3 ? _skipRound3Proposing : null,
                canSkip: isR3,
              );
            }),
          ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
          // Current phase panel (always visible — textfield or rate button)
          _buildCurrentPhasePanel(state),
        ],
    );
  }

  /// Get the translated Round 1 winner text for hint messages.
  String _getR1WinnerText(TutorialChatState state, AppLocalizations l10n) {
    final templateKey = state.selectedTemplate;
    if (templateKey != null && templateKey != 'classic') {
      return _translateProposition(
        TutorialData.round1WinnerForTemplate(templateKey), l10n);
    }
    return state.previousRoundWinners.isNotEmpty
        ? state.previousRoundWinners.first.content ?? ''
        : '';
  }

  /// Builds a PreviousWinnerPanel for the tutorial, translating winner content
  /// and providing custom results navigation.
  Widget _buildTopCandidatePlaceholder() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        // Ellipsis placeholder = no winner yet, not clickable
        onTap: null,
        child: UnconstrainedBox(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 64,
            ),
            child: PropositionContentCard(
              content: '...',
              label: l10n.chatTourPlaceholderTitle,
              borderColor: AppColors.consensus,
              glowColor: AppColors.consensus,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTutorialWinnerPanel(TutorialChatState state) {
    if (state.previousRoundWinners.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    // Translate all winner content for display
    final translatedWinners = state.previousRoundWinners.map((w) =>
      RoundWinner(
        id: w.id,
        roundId: w.roundId,
        propositionId: w.propositionId,
        content: _translateProposition(w.content ?? '', l10n),
        globalScore: w.globalScore,
        rank: w.rank,
        createdAt: w.createdAt,
      ),
    ).toList();

    final isR1Result = state.currentStep == TutorialStep.round1Result;
    final activeHint = _activeHintId(state);
    // Block taps on winner panel when any dialog is open, except hints
    // that tell the user to tap it (r1_result_tap, convergence tap)
    final isR2Result = state.currentStep == TutorialStep.round2Result;
    final blockPanel = (isR1Result && _r1ResultDialogStep < 2)
        || (isR2Result && _r2ResultDialogStep < 2)
        || _r1ResultDialogStep == 1 // R1 finger animation
        || _r2ResultDialogStep == 1 // R2 finger animation
        || _r1LeaderboardStep == 1 // leaderboard finger animation
        || _convergenceDialogStep == 1 // convergence finger animation
        || activeHint == 'r1_result_winner'
        || activeHint == 'r1_leaderboard_tap'
        || activeHint == 'r2_result_won'
        || activeHint == 'r2_new_round'
        || activeHint == 'r2_replace'
        || activeHint == 'r3_new_round'
        || activeHint == 'r3_replace';
    return AbsorbPointer(
      absorbing: blockPanel,
      child: PreviousWinnerPanel(
        previousRoundWinners: translatedWinners,
        currentWinnerIndex: state.currentWinnerIndex,
        roundNumber: state.currentStep == TutorialStep.round1Result ? 1
            : state.currentStep == TutorialStep.round2Result ? 2
            : (state.currentRound?.customId ?? 2) - 1,
        onWinnerIndexChanged: (index) {
          ref.read(tutorialChatNotifierProvider.notifier).setWinnerIndex(index);
        },
        onTap: isR1Result
            ? () => _showR1CycleHistory(context, state)
            : isR2Result
                ? () => _showR2CycleHistory(context, state)
                : () => _showTutorialCycleHistory(
                    context, state, state.consensusItems.length + 1,
                    showOngoingPlaceholder: false),
      ),
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Sequential: old fades out (0→0.5), new fades in (0.5→1)
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (pushedContext, animation, secondaryAnimation) => ReadOnlyResultsScreen(
          propositions: translatedResults,
          roundNumber: roundNumber,
          roundId: -roundNumber,
          myParticipantId: -1,
          onExitTutorial: () async {
            final confirmed = await _TutorialScreenState.showSkipDialog(pushedContext);
            if (confirmed && pushedContext.mounted) {
              Navigator.pop(pushedContext);
              _handleSkip();
            }
          },
        ),
      ),
    );
  }

  Widget _buildCurrentPhasePanel(TutorialChatState state) {
    // During result steps, hide unless leaderboard reveal is active
    if (state.currentStep == TutorialStep.round1Result) {
      // Show R2 proposing preview: status bar + progress + frozen timer + textfield
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundPhaseBar(
            roundNumber: 2,
            isProposing: true,
            phaseEndsAt: _frozenTimerEnd,
            participationPercent: 0,
            frozenTimer: true,
            frozenTimerDuration: const Duration(minutes: 5),
          ),
          ProposingStatePanel(
            roundCustomId: 2,
            propositionsPerUser: state.chat.propositionsPerUser,
            myPropositions: const [],
            propositionController: _propositionController,
            onSubmit: _submitProposition,
            showPhaseBar: false,
          ),
        ],
      );
    }
    if (state.currentStep == TutorialStep.round2Result) {
      // Show R3 proposing preview (dimmed via bottomDimOpacity)
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundPhaseBar(
            roundNumber: 3,
            isProposing: true,
            phaseEndsAt: _frozenTimerEnd,
            participationPercent: 0,
            frozenTimer: true,
            frozenTimerDuration: const Duration(minutes: 5),
          ),
          ProposingStatePanel(
            roundCustomId: 3,
            propositionsPerUser: state.chat.propositionsPerUser,
            myPropositions: const [],
            propositionController: _propositionController,
            onSubmit: _submitProposition,
            showPhaseBar: false,
          ),
        ],
      );
    }
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
        // Round 3: allow skipping proposing
        final isRound3 = state.currentRound!.customId == 3;
        // Tutorial: all NPCs participated, user may or may not have
        final userProposed = state.myPropositions.where((p) => !p.isCarriedForward).isNotEmpty;
        final proposingPercent = state.participants.isNotEmpty
            ? (((state.participants.length - 1) + (userProposed ? 1 : 0)) * 100 /
                state.participants.length).round()
            : 0;
        return ProposingStatePanel(
          roundCustomId: state.currentRound!.customId,
          propositionsPerUser: state.chat.propositionsPerUser,
          myPropositions: state.myPropositions,
          propositionController: _propositionController,
          onSubmit: _submitProposition,
          phaseEndsAt: state.currentRound!.phaseEndsAt,
          onPhaseExpired: () {}, // No-op for tutorial
          onSkip: isRound3 ? _skipRound3Proposing : null,
          canSkip: isRound3,
          participationPercent: proposingPercent,
          animateProgress: true,
        );
      case RoundPhase.rating:
        // Hide Start Rating button until the r1_rating_button hint appears
        final activeHint = _activeHintId(state);
        final hideButton = activeHint == 'r1_rating_phase';
        // R2/R3 auto-open rating screen — hide button entirely
        final isAutoOpen = state.currentRound!.customId >= 2;
        // Progress bar: 0 during r1_rating_phase (just entered), 75% after
        final showRatingProgress = activeHint != 'r1_rating_phase';
        final ratingPercent = showRatingProgress && state.participants.isNotEmpty
            ? (((state.participants.length - 1) + (state.hasRated ? 1 : 0)) * 100 /
                state.participants.length).round()
            : 0;
        // Freeze timer during rating phase hint, start fresh 5min at rating button hint
        final freezeRatingTimer = activeHint == 'r1_rating_phase';
        if (!freezeRatingTimer && _ratingTimerStart == null) {
          _ratingTimerStart = DateTime.now().add(const Duration(minutes: 5));
        }
        return RatingStatePanel(
          roundCustomId: state.currentRound!.customId,
          hasRated: state.hasRated,
          hasStartedRating: state.hasStartedRating,
          propositionCount: state.propositions.length,
          onStartRating: () => _openTutorialRatingScreen(state),
          phaseEndsAt: freezeRatingTimer ? _frozenTimerEnd : _ratingTimerStart,
          onPhaseExpired: () {}, // No-op for tutorial
          isHost: true,
          showButton: !hideButton,
          participationPercent: ratingPercent,
          animateProgress: true,
          frozenTimer: freezeRatingTimer,
          frozenTimerDuration: const Duration(minutes: 5),
        );
    }
  }

  /// Build tutorial-specific panel (intro only)
  Widget _buildTutorialPanel(TutorialChatState state) {
    final notifier = ref.read(tutorialChatNotifierProvider.notifier);

    if (state.currentStep == TutorialStep.intro) {
      return TutorialIntroPanel(
        onSelect: (templateKey) {
          _startIntroToChatTourTransition(templateKey);
        },
        onHtmlPlay: (templateKey) {
          _startIntroToChatTourTransition(templateKey, skipFadeOut: true);
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
  /// Name of the carried-forward winner to show a hint about (R2+)
  final String? carriedWinnerName;

  const _TutorialRatingScreen({
    required this.propositions,
    required this.onComplete,
    this.onExitTutorial,
    this.showHints = false,
    this.carriedWinnerName,
  });

  @override
  State<_TutorialRatingScreen> createState() => _TutorialRatingScreenState();
}

class _TutorialRatingScreenState extends State<_TutorialRatingScreen>
    with SingleTickerProviderStateMixin {
  RatingPhase _currentPhase = RatingPhase.binary;
  bool _dismissedRatingHint = false;
  bool _rankHintShown = false;
  bool _carriedHintDismissed = false;
  bool _carriedHintPending = false; // true as soon as carried card appears, blocks input
  bool _carriedHintReady = false;   // true after 500ms delay, shows dialog
  int _placementCount = 0;
  final _carriedCardKey = GlobalKey();
  double? _carriedCardBottom;
  late final AnimationController _fadeController;
  bool _hintReady = false;
  bool _pageFadeComplete = false;
  bool _ratingIntroShown = false; // true after intro dismissed, show Compare hint
  bool _demoComplete = false; // true after binary finger animation
  bool _posDemoComplete = false; // true after positioning finger animation
  bool _posIntroShown = false; // true after positioning demo plays, show Position hint
  final _swapButtonKey = GlobalKey();
  final _checkButtonKey = GlobalKey();
  final _movementControlsKey = GlobalKey();
  final _positionsNotifier = ValueNotifier<Map<String, double>>({});
  final _demoController = RatingDemoController();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeController.forward().then((_) {
      _pageFadeComplete = true;
      // Small delay after page fade before showing hint
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && widget.showHints && !_hintReady) {
          setState(() => _hintReady = true);
        }
        // Carried hint is triggered by onPhaseChanged → positioning, not here
      });
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _positionsNotifier.dispose();
    super.dispose();
  }

  void _measureCarriedCardPosition() {
    final box = _carriedCardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final pos = box.localToGlobal(Offset.zero);
    _carriedCardBottom = pos.dy + box.size.height;
  }

  void _advanceRatingHint() {
    TutorialTts.stop('line3545');
    if (!_ratingIntroShown) {
      setState(() => _hintReady = false); // fade out (800ms AnimatedOpacity)
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _ratingIntroShown = true;
            _hintReady = true; // fade in with new content
          });
        }
      });
      return;
    }
    if (!_rankHintShown) {
      setState(() => _hintReady = false); // fade out
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _rankHintShown = true;
            _demoComplete = false;
          });
        }
      });
      return;
    }
    setState(() {
      _dismissedRatingHint = true;
      _hintReady = false;
    });
  }

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

    // Track whether to dim non-active elements
    bool dimBackground = false;
    Widget? customDescWidget;

    if (_dismissedRatingHint) {
      hintTitle = null;
      hintDescription = null;
      hasInlineIcons = false;
    } else if (widget.showHints && _currentPhase == RatingPhase.binary && !_ratingIntroShown) {
      // First: rating screen intro
      hintTitle = l10n.tutorialRateIdeas;
      hintDescription = l10n.tutorialRatingIntroHint;
      hasInlineIcons = false;
    } else if (widget.showHints && _currentPhase == RatingPhase.binary && _ratingIntroShown && !_rankHintShown) {
      // Second: rank explanation (before finger demo)
      hintTitle = l10n.tutorialRateIdeas;
      hintDescription = l10n.tutorialRatingRankHint;
      hasInlineIcons = false;
    } else if (widget.showHints && _currentPhase == RatingPhase.binary && _rankHintShown && _demoComplete) {
      // Third: Compare Ideas dialog (after demo animation completes)
      hintTitle = l10n.tutorialHintCompare;
      hintDescription = l10n.tutorialRatingBinaryHint;
      hasInlineIcons = true;
      dimBackground = true;
    } else if (widget.showHints && _currentPhase == RatingPhase.positioning && _posDemoComplete) {
      // Show positioning hint after demo completes
      hintTitle = l10n.tutorialHintPosition;
      hintDescription = l10n.tutorialRatingPositioningHint;
      hasInlineIcons = true;
    } else {
      hintTitle = null;
      hintDescription = null;
      hasInlineIcons = false;
    }

    // Show hint only after page has faded in
    final showHint = _hintReady && !_dismissedRatingHint &&
        widget.showHints && (hintTitle != null);

    // Whether a finger demo is actively playing (block user taps on rating widget)
    final demoActive = widget.showHints && (
        (_ratingIntroShown && _rankHintShown && !_demoComplete && _currentPhase == RatingPhase.binary) ||
        (!_posDemoComplete && _currentPhase == RatingPhase.positioning)
    );
    // Block controls during hint transitions (fade out/in between dialogs)
    final hintsInProgress = widget.showHints && !_dismissedRatingHint &&
        _currentPhase == RatingPhase.binary && (!_rankHintShown || !_demoComplete);
    final blockBack = _carriedHintReady && !_carriedHintDismissed;
    final dimRatingAppBar = showHint || demoActive || hintsInProgress || (blockBack);
    return Scaffold(
        appBar: AppBar(
          leading: blockBack
              ? AnimatedOpacity(
                  opacity: 0.25,
                  duration: const Duration(milliseconds: 250),
                  child: AbsorbPointer(absorbing: true, child: const BackButton()),
                )
              : null,
          title: AnimatedOpacity(
            opacity: dimRatingAppBar ? 0.25 : 1.0,
            duration: const Duration(milliseconds: 250),
            child: Text(l10n.tutorialRateIdeas),
          ),
          actions: [
            if (widget.onExitTutorial != null)
              AnimatedOpacity(
                opacity: dimRatingAppBar ? 0.25 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: IconButton(
                  icon: const Icon(Icons.exit_to_app),
                  tooltip: l10n.tutorialSkipMenuItem,
                  onPressed: widget.onExitTutorial,
                ),
              ),
          ],
        ),
        body: Stack(
              fit: StackFit.expand,
              children: [
                // Layer 0: full-size rating widget (blocked during hints/demos)
                Positioned.fill(
              child: AbsorbPointer(
                absorbing: demoActive || showHint || hintsInProgress || (_carriedHintPending && !_carriedHintDismissed),
                child: RatingWidget(
              propositions: propsForRating,
              onRankingComplete: (_) => widget.onComplete(),
              lazyLoadingMode: false,
              isResuming: false,
              trackedCardKey: widget.carriedWinnerName != null ? _carriedCardKey : null,
              trackedCardId: widget.carriedWinnerName != null
                  ? widget.propositions
                      .firstWhere((p) => p.carriedFromId != null,
                          orElse: () => widget.propositions.first)
                      .id.toString()
                  : null,
              swapButtonKey: widget.showHints ? _swapButtonKey : null,
              checkButtonKey: widget.showHints ? _checkButtonKey : null,
              movementControlsKey: widget.showHints ? _movementControlsKey : null,
              positionsNotifier: widget.showHints ? _positionsNotifier : null,
              demoController: widget.showHints ? _demoController : null,
              onCounterUpdate: widget.carriedWinnerName != null
                  ? (placed, total) {
                      if (mounted && placed > _placementCount) {
                        final prevCount = _placementCount;
                        _placementCount = placed;
                        // The carried winner is the 3rd card. It appears when placed
                        // increases past the initial value (first comparison done).
                        // Skip the initial callback (prevCount == 0) which fires at init.
                        if (prevCount > 0 && !_carriedHintPending) {
                          setState(() => _carriedHintPending = true);
                          // Measure immediately on next frame (card still near comparison area)
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _measureCarriedCardPosition();
                          });
                          // Show dialog after card animation settles
                          Future.delayed(const Duration(milliseconds: 500), () {
                            if (mounted && !_carriedHintReady) {
                              setState(() => _carriedHintReady = true);
                            }
                          });
                        }
                      }
                    }
                  : null,
              onPhaseChanged: widget.showHints
                  ? (phase) {
                      if (mounted) {
                        setState(() {
                          _currentPhase = phase;
                          // Don't re-show hints if user undid back to binary
                          // after already completing all binary hints
                          if (!(phase == RatingPhase.binary && _demoComplete)) {
                            _dismissedRatingHint = false;
                          }
                          // Only show hint immediately if page fade is done
                          if (_pageFadeComplete) _hintReady = true;
                        });
                      }
                    }
                  : null,
            ),
          ),
          ),
          // Layer 1: floating hint overlay (always in tree, opacity-controlled)
          Positioned(
            left: 40,
            right: 80,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !(showHint && hintTitle != null),
              child: AnimatedOpacity(
                opacity: (showHint && hintTitle != null) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 700),
                child: (showHint && hintTitle != null)
                    ? Center(
                        child: GestureDetector(
                          onTap: () => _advanceRatingHint(),
                          child: TourTooltipCard(
                              title: hintTitle ?? '',
                              description: hintDescription ?? '',
                              descriptionWidget: customDescWidget ??
                                  (hasInlineIcons && hintDescription != null
                                      ? Text.rich(
                                          _buildInlineHintSpans(
                                            hintDescription,
                                            Theme.of(context),
                                            Theme.of(context).textTheme.bodyMedium,
                                          ),
                                        )
                                      : null),
                              onNext: _advanceRatingHint,
                              onSkip: widget.onExitTutorial ?? () {},
                              stepIndex: 0,
                              totalSteps: 1,
                              nextLabel: l10n.homeTourFinish,
                              skipLabel: l10n.tutorialSkipMenuItem,
                              stepOfLabel: '',
                            ),
                          ),
                        )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          // Layer 2: animated finger (always in tree — uses Positioned internally)
          RatingControlsDemo(
            swapButtonKey: _swapButtonKey,
            checkButtonKey: _checkButtonKey,
            onSwap: _demoController.swap,
            active: widget.showHints && _ratingIntroShown && _rankHintShown && !_demoComplete &&
                _currentPhase == RatingPhase.binary,
            onComplete: () {
              if (mounted) {
                setState(() {
                  _demoComplete = true;
                  _hintReady = true;
                });
              }
            },
          ),
          // Layer 3: positioning finger demo (always in tree)
          PositioningControlsDemo(
            movementControlsKey: _movementControlsKey,
            positionsNotifier: _positionsNotifier,
            demoController: _demoController,
            active: widget.showHints && !_posDemoComplete &&
                _currentPhase == RatingPhase.positioning,
            onComplete: () {
              if (mounted) {
                setState(() {
                  _posDemoComplete = true;
                  _hintReady = true;
                });
              }
            },
          ),
          // Carried-forward winner hint (R2+)
          if (widget.carriedWinnerName != null && _carriedHintReady && !_carriedHintDismissed)
            Builder(builder: (_) {
              // Re-measure in case card moved
              _measureCarriedCardPosition();
              // Convert global position to body-local by subtracting app bar + status bar
              final appBarHeight = kToolbarHeight + MediaQuery.of(context).padding.top;
              final localTop = (_carriedCardBottom ?? 200) - appBarHeight + 12;
              return Positioned(
              left: 40,
              right: 80,
              top: localTop,
              child: TourTooltipCard(
                title: l10n.tutorialCarriedWinnerTitle,
                description: l10n.tutorialCarriedWinnerDesc,
                onNext: () {
                  setState(() => _carriedHintDismissed = true);
                },
                onSkip: () {
                  setState(() => _carriedHintDismissed = true);
                },
                nextLabel: l10n.homeTourFinish,
                skipLabel: '',
                stepOfLabel: '',
                stepIndex: 0,
                totalSteps: 1,
                autoAdvance: true,
              ),
            );
            }),
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
    const undoColor = Color(0xFFEF5350);

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
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: borderColor == Colors.transparent
              ? null
              : Border.all(color: borderColor, width: 2),
        ),
        child: Icon(
          icon,
          size: 18,
          color: iconColor,
        ),
      ),
    );
  }
}

/// Cycle history page for the tutorial with optional convergence hint.
class _TutorialCycleHistoryPage extends StatefulWidget {
  final int convergenceNumber;
  final List<Map<String, dynamic>> rounds;
  final bool showOngoingPlaceholder;
  final bool showConvergenceHint;
  final TutorialChatState state;
  final String? templateKey;
  final String userProp;
  final VoidCallback onSkip;

  const _TutorialCycleHistoryPage({
    required this.convergenceNumber,
    required this.rounds,
    required this.showOngoingPlaceholder,
    this.showConvergenceHint = false,
    required this.state,
    required this.templateKey,
    required this.userProp,
    required this.onSkip,
  });

  @override
  State<_TutorialCycleHistoryPage> createState() =>
      _TutorialCycleHistoryPageState();
}

class _TutorialCycleHistoryPageState extends State<_TutorialCycleHistoryPage>
    with TickerProviderStateMixin {
  // 0=explain dialog, 1=finger animation, 2=back dialog
  int _dialogStep = -1; // -1 = not started yet
  bool _fingerDone = false;

  // Back arrow finger animation
  late final AnimationController _fingerController;
  final GlobalKey _backButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    if (widget.showConvergenceHint) {
      // Wait for page transition to complete before showing first dialog
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) {
          setState(() => _dialogStep = 0);
        }
      });
    }
  }

  void _advanceToFingerAnimation() {
    setState(() => _dialogStep = 1);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _fingerController.forward().then((_) {
          if (mounted) {
            setState(() {
              _fingerDone = true;
              _dialogStep = 2;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    // Don't stop TTS — next screen's dialog may already be speaking
    _fingerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showExplainDialog = widget.showConvergenceHint && _dialogStep == 0;
    final showBackDialog = widget.showConvergenceHint && _dialogStep == 2;

    final dimAppBar = showExplainDialog;
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: AnimatedOpacity(
          opacity: dimAppBar ? 0.25 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: AbsorbPointer(
            absorbing: widget.showConvergenceHint && _dialogStep < 2,
            child: IconButton(
              key: _backButtonKey,
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                TutorialTts.stop('cycle_back_pressed');
                Navigator.pop(context);
              },
            ),
          ),
        ),
        title: AnimatedOpacity(
          opacity: dimAppBar ? 0.25 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: Text(l10n.tutorialCycleHistoryExplainTitle),
        ),
      ),
      body: _buildBody(context, l10n, showExplainDialog, showBackDialog),
    );

    // Show finger animation overlay during step 1
    if (widget.showConvergenceHint && _dialogStep == 1 && !_fingerDone) {
      return Stack(
        children: [
          scaffold,
          _buildBackArrowFingerOverlay(),
        ],
      );
    }

    return scaffold;
  }

  Widget _buildBackArrowFingerOverlay() {
    final backBox =
        _backButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (backBox == null || !backBox.attached) return const SizedBox.shrink();

    final buttonGlobal = backBox.localToGlobal(
      Offset(backBox.size.width / 2, backBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(buttonGlobal, screenSize);
    final targetPos = buttonGlobal;

    return AnimatedBuilder(
      animation: _fingerController,
      builder: (context, _) {
        final t = _fingerController.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetPos, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          opacity = 1.0;
          pos = targetPos;
          scale = 0.78;
        } else if (t < 0.7) {
          opacity = 1.0;
          pos = targetPos;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = targetPos;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, bool showExplainDialog, bool showBackDialog) {
    final items = <Widget>[];

    // Ascending order: oldest at top, newest at bottom
    for (var index = 0; index < widget.rounds.length; index++) {
      final round = widget.rounds[index];
      // Last 2 rounds are convergence winners (only when 3+ rounds)
      final isConvergenceWinner = widget.rounds.length >= 3 &&
          index >= widget.rounds.length - 2;
      final roundNumber = round['number'] as int;
      final winners = round['winners'] as List<String>;

      if (items.isNotEmpty) items.add(const SizedBox(height: 12));
      // During explain dialog: convergence winners bright, others dimmed
      final dimEntry = showExplainDialog && !isConvergenceWinner;
      items.add(AnimatedOpacity(
        opacity: dimEntry ? 0.25 : 1.0,
        duration: const Duration(milliseconds: 250),
        child: RoundWinnerItem(
        winnerTexts: winners,
        label: winners.length > 1
            ? l10n.roundWinners(roundNumber)
            : l10n.roundWinner(roundNumber),
        isConvergence: isConvergenceWinner,
        onTap: () {
          final userProp1 = widget.state.userProposition1 ?? 'My idea';
          List<Proposition> results;
          switch (roundNumber) {
            case 1:
              results = TutorialData.round1ResultsWithRatings(
                  userProp1, templateKey: widget.templateKey);
            case 2:
              results = TutorialData.round2ResultsWithRatings(
                  widget.userProp, templateKey: widget.templateKey);
            default:
              results = TutorialData.round3ResultsWithRatings(
                  widget.userProp, templateKey: widget.templateKey, userR3Proposition: widget.state.userProposition3);
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReadOnlyResultsScreen(
                propositions: results,
                roundNumber: roundNumber,
              ),
            ),
          );
        },
      ),
      ));
    }

    if (widget.showOngoingPlaceholder) {
      items.add(const SizedBox(height: 12));
      items.add(AnimatedOpacity(
        opacity: showExplainDialog ? 0.25 : 1.0,
        duration: const Duration(milliseconds: 250),
        child: UnconstrainedBox(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 64,
          ),
          child: PropositionContentCard(
            content: '...',
            label: l10n.chatTourPlaceholderTitle,
            borderColor: AppColors.consensus,
            glowColor: AppColors.consensus,
          ),
        ),
      ),
      ));
    }

    // Dialog 1: Convergence explanation (inline in list)
    if (showExplainDialog) {
      items.add(const SizedBox(height: 12));
      items.add(TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: TourTooltipCard(
          title: l10n.tutorialCycleHistoryExplainTitle,
          description: l10n.tutorialCycleHistoryExplainDesc,
          onNext: _advanceToFingerAnimation,
          onSkip: _advanceToFingerAnimation,
          nextLabel: l10n.homeTourFinish,
          skipLabel: '',
          stepOfLabel: '',
          stepIndex: 0,
          totalSteps: 1,
          autoAdvance: true,
        ),
      ));
    }

    // Dialog 2: "Press [back] to continue" (positioned below app bar via Stack)
    // This is rendered outside the scrollable list

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              children: items,
            ),
          ),
        ),
        if (showBackDialog)
          Positioned(
            left: 40,
            right: 80,
            top: 16,
            child: Builder(
              builder: (context) {
                final desc = l10n.tutorialCycleHistoryBackDesc;
                final theme = Theme.of(context);
                final parts = desc.split('[back]');
                Widget? descWidget;
                if (parts.length >= 2) {
                  final spans = <InlineSpan>[];
                  for (var i = 0; i < parts.length; i++) {
                    if (parts[i].isNotEmpty) spans.add(TextSpan(text: parts[i]));
                    if (i < parts.length - 1) {
                      spans.add(WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(
                          Icons.arrow_back,
                          size: 18,
                          color: theme.colorScheme.onSurface,
                        ),
                      ));
                    }
                  }
                  descWidget = Text.rich(
                    TextSpan(style: theme.textTheme.bodyMedium, children: spans),
                  );
                }
                return TourTooltipCard(
                  title: l10n.tutorialCycleHistoryExplainTitle,
                  description: desc,
                  descriptionWidget: descWidget,
                  onNext: () => setState(() => _dialogStep = 3),
                  onSkip: () => setState(() => _dialogStep = 3),
                  nextLabel: l10n.homeTourFinish,
                  skipLabel: '',
                  stepOfLabel: '',
                  stepIndex: 0,
                  totalSteps: 1,
                  autoAdvance: true,
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Overlay widget showing finger animation + close hint above the bottom sheet.
/// Rendered in Flutter's Overlay (above everything including the sheet).
/// 3-step leaderboard tour overlay:
/// Step 0: "Participants" dialog (names visible, no ranks)
/// Step 1: "Rankings" dialog (ranks appear as dashes)
/// Step 2: Close hint with finger animation
class _LeaderboardTourOverlayWidget extends StatefulWidget {
  final GlobalKey closeButtonKey;
  final ValueNotifier<int> tourStep;
  final VoidCallback onDismiss;

  const _LeaderboardTourOverlayWidget({
    required this.closeButtonKey,
    required this.tourStep,
    required this.onDismiss,
  });

  @override
  State<_LeaderboardTourOverlayWidget> createState() =>
      _LeaderboardTourOverlayWidgetState();
}

class _LeaderboardTourOverlayWidgetState
    extends State<_LeaderboardTourOverlayWidget>
    with TickerProviderStateMixin {
  int _step = 0; // 0=participants, 1=rankings, 2=unranked, 3=already submitted, 4=higher rank, 5=close (finger+hint)
  late final AnimationController _fingerController;
  late final AnimationController _dialogFadeController;
  bool _fingerDone = false;
  bool _transitioning = false;
  Offset? _buttonGlobal;

  @override
  void initState() {
    super.initState();
    _fingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _dialogFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    // Delay step 0 so sheet renders invisible first, then fades in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.tourStep.value = 0;
    });
  }

  @override
  void dispose() {
    _fingerController.dispose();
    _dialogFadeController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_transitioning) return;
    _transitioning = true;
    // Fade out current dialog
    _dialogFadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _step++;
        _transitioning = false;
        if (_step == 1) {
          widget.tourStep.value = 1; // Show ranks with numbers
        } else if (_step == 2) {
          widget.tourStep.value = 2; // Transition ranks to dashes
        } else if (_step == 3) {
          widget.tourStep.value = 3; // Show "Done" tags on NPCs
        } else if (_step == 5) {
          widget.tourStep.value = 5; // Show close button
          _buttonGlobal = _measureButton();
          _fingerController.forward().then((_) {
            if (mounted) {
              setState(() => _fingerDone = true);
              widget.tourStep.value = 6; // Enable X button in sheet
            }
          });
        }
        // Step 4 doesn't change sheet state, just dialog text
      });
      // Fade in new dialog (for steps 0-4)
      if (_step == 3) {
        // Delay dialog so "Done" tags fade in first
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _dialogFadeController.forward();
          }
        });
      } else if (_step <= 4) {
        _dialogFadeController.forward();
      }
    });
  }

  Offset? _measureButton() {
    final box = widget.closeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenSize = MediaQuery.of(context).size;

    // Measure button position for step 2
    _buttonGlobal ??= _measureButton();
    final buttonPos = _buttonGlobal;
    // Position dialogs above the sheet
    final dialogBottom = buttonPos != null
        ? screenSize.height - (buttonPos.dy - 50) + 12
        : screenSize.height * 0.4;

    String title;
    String description;
    Widget? descriptionWidget;

    if (_step == 0) {
      title = l10n.chatTourLeaderboardParticipants;
      description = l10n.chatTourLeaderboardParticipantsDesc;
    } else if (_step == 1) {
      title = l10n.chatTourLeaderboardRankings;
      // TTS-friendly: replace markers with plain text
      description = l10n.chatTourLeaderboardRankingsDesc
          .replaceAll('[proposing]', l10n.proposing)
          .replaceAll('[rating]', l10n.rating);
      descriptionWidget = buildPhaseChipRichText(l10n.chatTourLeaderboardRankingsDesc, l10n, context);
    } else if (_step == 2) {
      title = l10n.chatTourLeaderboardRankings;
      description = l10n.chatTourLeaderboardRankingsDesc2;
    } else if (_step == 3) {
      title = l10n.chatTourSubmitTitle;
      description = l10n.chatTourSubmitDesc2
          .replaceAll('[proposing]', l10n.proposing);
      descriptionWidget = buildPhaseChipRichText(l10n.chatTourSubmitDesc2, l10n, context);
    } else if (_step == 4) {
      title = l10n.chatTourSubmitTitle;
      description = l10n.chatTourSubmitDesc3;
    } else {
      title = l10n.chatTourClosePanel;
      description = l10n.chatTourClosePanelDesc;
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Steps 0-4: dialog with Next button
          if (_step <= 4)
            Positioned(
              left: 16,
              right: 16,
              bottom: dialogBottom,
              child: FadeTransition(
                opacity: _dialogFadeController,
                child: TourTooltipCard(
                  title: title,
                  description: description,
                  descriptionWidget: descriptionWidget,
                  onNext: _nextStep,
                  onSkip: widget.onDismiss,
                  stepIndex: _step,
                  totalSteps: 6,
                  nextLabel: l10n.homeTourNext,
                  skipLabel: l10n.tutorialSkipMenuItem,
                  stepOfLabel: '',
                ),
              ),
            ),
          // Step 5: finger animation on close button
          if (_step == 5 && !_fingerDone && buttonPos != null)
            AnimatedBuilder(
              animation: _fingerController,
              builder: (context, _) {
                // Start directly below the X button
                final startPos = Offset(buttonPos.dx, buttonPos.dy + 80);
                final t = _fingerController.value;
                double opacity;
                Offset pos;
                double scale;

                if (t < 0.15) {
                  opacity = t / 0.15;
                  pos = startPos;
                  scale = 1.0;
                } else if (t < 0.45) {
                  final glideT = (t - 0.15) / 0.3;
                  opacity = 1.0;
                  pos = Offset.lerp(startPos, buttonPos, Curves.easeInOut.transform(glideT))!;
                  scale = 1.0;
                } else if (t < 0.55) {
                  opacity = 1.0;
                  pos = buttonPos;
                  scale = 0.78;
                } else if (t < 0.65) {
                  opacity = 1.0;
                  pos = buttonPos;
                  scale = 1.0;
                } else {
                  opacity = 1.0 - ((t - 0.65) / 0.35);
                  pos = buttonPos;
                  scale = 1.0;
                }

                return Positioned(
                  left: pos.dx - 14,
                  top: pos.dy - 4,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale,
                      child: const Icon(
                        Icons.touch_app,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          // Step 5: close hint after finger animation
          if (_step == 5 && _fingerDone)
            Positioned(
              left: 16,
              right: 16,
              bottom: dialogBottom,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 400),
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: NoButtonTtsCard(title: title, description: description),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cycle history page for R1 — shows 1 round entry with guided tutorial flow.
class _TutorialR1CycleHistoryPage extends StatefulWidget {
  final String r1Winner;
  final String userProp1;
  final String? templateKey;
  final VoidCallback onSkip;

  const _TutorialR1CycleHistoryPage({
    required this.r1Winner,
    required this.userProp1,
    required this.templateKey,
    required this.onSkip,
  });

  @override
  State<_TutorialR1CycleHistoryPage> createState() =>
      _TutorialR1CycleHistoryPageState();
}

class _TutorialR1CycleHistoryPageState
    extends State<_TutorialR1CycleHistoryPage>
    with TickerProviderStateMixin {
  // 0=explain dialog, 1=finger on round entry, 2=tap dialog
  // 3=returned from results, finger on back, 4=back dialog
  int _dialogStep = -1;
  bool _roundFingerDone = false;
  bool _backFingerDone = false;
  bool _hasOpenedResults = false;

  late final AnimationController _roundFingerController;
  late final AnimationController _backFingerController;
  final GlobalKey _roundEntryKey = GlobalKey();
  final GlobalKey _backButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _roundFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _backFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    // Show first dialog after page transition
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _dialogStep = 0);
    });
  }

  @override
  void dispose() {
    // Don't stop TTS — next screen's dialog may already be speaking
    _roundFingerController.dispose();
    _backFingerController.dispose();
    super.dispose();
  }

  void _advanceToRoundFinger() {
    setState(() => _dialogStep = 1);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _roundFingerController.forward().then((_) {
          if (mounted) {
            setState(() {
              _roundFingerDone = true;
              _dialogStep = 2;
            });
          }
        });
      }
    });
  }

  void _openR1Results() {
    if (_hasOpenedResults) return;
    _hasOpenedResults = true;
    // Stop audio + hide dialog in same frame to prevent empty card flash
    TutorialTts.stop('r1_openResults');
    setState(() => _dialogStep = -1);

    final results = TutorialData.round1ResultsWithRatings(
      widget.userProp1,
      templateKey: widget.templateKey,
    );

    // Delay push to next frame so setState rebuild removes the dialog first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (pushedContext, _, __) => ReadOnlyResultsScreen(
          propositions: results,
          roundNumber: 1,
          showTutorialHint: true,
          tutorialWinnerName: widget.r1Winner,
          onExitTutorial: () async {
            if (pushedContext.mounted) {
              Navigator.pop(pushedContext);
              widget.onSkip();
            }
          },
        ),
      ),
    ).then((_) {
      // Returned from results — show back finger
      if (mounted) {
        setState(() => _dialogStep = 3);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _backFingerController.forward().then((_) {
              if (mounted) {
                setState(() {
                  _backFingerDone = true;
                  _dialogStep = 4;
                });
              }
            });
          }
        });
      }
    });
    }); // end addPostFrameCallback
  }

  Widget _buildFingerOverlay(AnimationController controller, GlobalKey targetKey) {
    final targetBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.attached) return const SizedBox.shrink();

    final targetGlobal = targetBox.localToGlobal(
      Offset(targetBox.size.width / 2, targetBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(targetGlobal, screenSize);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetGlobal, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          opacity = 1.0;
          pos = targetGlobal;
          scale = 0.78;
        } else if (t < 0.7) {
          opacity = 1.0;
          pos = targetGlobal;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = targetGlobal;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Dim app bar during dialogs (not during back step)
    final dimAppBar = _dialogStep >= 0 && _dialogStep < 3;

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: AnimatedOpacity(
          opacity: dimAppBar ? 0.25 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: AbsorbPointer(
            absorbing: _dialogStep < 4,
            child: IconButton(
              key: _backButtonKey,
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                TutorialTts.stop('cycle_back_pressed');
                Navigator.pop(context);
              },
            ),
          ),
        ),
        title: AnimatedOpacity(
          opacity: dimAppBar ? 0.25 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: Text(l10n.tutorialR1CycleExplainTitle),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Center(
              child: Column(
                children: [
                  AbsorbPointer(
                    absorbing: _dialogStep < 2 || _hasOpenedResults,
                    child: KeyedSubtree(
                      key: _roundEntryKey,
                      child: RoundWinnerItem(
                        winnerTexts: [widget.r1Winner],
                        label: l10n.roundWinner(1),
                        isConvergence: false,
                        onTap: _openR1Results,
                      ),
                    ),
                  ),
                  // Dialog 1: explain (inline in list)
                  if (_dialogStep == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: TourTooltipCard(
                          title: l10n.tutorialR1CycleExplainTitle,
                          description: l10n.tutorialR1CycleExplainDesc,
                          onNext: _advanceToRoundFinger,
                          onSkip: _advanceToRoundFinger,
                          nextLabel: l10n.homeTourFinish,
                          skipLabel: '',
                          stepOfLabel: '',
                          stepIndex: 0,
                          totalSteps: 1,
                          autoAdvance: true,
                        ),
                      ),
                    ),
                  // Dialog 2: tap round (inline in list)
                  if (_dialogStep == 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: NoButtonTtsCard(
                          title: l10n.tutorialR1CycleExplainTitle,
                          description: l10n.tutorialR1CycleTapDesc,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Dialog: "Press back to continue" (below app bar)
          if (_dialogStep >= 4)
            Positioned(
              left: 40,
              right: 80,
              top: 16,
              child: Builder(
                builder: (context) {
                  final desc = l10n.tutorialPressBackToContinue;
                  final theme = Theme.of(context);
                  final parts = desc.split('[back]');
                  Widget? descWidget;
                  if (parts.length >= 2) {
                    final spans = <InlineSpan>[];
                    for (var i = 0; i < parts.length; i++) {
                      if (parts[i].isNotEmpty) spans.add(TextSpan(text: parts[i]));
                      if (i < parts.length - 1) {
                        spans.add(WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: theme.colorScheme.onSurface,
                          ),
                        ));
                      }
                    }
                    descWidget = Text.rich(
                      TextSpan(style: theme.textTheme.bodyMedium, children: spans),
                    );
                  }
                  return NoButtonTtsCard(
                    title: l10n.tutorialR1CycleExplainTitle,
                    description: desc,
                    descriptionWidget: descWidget,
                  );
                },
              ),
            ),
        ],
      ),
    );

    // Finger animation: tapping round entry
    if (_dialogStep == 1 && !_roundFingerDone) {
      return Stack(
        children: [
          scaffold,
          _buildFingerOverlay(_roundFingerController, _roundEntryKey),
        ],
      );
    }

    // Finger animation: tapping back arrow
    if (_dialogStep == 3 && !_backFingerDone) {
      return Stack(
        children: [
          scaffold,
          _buildFingerOverlay(_backFingerController, _backButtonKey),
        ],
      );
    }

    return scaffold;
  }
}

/// Overlay widget for R1 leaderboard reveal dialogs (above bottom sheet).
class _R1LeaderboardOverlayWidget extends StatefulWidget {
  final GlobalKey closeButtonKey;
  final ValueNotifier<int> dialogStep;
  final AppLocalizations l10n;

  const _R1LeaderboardOverlayWidget({
    required this.closeButtonKey,
    required this.dialogStep,
    required this.l10n,
  });

  @override
  State<_R1LeaderboardOverlayWidget> createState() =>
      _R1LeaderboardOverlayWidgetState();
}

class _R1LeaderboardOverlayWidgetState
    extends State<_R1LeaderboardOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fingerController;
  bool _fingerDone = false;

  @override
  void initState() {
    super.initState();
    _fingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _fingerController.dispose();
    super.dispose();
  }

  void _startCloseFingerAnimation() {
    _fingerController.reset();
    _fingerDone = false;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _fingerController.forward().then((_) {
        if (!mounted) return;
        setState(() => _fingerDone = true);
        widget.dialogStep.value = 2;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.dialogStep,
      builder: (context, step, _) {
        if (step == 0) {
          return _buildDialog(
            widget.l10n.tutorialR1LeaderboardUpdatedDesc,
            autoAdvance: true,
            onNext: () {
              TutorialTts.stop('line4890');
              widget.dialogStep.value = 1;
              _startCloseFingerAnimation();
            },
          );
        }
        // Step 1: finger animation on close button
        if (step == 1 && !_fingerDone) {
          return _buildFingerOverlay();
        }
        if (step == 2) {
          // No button — user must press X to continue
          final buttonPos = _measureCloseButton();
          final screenSize = MediaQuery.of(context).size;
          final dialogBottom = buttonPos != null
              ? screenSize.height - (buttonPos.dy - 50) + 12
              : screenSize.height * 0.4;
          return Positioned(
            left: 16,
            right: 16,
            bottom: dialogBottom,
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: NoButtonTtsCard(
                  title: widget.l10n.leaderboard,
                  description: widget.l10n.tutorialR1LeaderboardDoneDesc,
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildFingerOverlay() {
    final buttonPos = _measureCloseButton();
    if (buttonPos == null) return const SizedBox.shrink();

    // Start directly below the X button
    final startPos = Offset(buttonPos.dx, buttonPos.dy + 80);
    final targetPos = buttonPos;

    return AnimatedBuilder(
      animation: _fingerController,
      builder: (context, _) {
        final t = _fingerController.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.15) {
          opacity = t / 0.15;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.45) {
          final glideT = (t - 0.15) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetPos, curved)!;
          scale = 1.0;
        } else if (t < 0.55) {
          opacity = 1.0;
          pos = targetPos;
          scale = 0.78;
        } else if (t < 0.65) {
          opacity = 1.0;
          pos = targetPos;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.65) / 0.35);
          pos = targetPos;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Offset? _measureCloseButton() {
    final box = widget.closeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
  }

  Widget _buildDialog(String description, {required VoidCallback onNext, bool autoAdvance = true}) {
    final buttonPos = _measureCloseButton();
    final screenSize = MediaQuery.of(context).size;
    // Position just above the bottom sheet (same formula as chat tour overlay)
    final dialogBottom = buttonPos != null
        ? screenSize.height - (buttonPos.dy - 50) + 12
        : screenSize.height * 0.4;
    return Positioned(
      left: 16,
      right: 16,
      bottom: dialogBottom,
      child: Material(
        color: Colors.transparent,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: TourTooltipCard(
            title: widget.l10n.leaderboard,
            description: description,
            onNext: onNext,
            onSkip: onNext,
            nextLabel: widget.l10n.homeTourFinish,
            skipLabel: '',
            stepOfLabel: '',
            stepIndex: 0,
            totalSteps: 1,
            autoAdvance: autoAdvance,
          ),
        ),
      ),
    );
  }
}

/// Cycle history page for R2 — shows 2 round entries, guides user to tap Round 2.
class _TutorialR2CycleHistoryPage extends StatefulWidget {
  final String r1Winner;
  final String r2Winner;
  final String userProp1;
  final String userProp2;
  final String? templateKey;
  final VoidCallback onSkip;

  const _TutorialR2CycleHistoryPage({
    required this.r1Winner,
    required this.r2Winner,
    required this.userProp1,
    required this.userProp2,
    required this.templateKey,
    required this.onSkip,
  });

  @override
  State<_TutorialR2CycleHistoryPage> createState() =>
      _TutorialR2CycleHistoryPageState();
}

class _TutorialR2CycleHistoryPageState
    extends State<_TutorialR2CycleHistoryPage>
    with TickerProviderStateMixin {
  // 0=explain dialog, 1=finger on round 2, 2=tap dialog
  // 3=returned from results, finger on back, 4=back dialog
  int _dialogStep = -1;
  bool _roundFingerDone = false;
  bool _backFingerDone = false;
  bool _hasOpenedResults = false;

  late final AnimationController _roundFingerController;
  late final AnimationController _backFingerController;
  final GlobalKey _round2EntryKey = GlobalKey();
  final GlobalKey _backButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _roundFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _backFingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _dialogStep = 0);
    });
  }

  @override
  void dispose() {
    // Don't stop TTS here — next screen's dialog starts speaking
    // before this dispose fires (pop animation timing)
    _roundFingerController.dispose();
    _backFingerController.dispose();
    super.dispose();
  }

  void _advanceToRoundFinger() {
    setState(() => _dialogStep = 1);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _roundFingerController.forward().then((_) {
          if (mounted) {
            setState(() {
              _roundFingerDone = true;
              _dialogStep = 2;
            });
          }
        });
      }
    });
  }

  void _openR2Results() {
    if (_hasOpenedResults) return;
    _hasOpenedResults = true;
    // Stop audio + hide dialog in same frame to prevent empty card flash
    TutorialTts.stop('r2_openResults');
    setState(() => _dialogStep = -1);

    final results = TutorialData.round2ResultsWithRatings(
      widget.userProp2,
      templateKey: widget.templateKey,
    );

    // Delay push to next frame so setState rebuild removes the dialog first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        reverseTransitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeIn = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
          );
          return FadeTransition(opacity: fadeIn, child: child);
        },
        pageBuilder: (pushedContext, _, __) => ReadOnlyResultsScreen(
          propositions: results,
          roundNumber: 2,
          showTutorialHint: true,
          tutorialWinnerName: widget.r2Winner,
          tutorialHintDescription: AppLocalizations.of(pushedContext).tutorialR2ResultsExplainDesc,
          tutorialHintTargetRating: 75.0, // R1 winner (Movie Night) rating in R2 results
          onExitTutorial: () async {
            if (pushedContext.mounted) {
              Navigator.pop(pushedContext);
              widget.onSkip();
            }
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _dialogStep = 3);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _backFingerController.forward().then((_) {
              if (mounted) {
                setState(() {
                  _backFingerDone = true;
                  _dialogStep = 4;
                });
              }
            });
          }
        });
      }
    });
    }); // end addPostFrameCallback
  }

  Widget _buildFingerOverlay(AnimationController controller, GlobalKey targetKey) {
    final targetBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.attached) return const SizedBox.shrink();

    final targetGlobal = targetBox.localToGlobal(
      Offset(targetBox.size.width / 2, targetBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = fingerStartPos(targetGlobal, screenSize);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.2) {
          opacity = t / 0.2;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.5) {
          final glideT = (t - 0.2) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetGlobal, curved)!;
          scale = 1.0;
        } else if (t < 0.6) {
          opacity = 1.0;
          pos = targetGlobal;
          scale = 0.78;
        } else if (t < 0.7) {
          opacity = 1.0;
          pos = targetGlobal;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.7) / 0.3);
          pos = targetGlobal;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Dim app bar during dialogs (not during back step)
    final dimAppBar = _dialogStep >= 0 && _dialogStep < 3;

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: AnimatedOpacity(
          opacity: dimAppBar ? 0.25 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: AbsorbPointer(
            absorbing: _dialogStep < 4,
            child: IconButton(
              key: _backButtonKey,
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                TutorialTts.stop('cycle_back_pressed');
                Navigator.pop(context);
              },
            ),
          ),
        ),
        title: AnimatedOpacity(
          opacity: dimAppBar ? 0.25 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: Text(l10n.tutorialR1CycleExplainTitle),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Center(
              child: Column(
                children: [
                  // Round 1 winner (dimmed during finger animation + tap, unfade after results)
                  AnimatedOpacity(
                    opacity: (_dialogStep >= 1 && _dialogStep < 3) ? 0.25 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: RoundWinnerItem(
                      winnerTexts: [widget.r1Winner],
                      label: l10n.roundWinner(1),
                      isConvergence: false,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Round 2 winner (user taps this)
                  AbsorbPointer(
                    absorbing: _dialogStep < 2 || _hasOpenedResults,
                    child: KeyedSubtree(
                      key: _round2EntryKey,
                      child: RoundWinnerItem(
                        winnerTexts: [widget.r2Winner],
                        label: l10n.roundWinner(2),
                        isConvergence: false,
                        onTap: _openR2Results,
                      ),
                    ),
                  ),
                  // Dialog 1: explain
                  if (_dialogStep == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: TourTooltipCard(
                          title: l10n.tutorialR1CycleExplainTitle,
                          description: l10n.tutorialR2CycleExplainDesc,
                          onNext: _advanceToRoundFinger,
                          onSkip: _advanceToRoundFinger,
                          nextLabel: l10n.homeTourFinish,
                          skipLabel: '',
                          stepOfLabel: '',
                          stepIndex: 0,
                          totalSteps: 1,
                          autoAdvance: true,
                        ),
                      ),
                    ),
                  // Dialog 2: tap round 2
                  if (_dialogStep == 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: NoButtonTtsCard(
                          title: l10n.tutorialR1CycleExplainTitle,
                          description: l10n.tutorialR2CycleTapDesc,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Dialog: "Press back to continue" (below app bar)
          if (_dialogStep >= 4)
            Positioned(
              left: 40,
              right: 80,
              top: 16,
              child: Builder(
                builder: (context) {
                  final desc = l10n.tutorialPressBackToContinue;
                  final theme = Theme.of(context);
                  final parts = desc.split('[back]');
                  Widget? descWidget;
                  if (parts.length >= 2) {
                    final spans = <InlineSpan>[];
                    for (var i = 0; i < parts.length; i++) {
                      if (parts[i].isNotEmpty) spans.add(TextSpan(text: parts[i]));
                      if (i < parts.length - 1) {
                        spans.add(WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: theme.colorScheme.onSurface,
                          ),
                        ));
                      }
                    }
                    descWidget = Text.rich(
                      TextSpan(style: theme.textTheme.bodyMedium, children: spans),
                    );
                  }
                  return NoButtonTtsCard(
                    title: l10n.tutorialR1CycleExplainTitle,
                    description: desc,
                    descriptionWidget: descWidget,
                  );
                },
              ),
            ),
        ],
      ),
    );

    if (_dialogStep == 1 && !_roundFingerDone) {
      return Stack(children: [scaffold, _buildFingerOverlay(_roundFingerController, _round2EntryKey)]);
    }
    if (_dialogStep == 3 && !_backFingerDone) {
      return Stack(children: [scaffold, _buildFingerOverlay(_backFingerController, _backButtonKey)]);
    }

    return scaffold;
  }
}

/// Overlay widget for share demo dialogs (above QR dialog).
class _ShareOverlayWidget extends StatefulWidget {
  final GlobalKey closeButtonKey;
  final GlobalKey shareDialogKey;
  final ValueNotifier<int> dialogStep;
  final AppLocalizations l10n;

  const _ShareOverlayWidget({
    required this.closeButtonKey,
    required this.shareDialogKey,
    required this.dialogStep,
    required this.l10n,
  });

  @override
  State<_ShareOverlayWidget> createState() => _ShareOverlayWidgetState();
}

class _ShareOverlayWidgetState extends State<_ShareOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fingerController;
  bool _fingerDone = false;

  @override
  void initState() {
    super.initState();
    _fingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _fingerController.dispose();
    super.dispose();
  }

  void _startCloseFingerAnimation() {
    _fingerController.reset();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _fingerController.forward().then((_) {
        if (!mounted) return;
        setState(() => _fingerDone = true);
        widget.dialogStep.value = 2;
      });
    });
  }

  Offset? _measureCloseButton() {
    final box = widget.closeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.dialogStep,
      builder: (context, step, _) {
        if (step == 0) {
          return _buildDialog(
            widget.l10n.tutorialShareExplanation,
            autoAdvance: true,
            onNext: () {
              TutorialTts.stop('share_explain');
              widget.dialogStep.value = 1;
              _startCloseFingerAnimation();
            },
          );
        }
        if (step == 1 && !_fingerDone) {
          return _buildFingerOverlay();
        }
        if (step == 2) {
          return _buildDialog(
            widget.l10n.tutorialShareCloseDesc,
            autoAdvance: true,
            onNext: () {
              TutorialTts.stop('share_close');
              widget.dialogStep.value = 3;
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildFingerOverlay() {
    final buttonPos = _measureCloseButton();
    if (buttonPos == null) return const SizedBox.shrink();

    final startPos = Offset(buttonPos.dx, buttonPos.dy + 80);
    final targetPos = buttonPos;

    return AnimatedBuilder(
      animation: _fingerController,
      builder: (context, _) {
        final t = _fingerController.value;
        double opacity;
        Offset pos;
        double scale;

        if (t < 0.15) {
          opacity = t / 0.15;
          pos = startPos;
          scale = 1.0;
        } else if (t < 0.45) {
          final glideT = (t - 0.15) / 0.3;
          final curved = Curves.easeInOut.transform(glideT);
          opacity = 1.0;
          pos = Offset.lerp(startPos, targetPos, curved)!;
          scale = 1.0;
        } else if (t < 0.55) {
          opacity = 1.0;
          pos = targetPos;
          scale = 0.78;
        } else if (t < 0.65) {
          opacity = 1.0;
          pos = targetPos;
          scale = 1.0;
        } else {
          opacity = 1.0 - ((t - 0.65) / 0.35);
          pos = targetPos;
          scale = 1.0;
        }

        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 4,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.touch_app,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialog(String description, {required VoidCallback onNext, bool autoAdvance = true}) {
    // Measure share dialog bottom edge to position tooltip just below it
    final screenHeight = MediaQuery.of(context).size.height;
    double topPos = screenHeight * 0.75; // fallback
    final dialogBox = widget.shareDialogKey.currentContext?.findRenderObject() as RenderBox?;
    if (dialogBox != null && dialogBox.attached) {
      final dialogGlobal = dialogBox.localToGlobal(Offset.zero);
      final measuredTop = dialogGlobal.dy + dialogBox.size.height + 8;
      if (measuredTop < screenHeight - 80) {
        topPos = measuredTop;
      }
    }
    return Positioned(
      left: 16,
      right: 16,
      top: topPos,
      child: Material(
        color: Colors.transparent,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: TourTooltipCard(
            title: widget.l10n.tutorialShareTitle,
            description: description,
            onNext: onNext,
            onSkip: onNext,
            nextLabel: widget.l10n.homeTourFinish,
            skipLabel: '',
            stepOfLabel: '',
            stepIndex: 0,
            totalSteps: 1,
            autoAdvance: autoAdvance,
          ),
        ),
      ),
    );
  }
}
