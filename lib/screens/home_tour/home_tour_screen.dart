import 'package:flutter/foundation.dart';
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

class _HomeTourScreenState extends ConsumerState<HomeTourScreen> {
  // Keys for measuring widget positions
  final _bodyStackKey = GlobalKey();
  final _tooltipKey = GlobalKey();
  final _welcomeHeaderKey = GlobalKey();
  final _searchBarKey = GlobalKey();
  final _exploreKey = GlobalKey();
  final _pendingKey = GlobalKey();
  final _chatsKey = GlobalKey();

  // Animated tooltip position
  double _tooltipTop = 0;
  double _tooltipRight = 16;
  bool _measured = false;

  /// Whether [step] targets an app bar button (not body cards or FAB).
  bool _isAppBarStep(HomeTourStep step) {
    return step == HomeTourStep.exploreButton ||
        step == HomeTourStep.languageSelector ||
        step == HomeTourStep.howItWorks ||
        step == HomeTourStep.legalDocs;
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

    if (kDebugMode) {
      debugPrint('[HomeTourScreen] build: step=$step '
          'index=${tourState.stepIndex}/${tourState.totalSteps}');
    }

    if (step == HomeTourStep.complete) {
      if (kDebugMode) {
        debugPrint('[HomeTourScreen] tour complete, calling onComplete');
      }
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
          // Order matches real home screen: Explore, Language, How It Works, Legal Docs
          _appBarButton(
            key: _exploreKey,
            step: step,
            activeOn: HomeTourStep.exploreButton,
            child: IconButton(
              icon: const Icon(Icons.explore),
              tooltip: l10n.discoverChats,
              onPressed: () {},
            ),
          ),
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
            activeOn: HomeTourStep.howItWorks,
            child: IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: l10n.howItWorks,
              onPressed: () {},
            ),
          ),
          _appBarButton(
            step: step,
            activeOn: HomeTourStep.legalDocs,
            child: IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: l10n.legalDocuments,
              onPressed: () {},
            ),
          ),
          // Exit tutorial button (always visible)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.homeTourSkip,
            onPressed: () => ref.read(homeTourNotifierProvider.notifier).skip(),
          ),
        ],
      ),
      floatingActionButton: showFab
          ? AnimatedOpacity(
              opacity: step == HomeTourStep.createFab ? 1.0 : 0.25,
              duration: const Duration(milliseconds: 250),
              child: FloatingActionButton(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
            )
          : null,
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
                  pendingRequestKey: _pendingKey,
                  yourChatsKey: _chatsKey,
                ),
              ),
            ),
            // Animated tooltip overlay
            if (_measured && step != HomeTourStep.complete)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                left: 16,
                right: _tooltipRight,
                top: _tooltipTop,
                child: KeyedSubtree(
                  key: _tooltipKey,
                  child: _buildTooltip(context, tourState, l10n),
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
      opacity = 1.0; // Currently spotlighted
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
    if (stackBox == null) {
      if (kDebugMode) {
        debugPrint('[Tour] stackBox is null, cannot measure');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('[Tour] === Measuring for step=$step ===');
      debugPrint('[Tour] Stack size: ${stackBox.size}');
    }

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

      // exploreButton is an app bar step — tooltip at top of body
      case HomeTourStep.exploreButton:
        newTop = 8;

      case HomeTourStep.pendingRequest:
      case HomeTourStep.yourChats:
        GlobalKey targetKey;
        if (step == HomeTourStep.pendingRequest) {
          targetKey = _pendingKey;
        } else {
          targetKey = _chatsKey;
        }
        final cardBox =
            targetKey.currentContext?.findRenderObject() as RenderBox?;
        if (cardBox == null) return;
        final pos =
            cardBox.localToGlobal(Offset.zero, ancestor: stackBox);
        newTop = pos.dy + cardBox.size.height + 12;

      case HomeTourStep.createFab:
        final tooltipBox =
            _tooltipKey.currentContext?.findRenderObject() as RenderBox?;
        final tooltipH = tooltipBox?.size.height ?? 180;
        // Account for FAB (56px) + FAB bottom padding (16px) + gap (16px)
        const fabClearance = 56.0 + 16.0 + 16.0;
        newTop = stackBox.size.height - tooltipH - fabClearance;
        newRight = 16;
        if (kDebugMode) {
          debugPrint('[Tour] FAB step: stackH=${stackBox.size.height}, '
              'tooltipH=$tooltipH, fabClearance=$fabClearance, newTop=$newTop');
        }

      // All app bar steps: tooltip at top of body
      case HomeTourStep.howItWorks:
      case HomeTourStep.legalDocs:
        newTop = 8;

      case HomeTourStep.complete:
        return;
    }

    // Keep tooltip within visible bounds
    final tooltipBox =
        _tooltipKey.currentContext?.findRenderObject() as RenderBox?;
    final tooltipH = tooltipBox?.size.height ?? 180;
    final maxTop = stackBox.size.height - tooltipH - 8;
    newTop = newTop.clamp(0.0, maxTop);

    if ((newTop - _tooltipTop).abs() > 0.5 ||
        (newRight - _tooltipRight).abs() > 0.5 ||
        !_measured) {
      setState(() {
        _tooltipTop = newTop;
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
      case HomeTourStep.exploreButton:
        title = l10n.homeTourExploreButtonTitle;
        description = l10n.homeTourExploreButtonDesc;
      case HomeTourStep.pendingRequest:
        title = l10n.homeTourPendingRequestTitle;
        description = l10n.homeTourPendingRequestDesc;
      case HomeTourStep.yourChats:
        title = l10n.homeTourYourChatsTitle;
        description = l10n.homeTourYourChatsDesc;
      case HomeTourStep.createFab:
        title = l10n.homeTourCreateFabTitle;
        description = l10n.homeTourCreateFabDesc;
      case HomeTourStep.howItWorks:
        title = l10n.homeTourHowItWorksTitle;
        description = l10n.homeTourHowItWorksDesc;
      case HomeTourStep.legalDocs:
        title = l10n.homeTourLegalDocsTitle;
        description = l10n.homeTourLegalDocsDesc;
      case HomeTourStep.complete:
        return const SizedBox.shrink();
    }

    return TourTooltipCard(
      title: title,
      description: description,
      onNext: () => ref.read(homeTourNotifierProvider.notifier).nextStep(),
      onSkip: () => ref.read(homeTourNotifierProvider.notifier).skip(),
      stepIndex: tourState.stepIndex,
      totalSteps: tourState.totalSteps,
      nextLabel: isLastStep ? l10n.homeTourFinish : l10n.homeTourNext,
      skipLabel: l10n.homeTourSkip,
      stepOfLabel: l10n.homeTourStepOf(
        tourState.stepIndex + 1,
        tourState.totalSteps,
      ),
    );
  }
}
