import 'package:flutter/material.dart';

/// Compact countdown text like "3m 42s", updated by parent's periodic rebuild.
class CompactCountdown extends StatelessWidget {
  final Duration? remaining;

  const CompactCountdown({super.key, required this.remaining});

  @override
  Widget build(BuildContext context) {
    if (remaining == null) return const SizedBox.shrink();

    final total = remaining!.inSeconds;
    if (total <= 0) {
      return Text(
        'Ending...',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
      );
    }

    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    // Use zero-padded numbers so width stays constant as digits change
    String text;
    if (hours > 0) {
      text = '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    } else if (minutes > 0) {
      text = '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    } else {
      text = '${seconds}s';
    }

    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: total < 60
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}
