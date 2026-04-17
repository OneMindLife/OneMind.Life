import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Animated finger overlay that taps the real swap and check buttons.
/// Swap button is tapped twice (real taps via hit testing).
/// Check button gets one fake tap (visual only).
class RatingControlsDemo extends StatefulWidget {
  final GlobalKey swapButtonKey;
  final GlobalKey checkButtonKey;
  final VoidCallback? onComplete;
  final bool active;
  final VoidCallback? onSwap;

  const RatingControlsDemo({
    super.key,
    required this.swapButtonKey,
    required this.checkButtonKey,
    this.onComplete,
    this.active = false,
    this.onSwap,
  });

  @override
  State<RatingControlsDemo> createState() => _RatingControlsDemoState();
}

class _RatingControlsDemoState extends State<RatingControlsDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset? _swapLocal;
  Offset? _checkLocal;
  bool _tapped1 = false;
  bool _tapped2 = false;
  bool _completeCalled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );
    _controller.addListener(_handleTaps);
    if (widget.active) _pollForPositions();
  }

  @override
  void didUpdateWidget(RatingControlsDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _pollForPositions();
    }
  }

  int _pollCount = 0;

  void _pollForPositions() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _measure();
      _pollCount++;
      if (_swapLocal != null && _swapLocal!.dx > 100) {
        // Valid position found (not stuck at left edge)
        _controller.forward();
      } else if (_pollCount < 10) {
        _pollForPositions();
      }
    });
  }

  void _measure() {
    // swapButtonKey is on the controls Container (parent of both buttons)
    final controlsBox =
        widget.swapButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final checkBox =
        widget.checkButtonKey.currentContext?.findRenderObject() as RenderBox?;

    if (controlsBox == null) return;

    // Controls container global position
    final controlsGlobal = controlsBox.localToGlobal(Offset.zero);
    final controlsSize = controlsBox.size;

    // Binary controls layout: Container(padding:4) > SizedBox(w:40) > Column > [swap, SizedBox(h:20), check]
    // Each button is 40x40 inside AspectRatio(1:1) within the 40px wide SizedBox
    // Swap button center: controlsGlobal + (containerWidth/2, padding + 20)
    // Check button center: controlsGlobal + (containerWidth/2, padding + 40 + 20 + 20)
    final cx = controlsGlobal.dx + controlsSize.width / 2;
    final swapCy = controlsGlobal.dy + 4 + 20; // 4px padding + half of 40px button
    final checkCy = controlsGlobal.dy + 4 + 40 + 20 + 20; // padding + swap(40) + gap(20) + half check(20)

    final swapGlobal = Offset(cx, swapCy);
    final checkGlobal = Offset(cx, checkCy);

    if (!mounted) return;

    setState(() {
      _swapLocal = swapGlobal;
      _checkLocal = checkGlobal;
    });
  }

  void _handleTaps() {
    final t = _controller.value;

    // Real swap at peak of press animation
    if (t >= 0.32 && !_tapped1) {
      _tapped1 = true;
      widget.onSwap?.call();
    }
    if (t >= 0.57 && !_tapped2) {
      _tapped2 = true;
      widget.onSwap?.call();
    }
    // Trigger onComplete when fade-out starts (dialog appears alongside)
    if (t >= 0.78 && !_completeCalled) {
      _completeCalled = true;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTaps);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _swapLocal == null || _checkLocal == null) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }

    // We need to convert global positions to positions relative to
    // the Stack we're inside. Find the Stack's global offset.
    final stackBox = context.findAncestorRenderObjectOfType<RenderStack>();
    final stackGlobal = stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final swapRel = _swapLocal! - stackGlobal;
    final checkRel = _checkLocal! - stackGlobal;

    // Start 80px from swap button toward screen center
    final screenSize = MediaQuery.of(context).size;
    final swapGlobal = stackGlobal + swapRel;
    final swapDir = Offset(screenSize.width / 2, screenSize.height / 2) - swapGlobal;
    final swapDist = swapDir.distance;
    final nearSwap = swapDist < 1 ? Offset(swapRel.dx, swapRel.dy + 80) : swapRel + swapDir / swapDist * 80;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // Timeline:
        // 0.00-0.10: fade in at center
        // 0.10-0.25: glide from center to swap
        // 0.25-0.40: tap swap #1
        // 0.40-0.50: release, pause
        // 0.50-0.65: tap swap #2
        // 0.65-0.80: pause
        // 0.80-1.00: fade out

        Offset fingerPos;
        bool isPressed;
        double opacity;

        if (t < 0.10) {
          // Fade in at center
          fingerPos = nearSwap;
          isPressed = false;
          opacity = t / 0.10;
        } else if (t < 0.25) {
          // Glide to swap
          final moveT = Curves.easeInOut.transform((t - 0.10) / 0.15);
          fingerPos = Offset.lerp(nearSwap, swapRel, moveT)!;
          isPressed = false;
          opacity = 1.0;
        } else if (t < 0.40) {
          // Tap swap #1
          fingerPos = swapRel;
          isPressed = t >= 0.28 && t <= 0.37;
          opacity = 1.0;
        } else if (t < 0.50) {
          // Release, pause
          fingerPos = swapRel;
          isPressed = false;
          opacity = 1.0;
        } else if (t < 0.60) {
          // Tap swap #2
          fingerPos = swapRel;
          isPressed = t >= 0.53 && t <= 0.58;
          opacity = 1.0;
        } else if (t < 0.78) {
          // Pause — let propositions settle after swap animation (400ms)
          fingerPos = swapRel;
          isPressed = false;
          opacity = 1.0;
        } else {
          // Fade out
          fingerPos = swapRel;
          isPressed = false;
          opacity = 1.0 - ((t - 0.78) / 0.12).clamp(0.0, 1.0);
        }

        final scale = isPressed ? 0.78 : 1.0;

        return Positioned(
          left: fingerPos.dx - 14,
          top: fingerPos.dy - 14,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Icon(
                  Icons.touch_app,
                  size: 28,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
