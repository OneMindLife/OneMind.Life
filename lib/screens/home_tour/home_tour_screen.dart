import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/providers.dart';
import 'models/home_tour_state.dart';
import 'widgets/mock_home_content.dart';
import 'widgets/spotlight_overlay.dart';

/// Home screen tour that walks new users through each UI element.
/// Progressively builds the screen widget-by-widget. The tooltip
/// animates between positions using [AnimatedPositioned] in a Stack.
class HomeTourScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;

  const HomeTourScreen({super.key, this.onComplete});

  @override
  ConsumerState<HomeTourScreen> createState() => _HomeTourScreenState();
}

class _HomeTourScreenState extends ConsumerState<HomeTourScreen>
    with SingleTickerProviderStateMixin {
  // Keys for measuring widget positions
  final _bodyStackKey = GlobalKey();
  final _tooltipKey = GlobalKey();
  final _welcomeHeaderKey = GlobalKey();
  final _searchBarKey = GlobalKey();

  final _chatsKey = GlobalKey();
  final _pendingKey = GlobalKey();
  final _fabKey = GlobalKey();

  // Animated tooltip position — top for most steps, bottom for FAB step
  double? _tooltipTop = 0;
  double? _tooltipBottom;
  double _tooltipRight = 16;
  bool _measured = false;

  // Tooltip fade controller — sequential fade-out → fade-in
  late final AnimationController _tooltipFadeController;
  bool _tooltipTransitioning = false;

  @override
  void initState() {
    super.initState();
    _tooltipFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1.0,
    );
    // Reset tour state in case it's stale from a previous completion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(homeTourNotifierProvider.notifier).reset();
      }
    });
  }

  @override
  void dispose() {
    _tooltipFadeController.dispose();
    super.dispose();
  }

  /// Fade out tooltip → advance step → fade in new tooltip
  void _advanceHomeTourStep() {
    if (_tooltipTransitioning) return;
    setState(() => _tooltipTransitioning = true);
    _tooltipFadeController.reverse().then((_) {
      if (!mounted) return;
      ref.read(homeTourNotifierProvider.notifier).nextStep();
      final toStep = ref.read(homeTourNotifierProvider).currentStep;
      // Pre-set FAB position before rebuild to prevent jitter
      if (toStep == HomeTourStep.createFab) {
        _tooltipTop = null;
        _tooltipBottom = 80; // FAB bottom(16) + height(56) + gap(8)
      }
      setState(() => _tooltipTransitioning = false);
      // Element appears first, then tooltip fades in after delay
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          _updateTooltipPosition();
          _tooltipFadeController.forward();
        }
      });
    });
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
      ref.read(homeTourNotifierProvider.notifier).skip();
    }
  }

  /// Whether [step] targets an app bar button (not body cards or FAB).
  bool _isAppBarStep(HomeTourStep step) {
    return step == HomeTourStep.languageSelector ||
        step == HomeTourStep.tutorialButton ||
        step == HomeTourStep.menu;
  }

  /// Whether the body cards should be dimmed (FAB or app bar is active).
  bool _shouldDimBody(HomeTourStep step) {
    return step == HomeTourStep.createFab || _isAppBarStep(step);
  }

  @override
  Widget build(BuildContext context) {
    final tourState = ref.watch(homeTourNotifierProvider);
    final l10n = AppLocalizations.of(context);
    final step = tourState.currentStep;

    if (step == HomeTourStep.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onComplete?.call();
      });
    }

    // Measure tooltip position after layout
    if (step != HomeTourStep.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateTooltipPosition();
      });
    }

    // FAB visibility (only during createFab step and beyond, not on complete)
    final showFab = step.index >= HomeTourStep.createFab.index &&
        step != HomeTourStep.complete;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: AnimatedOpacity(
          opacity: 0.25,
          duration: const Duration(milliseconds: 250),
          child: Text(l10n.appTitle),
        ),
        actions: [
          // All buttons always rendered (fixed positions, no shifting).
          // Opacity: 0.0 before step, 1.0 on step, 0.25 after.
          // Order matches real home screen: Language, How It Works, Legal Docs
          _appBarButton(
            step: step,
            activeOn: HomeTourStep.languageSelector,
            child: IconButton(
              icon: const Icon(Icons.language),
              tooltip: l10n.language,
              onPressed: () {},
            ),
          ),
          _appBarButton(
            step: step,
            activeOn: HomeTourStep.tutorialButton,
            child: IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: l10n.howItWorks,
              onPressed: () {},
            ),
          ),
          _appBarButton(
            step: step,
            activeOn: HomeTourStep.menu,
            child: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {},
            ),
          ),
          // Exit tutorial button (always visible)
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: l10n.homeTourSkip,
            onPressed: _showSkipConfirmation,
          ),
        ],
      ),
      body: SizedBox.expand(
        child: Stack(
          key: _bodyStackKey,
          children: [
            // Cards layer — fills the Stack
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _shouldDimBody(step) ? 0.25 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: MockHomeContent(
                  currentStep: step,
                  welcomeHeaderKey: _welcomeHeaderKey,
                  searchBarKey: _searchBarKey,
                  yourChatsKey: _chatsKey,
                  pendingRequestKey: _pendingKey,
                ),
              ),
            ),
            // Mock FAB — always in tree for stable layout; invisible before its step
            Positioned(
              right: 16,
              bottom: 16,
              child: AnimatedOpacity(
                opacity: !showFab
                    ? 0.0
                    : step == HomeTourStep.createFab
                        ? (_tooltipTransitioning ? 0.25 : 1.0)
                        : 0.25,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !showFab,
                  child: FloatingActionButton(
                    key: _fabKey,
                    onPressed: () {},
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ),
            // Tooltip overlay — fades out/in between steps
            if (_measured && step != HomeTourStep.complete)
              Positioned(
                left: 16,
                right: _tooltipRight,
                top: _tooltipTop,
                bottom: _tooltipBottom,
                child: FadeTransition(
                  opacity: _tooltipFadeController,
                  child: KeyedSubtree(
                    key: _tooltipKey,
                    child: _buildTooltip(context, tourState, l10n),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// An app bar action button with 3 opacity states:
  /// - Before its step: 0.0 (invisible, but maintains layout space)
  /// - On its step: 1.0 (bright, highlighted)
  /// - After its step: 0.25 (dimmed)
  Widget _appBarButton({
    Key? key,
    required HomeTourStep step,
    required HomeTourStep activeOn,
    required Widget child,
  }) {
    double opacity;
    if (step.index < activeOn.index) {
      opacity = 0.0; // Not yet introduced
    } else if (step == activeOn) {
      opacity = _tooltipTransitioning ? 0.25 : 1.0; // Dim with tooltip fade-out
    } else {
      opacity = 0.25; // Already introduced
    }
    return KeyedSubtree(
      key: key,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 250),
        child: child,
      ),
    );
  }

  void _updateTooltipPosition() {
    final step = ref.read(homeTourNotifierProvider).currentStep;
    final stackBox =
        _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    double newTop;
    double newRight = 16;

    switch (step) {
      case HomeTourStep.welcomeName:
        final targetBox =
            _welcomeHeaderKey.currentContext?.findRenderObject() as RenderBox?;
        if (targetBox == null) return;
        final pos = targetBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = pos.dy + targetBox.size.height + 12;

      case HomeTourStep.searchBar:
        final targetBox =
            _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
        if (targetBox == null) return;
        final pos = targetBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = pos.dy + targetBox.size.height + 12;

      // languageSelector is an app bar step — tooltip at top of body
      case HomeTourStep.languageSelector:
        newTop = 8;

      case HomeTourStep.yourChats:
        final cardBox =
            _chatsKey.currentContext?.findRenderObject() as RenderBox?;
        if (cardBox == null) return;
        final pos =
            cardBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = pos.dy + cardBox.size.height + 12;

      case HomeTourStep.pendingRequest:
        final pendingBox =
            _pendingKey.currentContext?.findRenderObject() as RenderBox?;
        if (pendingBox == null) return;
        final pos =
            pendingBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = pos.dy + pendingBox.size.height + 12;

      case HomeTourStep.createFab:
        // Anchor from bottom — FAB is at bottom:16, height 56
        // Tooltip sits 8px above FAB top edge, grows upward
        const fabBottomPad = 16.0;
        const fabHeight = 56.0;
        const gap = 8.0;
        _tooltipBottom = fabBottomPad + fabHeight + gap;
        _tooltipTop = null;
        _tooltipRight = 16;
        if (!_measured) setState(() => _measured = true);
        return;

      // All app bar steps: tooltip at top of body
      case HomeTourStep.tutorialButton:
        newTop = 8;

      case HomeTourStep.menu:
        newTop = 8;

      case HomeTourStep.complete:
        return;
    }

    // Keep tooltip within visible bounds (don't go above or below the stack)
    final tooltipBox =
        _tooltipKey.currentContext?.findRenderObject() as RenderBox?;
    final tooltipH = tooltipBox?.size.height ?? 180;
    final maxTop = stackBox.size.height - tooltipH - 8;
    newTop = newTop.clamp(0.0, maxTop);


    final oldTop = _tooltipTop ?? 0;
    if ((newTop - oldTop).abs() > 0.5 ||
        (newRight - _tooltipRight).abs() > 0.5 ||
        _tooltipBottom != null ||
        !_measured) {
      setState(() {
        _tooltipTop = newTop;
        _tooltipBottom = null;
        _tooltipRight = newRight;
        _measured = true;
      });
    }
  }

  Widget _buildTooltip(
    BuildContext context,
    HomeTourState tourState,
    AppLocalizations l10n,
  ) {
    final isLastStep = tourState.stepIndex == HomeTourState.total - 1;

    String title;
    String description;
    Widget? descriptionWidget;
    switch (tourState.currentStep) {
      case HomeTourStep.welcomeName:
        title = l10n.homeTourWelcomeNameTitle;
        description = l10n.homeTourWelcomeNameDesc;
      case HomeTourStep.languageSelector:
        title = l10n.homeTourLanguageSelectorTitle;
        description = l10n.homeTourLanguageSelectorDesc;
      case HomeTourStep.searchBar:
        title = l10n.homeTourSearchBarTitle;
        description = l10n.homeTourSearchBarDesc;
      case HomeTourStep.yourChats:
        title = l10n.homeTourYourChatsTitle;
        description = l10n.homeTourYourChatsDesc;
      case HomeTourStep.pendingRequest:
        title = l10n.homeTourPendingRequestTitle;
        description = l10n.homeTourPendingRequestDesc;
      case HomeTourStep.createFab:
        title = l10n.homeTourCreateFabTitle;
        description = l10n.homeTourCreateFabDesc;
        descriptionWidget = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AbsorbPointer(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: FloatingActionButton(
                      onPressed: () {},
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.homeTourCreateFabDesc,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        );
      case HomeTourStep.tutorialButton:
        title = l10n.homeTourTutorialButtonTitle;
        description = l10n.homeTourTutorialButtonDesc;
      case HomeTourStep.menu:
        title = l10n.homeTourMenuTitle;
        description = l10n.homeTourMenuDesc;
      case HomeTourStep.complete:
        return const SizedBox.shrink();
    }

    return TourTooltipCard(
      title: title,
      description: description,
      descriptionWidget: descriptionWidget,
      onNext: _advanceHomeTourStep,
      onSkip: () => ref.read(homeTourNotifierProvider.notifier).skip(),
      stepIndex: tourState.stepIndex,
      totalSteps: tourState.totalSteps,
      nextLabel: isLastStep ? l10n.homeTourFinish : l10n.homeTourNext,
      autoAdvance: true,
      skipLabel: l10n.homeTourSkip,
      stepOfLabel: l10n.homeTourStepOf(
        tourState.stepIndex + 1,
        tourState.totalSteps,
      ),
    );
  }
}
