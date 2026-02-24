import 'dart:async';
import 'package:flutter/material.dart';

/// A countdown timer widget that displays time remaining until a deadline.
class CountdownTimer extends StatefulWidget {
  final DateTime endsAt;
  final VoidCallback? onExpired;
  final TextStyle? style;
  final bool showIcon;

  const CountdownTimer({
    super.key,
    required this.endsAt,
    this.onExpired,
    this.style,
    this.showIcon = true,
  });

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  @override
  void didUpdateWidget(CountdownTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      _updateRemaining();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final remaining = widget.endsAt.difference(now);

    // Only fire onExpired when transitioning from positive to negative
    // Use > 0 (not >= 0) to prevent firing when already expired (_remaining == 0)
    if (remaining.isNegative && _remaining.inSeconds > 0) {
      widget.onExpired?.call();
    }

    if (mounted) {
      setState(() {
        _remaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      final seconds = duration.inSeconds.remainder(60);
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    } else if (duration.inMinutes > 0) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds.remainder(60);
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _remaining == Duration.zero;

    // If a custom style is provided, use it. Otherwise inherit from the
    // enclosing DefaultTextStyle so the timer matches its parent (e.g.
    // white text inside a FilledButton).
    final textStyle = widget.style ?? DefaultTextStyle.of(context).style;

    if (isExpired) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showIcon)
            Icon(
              Icons.timer_off,
              size: 16,
              color: textStyle.color,
            ),
          if (widget.showIcon) const SizedBox(width: 4),
          Text('Time expired', style: textStyle),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showIcon)
          Icon(
            Icons.timer,
            size: 16,
            color: textStyle.color,
          ),
        if (widget.showIcon) const SizedBox(width: 4),
        Text(
          _formatDuration(_remaining),
          style: textStyle.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
