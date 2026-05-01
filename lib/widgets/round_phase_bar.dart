import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import 'countdown_timer.dart';

/// A status bar showing the current round number, phase (Proposing / Rating),
/// and countdown timer. Each section can have its own opacity for progressive
/// reveal during the tutorial chat tour.
class RoundPhaseBar extends StatelessWidget {
  final int roundNumber;
  final bool isProposing;
  final DateTime? phaseEndsAt;
  final VoidCallback? onPhaseExpired;

  /// Participation percentage (0-100). Shows progress bar between phase chips and timer.
  final int? participationPercent;

  /// Whether to animate the progress bar from 0 to the target value.
  final bool animateProgress;

  /// Whether to show the inactive phase chip. Defaults to true.
  final bool showInactivePhase;

  /// Whether to highlight both phase chips as active. Defaults to false.
  final bool highlightAllPhases;

  /// Opacity for each section (1.0 = visible, 0.0 = hidden, 0.25 = dimmed).
  /// Defaults to 1.0 (fully visible).
  final double roundOpacity;
  final double phasesOpacity;
  /// Separate opacity for progress bar. Defaults to phasesOpacity.
  final double? progressOpacity;
  final double timerOpacity;
  /// When true, the countdown timer shows but doesn't tick down.
  final bool frozenTimer;
  /// Exact duration to display when timer is frozen (e.g. 5 minutes).
  final Duration? frozenTimerDuration;

  /// When true, progress bar and timer always occupy space (invisible if null/hidden).
  /// Prevents layout shifts during progressive reveal in tutorials.
  final bool reserveSpace;

  /// phaseEndsAt used for layout reservation when reserveSpace is true.
  final DateTime? reservePhaseEndsAt;

  /// When true, the timer slot is replaced with a "Paused" indicator
  /// (pause icon + label) instead of a countdown. Use when the chat is
  /// host_paused and phaseEndsAt has been cleared.
  final bool isPaused;

  /// When false, the bottom divider is omitted. Useful when the bar sits
  /// flush against the bottom edge of the screen and a trailing rule
  /// would just float above empty space.
  final bool showBottomDivider;

  /// When false, the top divider is omitted. Useful when the bar sits
  /// directly under an AppBar so a leading rule would just stack against
  /// the AppBar's bottom edge.
  final bool showTopDivider;

  const RoundPhaseBar({
    super.key,
    required this.roundNumber,
    this.isProposing = true,
    this.phaseEndsAt,
    this.onPhaseExpired,
    this.participationPercent,
    this.animateProgress = false,
    this.showInactivePhase = false,
    this.highlightAllPhases = false,
    this.roundOpacity = 1.0,
    this.phasesOpacity = 1.0,
    this.progressOpacity,
    this.timerOpacity = 1.0,
    this.frozenTimer = false,
    this.frozenTimerDuration,
    this.reserveSpace = false,
    this.reservePhaseEndsAt,
    this.isPaused = false,
    this.showBottomDivider = true,
    this.showTopDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final barVisible = roundOpacity > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (barVisible && showTopDivider)
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Round number
              AnimatedOpacity(
                opacity: roundOpacity,
                duration: const Duration(milliseconds: 250),
                child: Text(
                  l10n.roundNumber(roundNumber),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              // Divider between round and phases
              AnimatedOpacity(
                opacity: phasesOpacity,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              // Phase chips
              AnimatedOpacity(
                opacity: phasesOpacity,
                duration: const Duration(milliseconds: 250),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showInactivePhase || isProposing)
                      _PhaseChip(
                        label: l10n.proposing,
                        isActive: highlightAllPhases || isProposing,
                        color: AppColors.proposing,
                        theme: theme,
                      ),
                    if (showInactivePhase || reserveSpace)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.hardEdge,
                        child: showInactivePhase
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 6),
                                  _PhaseChip(
                                    label: l10n.rating,
                                    isActive: highlightAllPhases || !isProposing,
                                    color: AppColors.rating,
                                    theme: theme,
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    if (!showInactivePhase && !reserveSpace && !isProposing)
                      _PhaseChip(
                        label: l10n.rating,
                        isActive: true,
                        color: AppColors.rating,
                        theme: theme,
                      ),
                  ],
                ),
              ),
              // Participation progress bar
              if (participationPercent != null || reserveSpace)
                AnimatedOpacity(
                  opacity: participationPercent != null
                      ? (progressOpacity ?? phasesOpacity) : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 1,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: theme.colorScheme.outlineVariant,
                      ),
                      if (animateProgress && participationPercent != null)
                        Builder(builder: (_) {
                          return TweenAnimationBuilder<int>(
                          key: ValueKey('progress_${participationPercent}_$isProposing'),
                          tween: IntTween(begin: 0, end: participationPercent!.clamp(0, 100)),
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeOut,
                          builder: (context, value, _) => _ParticipationBar(
                            percent: value,
                            color: isProposing ? AppColors.proposing : AppColors.rating,
                            theme: theme,
                          ),
                        );
                        })
                      else
                        _ParticipationBar(
                          percent: (participationPercent ?? 0).clamp(0, 100),
                          color: isProposing ? AppColors.proposing : AppColors.rating,
                          theme: theme,
                        ),
                    ],
                  ),
                ),
              // Timer (or "Paused" indicator if isPaused)
              if (isPaused)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Icon(
                      Icons.pause_circle_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.chatPaused,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              else if (phaseEndsAt != null || reserveSpace)
                AnimatedOpacity(
                  opacity: phaseEndsAt != null ? timerOpacity : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 1,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: theme.colorScheme.outlineVariant,
                      ),
                      CountdownTimer(
                        endsAt: phaseEndsAt ?? reservePhaseEndsAt ?? DateTime.now().add(const Duration(minutes: 5)),
                        onExpired: onPhaseExpired,
                        frozen: frozenTimer || phaseEndsAt == null,
                        frozenDuration: frozenTimerDuration,
                        showIcon: false,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isProposing
                              ? AppColors.proposing
                              : AppColors.rating,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ),
        if (barVisible && showBottomDivider)
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
      ],
    );
  }
}

class _PhaseChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;
  final ThemeData theme;

  const _PhaseChip({
    required this.label,
    required this.isActive,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.7) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? color.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: isActive
              ? Colors.white
              : theme.colorScheme.outline.withValues(alpha: 0.5),
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// Compact progress bar with percentage text inside.
class _ParticipationBar extends StatelessWidget {
  final int percent;
  final Color color;
  final ThemeData theme;

  const _ParticipationBar({
    required this.percent,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = percent / 100.0;
    final label = '$percent%';

    return Container(
      width: 56,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Filled portion
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          // Percentage text centered
          Center(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: percent >= 50
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
