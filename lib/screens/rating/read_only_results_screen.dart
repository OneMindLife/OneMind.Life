import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../screens/home_tour/widgets/spotlight_overlay.dart';
import '../../widgets/rating/rating_model.dart';
import '../../widgets/rating/rating_widget.dart';

/// Read-only results screen showing propositions with their final ratings.
/// Used for viewing round results after rating completes.
class ReadOnlyResultsScreen extends StatefulWidget {
  final List<Proposition> propositions;
  final int roundNumber;
  final int? roundId;
  final int? myParticipantId;

  /// Distinct rater count for this round. When non-null, shown as a subtitle
  /// under the AppBar title. Omitted in tutorial contexts where there are no
  /// real raters.
  final int? raterCount;

  /// Whether to show a tutorial hint overlay
  final bool showTutorialHint;

  /// Winner name to display in tutorial hint (e.g. "Community Garden won!")
  final String? tutorialWinnerName;

  /// Optional custom title for the tutorial hint (overrides default)
  final String? tutorialHintTitle;

  /// Optional custom description for the tutorial hint (overrides default)
  final String? tutorialHintDescription;

  /// Optional rating value to position hint near (instead of winner).
  /// Used to position dialog near a specific proposition in the grid.
  final double? tutorialHintTargetRating;

  /// Callback to exit the tutorial (shows close button in AppBar when set)
  final VoidCallback? onExitTutorial;

  const ReadOnlyResultsScreen({
    super.key,
    required this.propositions,
    required this.roundNumber,
    this.roundId,
    this.myParticipantId,
    this.raterCount,
    this.showTutorialHint = false,
    this.tutorialWinnerName,
    this.tutorialHintTitle,
    this.tutorialHintDescription,
    this.tutorialHintTargetRating,
    this.onExitTutorial,
  });

  @override
  State<ReadOnlyResultsScreen> createState() =>
      _ReadOnlyResultsScreenState();
}

