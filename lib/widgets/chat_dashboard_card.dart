import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/round.dart';
import '../utils/language_utils.dart';
import 'compact_countdown.dart';
import 'participant_badge.dart';
import 'phase_badge.dart';

/// Model-agnostic dashboard card used by both the home screen and discover screen.
///
/// Accepts primitive fields via named parameters so both [ChatDashboardInfo]
/// and [PublicChatSummary] can use it without coupling.
class ChatDashboardCard extends StatelessWidget {
  /// Chat display name.
  final String name;

  /// Initial message / question (shown as subtitle).
  final String initialMessage;

  /// Callback when the card is tapped.
  final VoidCallback onTap;

  /// Number of active participants.
  final int participantCount;

  /// Current round phase (null = idle).
  final RoundPhase? phase;

  /// Whether the chat is paused (schedule or host).
  final bool isPaused;

  /// Time remaining until phase ends (null = no timer).
  final Duration? timeRemaining;

  /// Languages configured for this chat (shown as compact label).
  final List<String> translationLanguages;

  /// Override the phase bar color (e.g. official chats use primary color).
  final Color? phaseBarColorOverride;

  /// Optional trailing widget (e.g. Join button, Joined chip).
  final Widget? trailing;

  /// The user's explicitly chosen viewing language for this chat (null = not set).
  final String? viewingLanguageCode;

  /// Optional semantics label for accessibility.
  final String? semanticLabel;

  const ChatDashboardCard({
    super.key,
    required this.name,
    required this.initialMessage,
    required this.onTap,
    this.participantCount = 0,
    this.phase,
    this.isPaused = false,
    this.timeRemaining,
    this.translationLanguages = const ['en'],
    this.phaseBarColorOverride,
    this.trailing,
    this.viewingLanguageCode,
    this.semanticLabel,
  });

  /// Resolves the vertical phase bar color.
  static Color phaseBarColor(
    BuildContext context, {
    RoundPhase? phase,
    bool isPaused = false,
    Color? override,
  }) {
    if (override != null) return override;
    if (isPaused) return AppColors.waiting;
    switch (phase) {
      case RoundPhase.proposing:
        return AppColors.proposing;
      case RoundPhase.rating:
        return AppColors.rating;
      case RoundPhase.waiting:
        return AppColors.consensus;
      case null:
        return AppColors.waiting;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTimer = timeRemaining != null && phase != null;

    return Semantics(
      button: true,
      label: semanticLabel,
      hint: 'Double tap to open',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Vertical color bar indicating phase
                ExcludeSemantics(
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: phaseBarColor(
                        context,
                        phase: phase,
                        isPaused: isPaused,
                        override: phaseBarColorOverride,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Name + participant badge + optional trailing
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style:
                                    Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ParticipantBadge(count: participantCount),
                            if (trailing != null) ...[
                              const SizedBox(width: 8),
                              trailing!,
                            ],
                          ],
                        ),
                        // Row 2: Initial message (1 line, muted)
                        const SizedBox(height: 4),
                        Text(
                          initialMessage,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Row 3: Phase badge + countdown + spacer + language codes
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            PhaseBadge(
                              phase: phase,
                              isPaused: isPaused,
                            ),
                            if (hasTimer) ...[
                              const SizedBox(width: 8),
                              CompactCountdown(remaining: timeRemaining),
                            ],
                            const Spacer(),
                            _LanguageLabel(
                              languages: translationLanguages,
                              highlightCode: viewingLanguageCode,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the language list with optional highlighting of the selected language.
class _LanguageLabel extends StatelessWidget {
  final List<String> languages;
  final String? highlightCode;

  const _LanguageLabel({required this.languages, this.highlightCode});

  @override
  Widget build(BuildContext context) {
    final defaultStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final highlightStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        );

    final sorted = languages.map((code) => code).toList()..sort();

    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) TextSpan(text: ', ', style: defaultStyle),
            TextSpan(
              text: LanguageUtils.displayName(sorted[i]),
              style: sorted[i] == highlightCode ? highlightStyle : defaultStyle,
            ),
          ],
        ],
      ),
    );
  }
}
