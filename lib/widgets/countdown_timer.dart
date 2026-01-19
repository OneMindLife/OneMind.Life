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
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (duration.inMinutes > 0) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds.remainder(60);
      return '${minutes}m ${seconds}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _remaining == Duration.zero;
    final isUrgent = _remaining.inMinutes < 1 && !isExpired;

    final textStyle = widget.style ??
        Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isUrgent
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isUrgent ? FontWeight.bold : FontWeight.normal,
            );

    if (isExpired) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showIcon)
            Icon(
              Icons.timer_off,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            color: isUrgent
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        if (widget.showIcon) const SizedBox(width: 4),
        Text(_formatDuration(_remaining), style: textStyle),
      ],
    );
  }
}
