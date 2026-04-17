import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../screens/chat/widgets/previous_round_display.dart';

/// A round winner card for cycle history screens.
/// Supports multiple tied winners with chevron navigation.
/// Shrinks to content width (not full-width).
class RoundWinnerItem extends StatefulWidget {
  final List<String> winnerTexts;
  final String label;
  final bool isConvergence;
  final VoidCallback onTap;

  const RoundWinnerItem({
    super.key,
    required this.winnerTexts,
    required this.label,
    this.isConvergence = false,
    required this.onTap,
  });

  @override
  State<RoundWinnerItem> createState() => _RoundWinnerItemState();
}

class _RoundWinnerItemState extends State<RoundWinnerItem> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMultiple = widget.winnerTexts.length > 1;
    final currentText = widget.winnerTexts.isEmpty
        ? '—'
        : widget.winnerTexts[_currentIndex];
    final borderColor = widget.isConvergence
        ? theme.colorScheme.primary
        : AppColors.consensus;

    return GestureDetector(
      onTap: widget.onTap,
      child: UnconstrainedBox(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 64,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Card with optional chevrons
              if (hasMultiple)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        _currentIndex = _currentIndex > 0
                            ? _currentIndex - 1
                            : widget.winnerTexts.length - 1;
                      }),
                      child: Icon(
                        Icons.chevron_left,
                        size: 24,
                        color: borderColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(child: _buildCard(theme, currentText, borderColor)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(() {
                        _currentIndex = _currentIndex < widget.winnerTexts.length - 1
                            ? _currentIndex + 1
                            : 0;
                      }),
                      child: Icon(
                        Icons.chevron_right,
                        size: 24,
                        color: borderColor,
                      ),
                    ),
                  ],
                )
              else
                _buildCard(theme, currentText, borderColor),

              // Page indicators for ties
              if (hasMultiple) ...[
                const SizedBox(height: 6),
                WinnerPageIndicator(
                  count: widget.winnerTexts.length,
                  currentIndex: _currentIndex,
                  onIndexChanged: (i) => setState(() => _currentIndex = i),
                  activeColor: borderColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(ThemeData theme, String text, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: widget.isConvergence ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: borderColor.withValues(alpha: 0.1),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
