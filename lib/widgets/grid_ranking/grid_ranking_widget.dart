import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'grid_ranking_model.dart';
import 'grid_ranking_painter.dart';
import 'proposition_card.dart';
import 'stacked_proposition_card.dart';

/// Constants for layout calculations
class GridRankingConstants {
  static const double proposedMessageMaxHeight = 150.0;
  static const double safetyMargin = 20.0;
  static const double topPadding = (proposedMessageMaxHeight / 2) + safetyMargin;
  static const double bottomPadding = (proposedMessageMaxHeight / 2) + safetyMargin;

  static final Map<String, GlobalKey> _stackedCardKeys = {};

  static GlobalKey getStackKey(double position) {
    final key = 'stack_${position.toStringAsFixed(1)}';
    return _stackedCardKeys.putIfAbsent(key, () => GlobalKey(debugLabel: key));
  }
}

/// Grid ranking widget for interactive proposition ranking
class GridRankingWidget extends StatefulWidget {
  final List<Map<String, dynamic>> propositions;
  final Function(Map<String, double>) onRankingComplete;
  final Function(int currentPlacing, int total)? onCounterUpdate;

  /// Callback when a placement is confirmed (for lazy loading)
  final void Function()? onPlacementConfirmed;

  /// Callback when undo removes a proposition (for lazy loading to re-fetch)
  final void Function(String removedId)? onUndo;

  /// Callback to save rankings after each placement
  /// Parameters: rankings map (id -> position), whether all positions changed
  final void Function(Map<String, double> rankings, bool allPositionsChanged)? onSaveRankings;

  /// Whether lazy loading mode is enabled
  final bool lazyLoadingMode;

  /// Whether resuming from saved rankings (propositions include 'position' field)
  final bool isResuming;

  /// Read-only mode for viewing results (no editing controls, only zoom/pan)
  final bool readOnly;

  const GridRankingWidget({
    super.key,
    required this.propositions,
    required this.onRankingComplete,
    this.onCounterUpdate,
    this.onPlacementConfirmed,
    this.onUndo,
    this.onSaveRankings,
    this.lazyLoadingMode = false,
    this.isResuming = false,
    this.readOnly = false,
  });

  @override
  State<GridRankingWidget> createState() => GridRankingWidgetState();
}

