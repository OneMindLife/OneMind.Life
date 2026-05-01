import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../screens/home_tour/widgets/spotlight_overlay.dart';
import 'positioning_controls_demo.dart';
import 'rating/rating_model.dart';
import 'rating/rating_widget.dart';
import 'rating_controls_demo.dart';

/// Self-contained help modal that demonstrates the rating controls.
///
/// Shows a real `RatingWidget` populated with fake propositions so the
/// demonstrated buttons line up with what the user will use, then plays
/// the matching finger animation and a tooltip dialog. Closing the dialog
/// (or tapping back) returns to the caller.
class RatingHelpModal extends StatefulWidget {
  final RatingPhase phase;

  const RatingHelpModal({super.key, required this.phase});

  static Future<void> show(BuildContext context, RatingPhase phase) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RatingHelpModal(phase: phase),
      ),
    );
  }

  @override
  State<RatingHelpModal> createState() => _RatingHelpModalState();
}

class _RatingHelpModalState extends State<RatingHelpModal> {
  final GlobalKey<RatingWidgetState> _ratingKey = GlobalKey();
  final GlobalKey _swapButtonKey = GlobalKey();
  final GlobalKey _checkButtonKey = GlobalKey();
  final GlobalKey _movementControlsKey = GlobalKey();
  final ValueNotifier<Map<String, double>> _positionsNotifier =
      ValueNotifier({});
  final RatingDemoController _demoController = RatingDemoController();

  bool _demoComplete = false;
  bool _showDialog = false;

  // Mock pool used in positioning phase. The first three are pre-placed,
  // the fourth is fed in via lazy loading once the widget asks for more.
  // Generic placeholder content keeps the focus on the controls, not on
  // the wording of the example ideas.
  static const List<Map<String, dynamic>> _binaryProps = [
    {'id': 'help-1', 'content': 'Idea 1'},
    {'id': 'help-2', 'content': 'Idea 2'},
  ];

  static const List<Map<String, dynamic>> _positioningPlaced = [
    {'id': 'help-1', 'content': 'Idea 1', 'position': 100.0},
    {'id': 'help-2', 'content': 'Idea 2', 'position': 0.0},
  ];

  static const Map<String, dynamic> _positioningNext = {
    'id': 'help-3',
    'content': 'Idea 3',
  };

  bool _nextFed = false;

  @override
  void initState() {
    super.initState();
    if (widget.phase == RatingPhase.positioning) {
      // Lazy-load the third prop after the widget has initialized in
      // positioning phase so it becomes the active card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _nextFed) return;
        _nextFed = true;
        _ratingKey.currentState?.addProposition(_positioningNext);
      });
    }
  }

  @override
  void dispose() {
    _positionsNotifier.dispose();
    super.dispose();
  }

  void _onDemoComplete() {
    if (_demoComplete || !mounted) return;
    setState(() {
      _demoComplete = true;
      _showDialog = true;
    });
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isBinary = widget.phase == RatingPhase.binary;

    final hintTitle = isBinary
        ? l10n.tutorialHintCompare
        : l10n.tutorialHintPosition;
    final hintDescription = isBinary
        ? l10n.tutorialRatingBinaryHint
        : l10n.tutorialRatingPositioningHint;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.howItWorks),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Block all interaction with the demo widget — this is a passive
            // walkthrough.
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: RatingWidget(
                  key: _ratingKey,
                  propositions: isBinary
                      ? _binaryProps
                      : _positioningPlaced,
                  onRankingComplete: (_) {},
                  lazyLoadingMode: !isBinary,
                  isResuming: !isBinary,
                  swapButtonKey: _swapButtonKey,
                  checkButtonKey: _checkButtonKey,
                  movementControlsKey: _movementControlsKey,
                  positionsNotifier: _positionsNotifier,
                  demoController: _demoController,
                ),
              ),
            ),

            // Animated finger overlay matching the active phase.
            // onSwap must dereference _demoController.swap at click time
            // (closure), not capture the current value at build time —
            // the RatingWidget assigns the callback in its initState, so
            // build-time capture would resolve to null.
            if (isBinary)
              RatingControlsDemo(
                swapButtonKey: _swapButtonKey,
                checkButtonKey: _checkButtonKey,
                onSwap: () => _demoController.swap?.call(),
                active: !_demoComplete,
                onComplete: _onDemoComplete,
              )
            else
              PositioningControlsDemo(
                movementControlsKey: _movementControlsKey,
                positionsNotifier: _positionsNotifier,
                demoController: _demoController,
                active: !_demoComplete,
                onComplete: _onDemoComplete,
              ),

            // Dialog overlay (fades in once the finger animation finishes).
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showDialog,
                child: AnimatedOpacity(
                  opacity: _showDialog ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: TourTooltipCard(
                        title: hintTitle,
                        description: hintDescription,
                        descriptionWidget: Text.rich(
                          _buildInlineHintSpans(
                            hintDescription,
                            theme,
                            theme.textTheme.bodyMedium,
                          ),
                        ),
                        onNext: _close,
                        onSkip: _close,
                        stepIndex: 0,
                        totalSteps: 1,
                        nextLabel: l10n.gotIt,
                        skipLabel: l10n.gotIt,
                        stepOfLabel: '',
                        autoAdvance: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Inline-icon helpers (mirrors the tutorial's marker rendering) ---

  InlineSpan _buildInlineHintSpans(
      String text, ThemeData theme, TextStyle? textStyle) {
    final markerPattern = RegExp(r'\[(swap|check|up|down|undo|zoomin|zoomout)\]');
    final children = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in markerPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        children.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      children.add(_inlineIcon(match.group(1)!, theme));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastEnd)));
    }
    return TextSpan(style: textStyle, children: children);
  }

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
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}
