import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;
import 'rating/rating_widget.dart';

/// Animated finger that holds down/up/down arrows on real positioning controls.
/// Releases each hold when the active proposition reaches the target position.
/// Uses [activePositionNotifier] from the RatingWidget to react dynamically.
class PositioningControlsDemo extends StatefulWidget {
  final GlobalKey movementControlsKey;
  final ValueNotifier<Map<String, double>> positionsNotifier;
  final RatingDemoController? demoController;
  final VoidCallback? onComplete;
  final bool active;

  const PositioningControlsDemo({
    super.key,
    required this.movementControlsKey,
    required this.positionsNotifier,
    this.demoController,
    this.onComplete,
    this.active = false,
  });

  @override
  State<PositioningControlsDemo> createState() =>
      _PositioningControlsDemoState();
}

enum _HoldPhase { idle, fadeIn, glideToUp, holdUp, glideToDown, holdDown, glideToUp2, holdUp2, fadeOut, done }

class _PositioningControlsDemoState extends State<PositioningControlsDemo>
    with SingleTickerProviderStateMixin {
  Offset? _upLocal;
  Offset? _downLocal;
  Offset? _centerPos;
  int _pollCount = 0;
  bool _sequenceStarted = false;


  _HoldPhase _phase = _HoldPhase.idle;
  double _fingerOpacity = 0.0;
  Offset? _fingerPos;
  bool _isHolding = false;

  // Animation for glides and fades
  late final AnimationController _glideController;

  @override
  void initState() {
    super.initState();
    _glideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.active) _pollForPositions();
    widget.positionsNotifier.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(PositioningControlsDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _phase = _HoldPhase.idle;
      _pollForPositions();
    }
  }

  @override
  void dispose() {
    widget.positionsNotifier.removeListener(_onPositionChanged);
    _glideController.dispose();
    super.dispose();
  }

  void _pollForPositions() {
    if (_sequenceStarted) return;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || _sequenceStarted) return;
      _measure();
      _pollCount++;
      if (_downLocal != null && _downLocal!.dx > 100) {
        _sequenceStarted = true;
        _startSequence();
      } else if (_pollCount < 10) {
        _pollForPositions();
      }
    });
  }

  void _measure() {
    final controlsBox = widget.movementControlsKey.currentContext
        ?.findRenderObject() as RenderBox?;
    if (controlsBox == null) return;

    final controlsGlobal = controlsBox.localToGlobal(Offset.zero);
    final controlsSize = controlsBox.size;

    final cx = controlsGlobal.dx + controlsSize.width / 2;
    final upCy = controlsGlobal.dy + 4 + 20;
    final downCy = controlsGlobal.dy + 4 + 40 + 20 + 40 + 20 + 20;

    if (!mounted) return;
    setState(() {
      _upLocal = Offset(cx, upCy);
      _downLocal = Offset(cx, downCy);
    });
  }

  void _startSequence() {
    // Start: fade in at center, then glide to up
    _advanceTo(_HoldPhase.fadeIn);
  }

  void _advanceTo(_HoldPhase next) {
    if (!mounted) return;
    setState(() => _phase = next);

    switch (next) {
      case _HoldPhase.fadeIn:
        _fingerPos = _centerPos;
        _fingerOpacity = 0.0;
        _isHolding = false;
        _animateFade(0.0, 1.0, const Duration(milliseconds: 500), () {
          _advanceTo(_HoldPhase.glideToUp);
        });

      case _HoldPhase.glideToUp:
        _animateGlide(_centerPos!, _upLocal!, const Duration(milliseconds: 700), () {
          _advanceTo(_HoldPhase.holdUp);
        });

      case _HoldPhase.holdUp:
        setState(() => _isHolding = true);
        _fingerPos = _upLocal;
        widget.demoController?.startMove?.call(1); // up
        // Release when position reaches target

      case _HoldPhase.glideToDown:
        setState(() => _isHolding = false);
        _animateGlide(_upLocal!, _downLocal!, const Duration(milliseconds: 700), () {
          _advanceTo(_HoldPhase.holdDown);
        });

      case _HoldPhase.holdDown:
        setState(() => _isHolding = true);
        _fingerPos = _downLocal;
        widget.demoController?.startMove?.call(-1); // down
        // Release when position reaches target

      case _HoldPhase.glideToUp2:
        setState(() => _isHolding = false);
        _animateGlide(_downLocal!, _upLocal!, const Duration(milliseconds: 700), () {
          _advanceTo(_HoldPhase.holdUp2);
        });

      case _HoldPhase.holdUp2:
        setState(() => _isHolding = true);
        _fingerPos = _upLocal;
        widget.demoController?.startMove?.call(1); // up
        // Release when position reaches target

      case _HoldPhase.fadeOut:
        setState(() => _isHolding = false);
        _animateFade(1.0, 0.0, const Duration(milliseconds: 500), () {
          _advanceTo(_HoldPhase.done);
        });

      case _HoldPhase.done:
        widget.onComplete?.call();

      case _HoldPhase.idle:
        break;
    }
  }

  // Track initial positions to know which propositions to watch
  Map<String, double>? _initialPositions;

  void _onPositionChanged() {
    final positions = widget.positionsNotifier.value;
    if (positions.isEmpty) return;

    // Capture initial positions on first update
    _initialPositions ??= Map.from(positions);

    switch (_phase) {
      case _HoldPhase.holdUp:
        // Holding up arrow. Wait until the proposition that was near 100
        // has been pushed down to ~50.
        final topProp = _initialPositions!.entries
            .reduce((a, b) => a.value > b.value ? a : b);
        final currentPos = positions[topProp.key];
        if (currentPos != null && currentPos <= 55) {
          widget.demoController?.stopMove?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _advanceTo(_HoldPhase.glideToDown);
          });
        }
      case _HoldPhase.holdDown:
        // Holding down arrow. Wait until the proposition that was near 0
        // has been pushed up to ~50.
        final bottomProp = _initialPositions!.entries
            .reduce((a, b) => a.value < b.value ? a : b);
        final currentPos = positions[bottomProp.key];
        if (currentPos != null && currentPos >= 45) {
          widget.demoController?.stopMove?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _advanceTo(_HoldPhase.glideToUp2);
          });
        }
      case _HoldPhase.holdUp2:
        // Holding up again. Wait until active reaches ~50.
        final active = positions.entries.reduce((a, b) {
          final aDiff = (a.value - (_initialPositions![a.key] ?? a.value)).abs();
          final bDiff = (b.value - (_initialPositions![b.key] ?? b.value)).abs();
          return aDiff > bDiff ? a : b;
        });
        if (active.value >= 45 && active.value <= 55) {
          widget.demoController?.stopMove?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted) _advanceTo(_HoldPhase.fadeOut);
            });
          });
        }
      default:
        break;
    }
  }

  VoidCallback? _activeListener;

  void _clearListener() {
    if (_activeListener != null) {
      _glideController.removeListener(_activeListener!);
      _activeListener = null;
    }
  }

  void _animateFade(double from, double to, Duration duration, VoidCallback onDone) {
    _clearListener();
    _glideController.duration = duration;
    _glideController.reset();
    _activeListener = () {
      if (mounted) {
        setState(() {
          _fingerOpacity = from + (to - from) * _glideController.value;
        });
      }
    };
    _glideController.addListener(_activeListener!);
    _glideController.forward().then((_) {
      _clearListener();
      if (mounted) onDone();
    });
  }

  void _animateGlide(Offset from, Offset to, Duration duration, VoidCallback onDone) {
    _clearListener();
    _glideController.duration = duration;
    _glideController.reset();
    _activeListener = () {
      if (!mounted) return;
      final t = Curves.easeInOut.transform(_glideController.value);
      setState(() {
        _fingerPos = Offset.lerp(from, to, t);
      });
    };
    _glideController.addListener(_activeListener!);
    _glideController.forward().then((_) {
      _clearListener();
      if (mounted) onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _phase == _HoldPhase.idle || _phase == _HoldPhase.done) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }

    // Calculate center position on first build
    if (_centerPos == null && _downLocal != null) {
      final stackBox = context.findAncestorRenderObjectOfType<RenderStack>();
      final stackGlobal = stackBox?.localToGlobal(Offset.zero) ?? Offset.zero;
      final screenSize = MediaQuery.of(context).size;
      // Convert button positions to stack-relative
      _upLocal = _upLocal! - stackGlobal;
      _downLocal = _downLocal! - stackGlobal;
      // Start 80px from up button toward screen center
      final center = Offset(screenSize.width / 2, screenSize.height / 2) - stackGlobal;
      final dir = center - _upLocal!;
      final dist = dir.distance;
      _centerPos = dist < 1 ? Offset(_upLocal!.dx, _upLocal!.dy + 80) : _upLocal! + dir / dist * 80;

    }

    final pos = _fingerPos ?? _centerPos ?? Offset.zero;
    final scale = _isHolding ? 0.78 : 1.0;

    return Positioned(
      left: pos.dx - 14,
      top: pos.dy - 14,
      child: IgnorePointer(
        child: Opacity(
          opacity: _fingerOpacity.clamp(0.0, 1.0),
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
  }
}