/// State class for GridRankingWidget, exposed for lazy loading operations
class GridRankingWidgetState extends State<GridRankingWidget>
    with TickerProviderStateMixin {
  late GridRankingModel _model;
  final ScrollController _scrollController = ScrollController();

  double _zoomLevel = 1.0;
  Timer? _moveTimer;
  double? _lastAvailableHeight;
  double? _lastConstraintsHeight;
  int _lastPropositionCount = 0;
  bool _hasAutoSubmitted = false;
  double _currentScrollOffset = 0.0;

  @override
  void initState() {
    super.initState();

    _model = GridRankingModel(
      widget.propositions,
      onPlacementConfirmed: widget.onPlacementConfirmed,
      onUndo: widget.onUndo,
      onSaveRankings: widget.onSaveRankings,
      lazyLoadingMode: widget.lazyLoadingMode,
      isResuming: widget.isResuming,
    );
    _model.addListener(_onModelChange);
    _lastPropositionCount = _model.rankedPropositions.length;

    if (widget.onCounterUpdate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onCounterUpdate!(
            _model.rankedPropositions.length, _model.totalPropositions);
      });
    }

    // Handle deferred fetch for resume mode (callback couldn't be called during construction)
    if (_model.needsFetchAfterInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _model.clearNeedsFetchAfterInit();
        widget.onPlacementConfirmed?.call();
      });
    }

    _scrollController.addListener(() {
      setState(() {
        _currentScrollOffset = _scrollController.offset;
      });
    });
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    _model.removeListener(_onModelChange);
    _model.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Add a proposition dynamically (for lazy loading)
  void addProposition(Map<String, dynamic> proposition) {
    _model.addProposition(proposition);
  }

  /// Signal that no more propositions are available
  void setNoMorePropositions() {
    _model.setNoMorePropositions();
  }

  /// Get current rankings (for manual submit if needed)
  Map<String, double> getCurrentRankings() {
    return _model.getFinalRankings();
  }

  void _onModelChange() {
    final currentPropositionCount = _model.rankedPropositions.length;
    if (currentPropositionCount != _lastPropositionCount) {
      _zoomLevel = 1.0;
      _lastPropositionCount = currentPropositionCount;
      _currentScrollOffset = 0.0;

      if (_scrollController.hasClients) {
        if (_scrollController.position.isScrollingNotifier.value) {
          _scrollController.jumpTo(_scrollController.offset);
        }
        _scrollController.jumpTo(0.0);
      }
    }

    if (widget.onCounterUpdate != null) {
      widget.onCounterUpdate!(
          _model.rankedPropositions.length, _model.totalPropositions);
    }

    setState(() {});

    // Auto-submit when complete and all propositions are ranked
    // In lazy loading mode, check model.isComplete which accounts for morePropositionsExpected
    if (_model.phase == RankingPhase.completed &&
        _model.isComplete &&
        !_hasAutoSubmitted) {
      _hasAutoSubmitted = true;
      _autoSubmitRankings();
    }
  }

  Future<void> _autoSubmitRankings() async {
    final rankings = _model.getFinalRankings();
    await widget.onRankingComplete(rankings);
  }

  void _zoomIn() {
    if (_lastAvailableHeight == null || _lastConstraintsHeight == null) {
      setState(() {
        _zoomLevel = (_zoomLevel * 1.25).clamp(1.0, 15.0);
      });
      return;
    }

    final oldZoom = _zoomLevel;
    final newZoom = (oldZoom * 1.25).clamp(1.0, 15.0);

    if (oldZoom == newZoom) return;

    final activeProposition = _model.rankedPropositions.firstWhere(
      (p) => p.isActive,
      orElse: () => _model.rankedPropositions.first,
    );

    final activeCount = _model.rankedPropositions.where((p) => p.isActive).length;

    setState(() {
      _zoomLevel = newZoom;
    });

    if (activeCount != 1) return;

    final normalizedPosition = activeProposition.position / 100.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final newGridHeight = _lastAvailableHeight! * newZoom;
      final viewportHeight = _lastConstraintsHeight!;
      final messageY = (1 - normalizedPosition) * newGridHeight;
      final cardHalfHeight = GridRankingConstants.proposedMessageMaxHeight / 2;
      final cardTop = messageY - cardHalfHeight;
      final cardBottom = messageY + cardHalfHeight;

      var targetScroll = messageY - (viewportHeight / 2);

      if (cardBottom > targetScroll + viewportHeight) {
        targetScroll = cardBottom - viewportHeight;
      }
      if (cardTop < targetScroll) {
        targetScroll = cardTop;
      }

      final clampedScroll =
          targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(clampedScroll);

      setState(() {
        _currentScrollOffset = clampedScroll;
      });
    });
  }

  void _zoomOut() {
    if (_lastAvailableHeight == null || _lastConstraintsHeight == null) {
      setState(() {
        _zoomLevel = (_zoomLevel / 1.25).clamp(1.0, 15.0);
      });
      return;
    }

    final oldZoom = _zoomLevel;
    final newZoom = (oldZoom / 1.25).clamp(1.0, 15.0);

    if (oldZoom == newZoom) return;

    final activeProposition = _model.rankedPropositions.firstWhere(
      (p) => p.isActive,
      orElse: () => _model.rankedPropositions.first,
    );

    final activeCount = _model.rankedPropositions.where((p) => p.isActive).length;

    setState(() {
      _zoomLevel = newZoom;
    });

    if (activeCount != 1) return;

    final normalizedPosition = activeProposition.position / 100.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final newGridHeight = _lastAvailableHeight! * newZoom;
      final viewportHeight = _lastConstraintsHeight!;
      final messageY = (1 - normalizedPosition) * newGridHeight;
      final cardHalfHeight = GridRankingConstants.proposedMessageMaxHeight / 2;
      final cardTop = messageY - cardHalfHeight;
      final cardBottom = messageY + cardHalfHeight;

      var targetScroll = messageY - (viewportHeight / 2);

      if (cardBottom > targetScroll + viewportHeight) {
        targetScroll = cardBottom - viewportHeight;
      }
      if (cardTop < targetScroll) {
        targetScroll = cardTop;
      }

      final clampedScroll =
          targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(clampedScroll);

      setState(() {
        _currentScrollOffset = clampedScroll;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, gridConstraints) {
                  return _buildGridArea(gridConstraints);
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              child: _buildControls(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGridArea(BoxConstraints constraints) {
    final theme = Theme.of(context);
    final availableHeight = constraints.maxHeight;
    final gridHeight = availableHeight * _zoomLevel;

    _lastAvailableHeight = availableHeight;
    _lastConstraintsHeight = constraints.maxHeight;

    return SingleChildScrollView(
      controller: _scrollController,
      child: SizedBox(
        height: gridHeight,
        child: Stack(
          children: [
            // Border decoration
            Positioned(
              top: 75,
              left: 0,
              right: 0,
              bottom: 75,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha:0.3),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

            // Content layer
            Positioned.fill(
              child: Stack(
                children: [
                  // Grid background
                  Positioned(
                    top: 75,
                    left: 0,
                    right: 0,
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, gridHeight - 150),
                      painter: GridRankingPainter(
                        propositions: _model.rankedPropositions,
                        scrollOffset: _currentScrollOffset - 75,
                        gridColor: theme.colorScheme.outline,
                        activeColor: theme.colorScheme.primary,
                        labelStyle: theme.textTheme.bodyMedium!,
                        viewportHeight: constraints.maxHeight,
                        activePosition: _model.rankedPropositions
                                .any((p) => p.isActive)
                            ? _model.rankedPropositions
                                .firstWhere((p) => p.isActive)
                                .position
                            : null,
                      ),
                    ),
                  ),

                  // Proposition cards
                  Positioned.fill(
                    child: Row(
                      children: [
                        const SizedBox(width: 30),
                        Expanded(
                          child: Stack(
                            children: _buildPropositionCards(gridHeight),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPropositionCards(double availableHeight) {
    final theme = Theme.of(context);

    // Sort so active is rendered last (on top)
    final sortedPropositions =
        List<RankingProposition>.from(_model.rankedPropositions);
    sortedPropositions.sort((a, b) {
      if (a.isActive && !b.isActive) return 1;
      if (!a.isActive && b.isActive) return -1;
      return 0;
    });

    return sortedPropositions.map((proposition) {
      const buffer = 75.0;
      final stackHeight = availableHeight - (buffer * 2);
      final yPercent = 1 - (proposition.position / 100);
      final yPosition = (yPercent * stackHeight) + buffer;

      final roundedPos = (proposition.position * 10).round() / 10;
      final stack = _model.getStackAtPosition(proposition.position);
      final isDefaultCard = stack?.defaultCardId == proposition.id;

      final activeProp = _model.rankedPropositions.firstWhere(
        (p) => p.isActive,
        orElse: () => proposition,
      );
      final activeRoundedPos = (activeProp.position * 10).round() / 10;
      final activeAtThisPosition =
          roundedPos == activeRoundedPos && activeProp.id != proposition.id;

      Widget cardWidget;
      bool shouldHide = false;

      if (proposition.isActive && stack != null) {
        final allCardsInStack = _model.rankedPropositions
            .where((p) => ((p.position * 10).round() / 10) == roundedPos)
            .toList();

        final actualDefaultCard = allCardsInStack.firstWhere(
          (p) => p.id == stack.defaultCardId,
          orElse: () => proposition,
        );

        final stackKey = GridRankingConstants.getStackKey(stack.position);
        cardWidget = StackedPropositionCard(
          key: stackKey,
          defaultCard: actualDefaultCard,
          allCardsInStack: allCardsInStack,
          isActive: actualDefaultCard.isActive,
          model: _model,
        );
      } else if (stack != null && isDefaultCard && !activeAtThisPosition) {
        final allCardsInStack = _model.rankedPropositions
            .where((p) => ((p.position * 10).round() / 10) == roundedPos)
            .toList();

        final actualDefaultCard = allCardsInStack.firstWhere(
          (p) => p.id == stack.defaultCardId,
          orElse: () => proposition,
        );

        final stackKey = GridRankingConstants.getStackKey(stack.position);
        cardWidget = StackedPropositionCard(
          key: stackKey,
          defaultCard: actualDefaultCard,
          allCardsInStack: allCardsInStack,
          isActive: actualDefaultCard.isActive,
          model: _model,
        );
      } else if (stack != null && (!isDefaultCard || activeAtThisPosition)) {
        shouldHide = true;
        cardWidget = PropositionCard(
          proposition: proposition,
          isActive: proposition.isActive,
          isBinaryPhase: _model.phase == RankingPhase.binary,
          activeGlowColor: theme.colorScheme.primary,
        );
      } else {
        cardWidget = PropositionCard(
          proposition: proposition,
          isActive: proposition.isActive,
          isBinaryPhase: _model.phase == RankingPhase.binary,
          activeGlowColor: theme.colorScheme.primary,
        );
      }

      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        top: yPosition,
        left: 0,
        right: 0,
        child: FractionalTranslation(
          translation: const Offset(0, -0.5),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Opacity(
                opacity: shouldHide ? 0.0 : 1.0,
                child: cardWidget,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildControls() {
    // In readOnly mode, only show zoom controls
    if (widget.readOnly) {
      return _buildZoomControls();
    }
    return _model.phase == RankingPhase.binary
        ? _buildBinaryControls()
        : _buildPositioningControls();
  }

  Widget _buildZoomControls() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: GestureDetector(
                onTap: _zoomIn,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.zoom_in,
                    size: 25,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 1.0,
              child: GestureDetector(
                onTap: _zoomOut,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.zoom_out,
                    size: 25,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBinaryControls() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha:0.5),
          width: 1,
        ),
      ),
      child: SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Swap button
            AspectRatio(
              aspectRatio: 1.0,
              child: GestureDetector(
                onTap: _model.swapBinaryPositions,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.swap_vert,
                    size: 25,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Confirm button
            AspectRatio(
              aspectRatio: 1.0,
              child: GestureDetector(
                onTap: _model.confirmBinaryChoice,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 25,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositioningControls() {
    final theme = Theme.of(context);
    final controlsDisabled = _model.areControlsDisabled;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom controls
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha:0.5),
                width: 1,
              ),
            ),
            child: SizedBox(
              width: 40,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: GestureDetector(
                      onTap: _zoomIn,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(alpha:0.5),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.zoom_in,
                          size: 25,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: GestureDetector(
                      onTap: _zoomOut,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(alpha:0.5),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.zoom_out,
                          size: 25,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Movement controls
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha:0.5),
                width: 1,
              ),
            ),
            child: SizedBox(
              width: 40,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Arrow up
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: GestureDetector(
                      onTapDown:
                          controlsDisabled ? null : (_) => _startContinuousMove(1),
                      onTapUp: controlsDisabled ? null : (_) => _stopContinuousMove(),
                      onTapCancel:
                          controlsDisabled ? () {} : () => _stopContinuousMove(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_upward,
                          size: 25,
                          color: controlsDisabled
                              ? theme.colorScheme.outline
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Place button
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: GestureDetector(
                      onTap: controlsDisabled ? null : _model.confirmPlacement,
                      child: Container(
                        decoration: BoxDecoration(
                          color: controlsDisabled
                              ? theme.colorScheme.outline.withValues(alpha:0.3)
                              : theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 25,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Arrow down
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: GestureDetector(
                      onTapDown:
                          controlsDisabled ? null : (_) => _startContinuousMove(-1),
                      onTapUp: controlsDisabled ? null : (_) => _stopContinuousMove(),
                      onTapCancel:
                          controlsDisabled ? () {} : () => _stopContinuousMove(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_downward,
                          size: 25,
                          color: controlsDisabled
                              ? theme.colorScheme.outline
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Undo button
          if (_model.rankedPropositions.length > 2) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF8B0000).withValues(alpha:0.5),
                  width: 1,
                ),
              ),
              child: SizedBox(
                width: 40,
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: GestureDetector(
                    onTap: controlsDisabled ? null : _model.undoLastPlacement,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF8B0000).withValues(alpha:0.5),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.undo,
                        size: 25,
                        color: const Color(0xFF8B0000).withValues(alpha:0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _startContinuousMove(double delta) {
    if (_model.phase != RankingPhase.positioning) return;

    _model.moveActiveProposition(delta);
    _moveTimer?.cancel();

    int holdDuration = 0;

    _moveTimer = Timer(const Duration(milliseconds: 300), () {
      _moveTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        holdDuration++;

        double acceleration = 1.0;
        if (holdDuration > 10) acceleration = 2.0;
        if (holdDuration > 20) acceleration = 4.0;
        if (holdDuration > 30) acceleration = 8.0;
        if (holdDuration > 40) acceleration = 16.0;
        if (holdDuration > 60) acceleration = 32.0;
        if (holdDuration > 80) acceleration = 64.0;
        if (holdDuration > 100) {
          acceleration = pow(2, holdDuration / 20).toDouble();
        }

        _model.moveActiveProposition(delta * acceleration);
      });
    });
  }

  void _stopContinuousMove() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }
}