class _ReadOnlyResultsScreenState extends State<ReadOnlyResultsScreen>
    with TickerProviderStateMixin {
  late RatingModel _model;
  late final AnimationController _fadeController;
  double? _hintTop;

  // Back arrow finger animation
  late final AnimationController _fingerController;
  bool _fingerDone = false;
  final GlobalKey _backButtonKey = GlobalKey();

  // 0 = first dialog (winner), 1 = finger animation, 2 = second dialog (back), 3 = dismissed
  int _resultsDialogStep = 0;
  bool _hintReady = false;

  /// Build a rich text widget replacing [back] with an inline arrow icon.
  Widget? _buildHintDescriptionWidget(String text, ThemeData theme) {
    final parts = text.split('[back]');
    if (parts.length < 2) return null;
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
    return Text.rich(
      TextSpan(style: theme.textTheme.bodyMedium, children: spans),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeModel();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fingerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2125),
    );
    _fadeController.forward().then((_) {
      if (mounted && widget.showTutorialHint) {
        // Measure winning proposition position after layout settles
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _measureWinnerPosition();
        });
        // Delay after fade-in before showing dialog (let grid settle)
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            setState(() => _hintReady = true);
          }
        });
      }
    });
  }

  void _advanceToFingerAnimation() {
    setState(() => _resultsDialogStep = 1);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _fingerController.forward().then((_) {
          if (mounted) {
            setState(() {
              _fingerDone = true;
              _resultsDialogStep = 2;
            });
          }
        });
      }
    });
  }

  void _initializeModel() {
    final propositionMaps = widget.propositions.map((p) => {
      'id': p.id,
      'content': p.displayContent,
      'finalRating': p.finalRating ?? 50.0,
    }).toList();

    _model = RatingModel.fromResults(propositionMaps);
  }

  @override
  void dispose() {
    // Don't stop TTS — next screen's dialog may already be speaking
    _fadeController.dispose();
    _fingerController.dispose();
    _model.dispose();
    super.dispose();
  }

  void _measureWinnerPosition() {
    // The grid body starts after the AppBar. We need to find where
    // the winning card is rendered. Since we know the winner's rating
    // and the grid height, calculate its Y position.
    final bodyBox = context.findRenderObject() as RenderBox?;
    if (bodyBox == null) return;

    final winnerRating = widget.tutorialHintTargetRating ??
        (widget.propositions.isEmpty
            ? 50.0
            : widget.propositions
                .map((p) => p.finalRating ?? 50.0)
                .reduce((a, b) => a > b ? a : b));

    // The grid area is the full body height. Position 100 = top, 0 = bottom.
    // The card center Y = bodyHeight * (1 - rating/100).
    // Card is ~60px tall, so bottom edge is center + 30.
    // Add padding for gap between card and dialog.
    final bodyHeight = bodyBox.size.height;
    // Subtract AppBar height approximation (already in SafeArea)
    final gridHeight = bodyHeight;
    final winnerCenterY = gridHeight * (1.0 - winnerRating / 100.0);
    // Card is ~60px tall → bottom edge at centerY + 30.
    // Winner card (top) also has a label above it, so needs extra clearance.
    const cardHalfHeight = 30.0;
    const gap = 32.0;
    final isTargetedCard = widget.tutorialHintTargetRating != null;
    // Targeted card: position just below card. Winner: extra space for label + crown.
    final hintTop = winnerCenterY + cardHalfHeight + gap + (isTargetedCard ? 0 : 70);

    setState(() => _hintTop = hintTop);
  }

  Widget _buildPropositionsGrid() {
    final l10n = AppLocalizations.of(context);

    if (widget.propositions.isEmpty) {
      return Center(
        child: Text(
          l10n.noPropositionsToDisplay,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return RatingWidget(
      propositions: widget.propositions.map((p) => {
        'id': p.id.toString(),
        'content': p.displayContent,
        'position': p.finalRating ?? 50.0,
      }).toList(),
      onRankingComplete: (_) async {},
      readOnly: true,
      isResuming: true,
    );
  }

  static Offset _fingerStartPos(Offset target, Size screenSize) {
    final center = Offset(screenSize.width / 2, screenSize.height / 2);
    final direction = center - target;
    final distance = direction.distance;
    if (distance < 1) return Offset(target.dx, target.dy + 80);
    return target + direction / distance * 80;
  }

  Widget _buildBackArrowFingerOverlay() {
    final backBox =
        _backButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (backBox == null || !backBox.attached) return const SizedBox.shrink();

    final buttonGlobal = backBox.localToGlobal(
      Offset(backBox.size.width / 2, backBox.size.height / 2),
    );
    final screenSize = MediaQuery.of(context).size;
    final startPos = _fingerStartPos(buttonGlobal, screenSize);
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

  Widget _buildResultsDialog(AppLocalizations l10n) {
    if (!widget.showTutorialHint) return const SizedBox.shrink();

    // Dialog 1: Winner announcement (step 0)
    if (_resultsDialogStep == 0) {
      final desc = widget.tutorialHintDescription ??
          l10n.tutorialResultsWinnerHint;
      return TourTooltipCard(
        title: widget.tutorialHintTitle ?? l10n.tutorialResultsTitle,
        description: desc,
        onNext: _advanceToFingerAnimation,
        onSkip: _advanceToFingerAnimation,
        nextLabel: l10n.homeTourFinish,
        skipLabel: '',
        stepOfLabel: '',
        stepIndex: 0,
        totalSteps: 1,
        autoAdvance: true,
      );
    }

    // Dialog 2: Back arrow hint (step 2, after finger)
    if (_resultsDialogStep == 2) {
      final desc = l10n.tutorialResultsBackHint;
      final theme = Theme.of(context);
      final descWidget = _buildHintDescriptionWidget(desc, theme);
      return TourTooltipCard(
        title: widget.tutorialHintTitle ?? l10n.tutorialResultsTitle,
        description: desc,
        descriptionWidget: descWidget,
        onNext: () => setState(() => _resultsDialogStep = 3),
        onSkip: () => setState(() => _resultsDialogStep = 3),
        nextLabel: l10n.homeTourFinish,
        skipLabel: '',
        stepOfLabel: '',
        stepIndex: 0,
        totalSteps: 1,
        autoAdvance: true,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final scaffold = Scaffold(
        appBar: AppBar(
          leading: widget.showTutorialHint
              ? AnimatedOpacity(
                  opacity: _resultsDialogStep == 0 ? 0.25 : 1.0,
                  duration: const Duration(milliseconds: 250),
                  child: AbsorbPointer(
                    absorbing: _resultsDialogStep < 2,
                    child: IconButton(
                      key: _backButtonKey,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        TutorialTts.stop('results_back_pressed');
                        Navigator.pop(context);
                      },
                    ),
                  ),
                )
              : null,
          title: AnimatedOpacity(
            opacity: widget.showTutorialHint && _resultsDialogStep < 2 ? 0.25 : 1.0,
            duration: const Duration(milliseconds: 250),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.roundResults,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (widget.raterCount != null)
                  Text(
                    'Raters: ${widget.raterCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          actions: [
            if (widget.onExitTutorial != null)
              AnimatedOpacity(
                opacity: _resultsDialogStep < 2 ? 0.25 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: IconButton(
                  icon: const Icon(Icons.exit_to_app),
                  tooltip: l10n.tutorialSkipMenuItem,
                  onPressed: widget.onExitTutorial,
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full-size results grid (blocked during dialogs)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: widget.showTutorialHint && _hintReady && _resultsDialogStep <= 2,
                  child: _buildPropositionsGrid(),
                ),
              ),
              // Floating hint overlay (fades in after page transition)
              if (_hintReady)
                Positioned(
                  left: 40,
                  right: 80,
                  top: _resultsDialogStep == 2 ? 8 : (_hintTop ?? 100),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                    child: _buildResultsDialog(l10n),
                  ),
                ),
                ],
              ),
        ),
    );

    // Show finger animation overlay during step 1
    if (widget.showTutorialHint && _resultsDialogStep == 1 && !_fingerDone) {
      return Stack(
        children: [
          scaffold,
          _buildBackArrowFingerOverlay(),
        ],
      );
    }

    return scaffold;
  }
}
