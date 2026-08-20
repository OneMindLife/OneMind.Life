import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';

/// Host-only footer control for a real quick-create chat in matches rating.
///
/// These chats have NO timer (see seed_no_timer) and don't silently auto-seal
/// (a real chat's participants join over time, so "everyone's done" briefly goes
/// true early and would seal under late joiners). So the HOST decides when voting
/// ends. This bar is always available during rating; when everyone present has
/// voted it promotes itself to an "Everyone's voted" prompt so the host gets the
/// 100% signal but still confirms the end (only they know if stragglers are coming).
///
/// Tapping triggers a terminal confirmation, then [onEndVoting]; the parent calls
/// host_end_voting (tally votes as they stand → lock in the winner → chat ends).
class HostEndVotingBar extends StatelessWidget {
  const HostEndVotingBar({
    super.key,
    required this.done,
    required this.eligible,
    required this.isEnding,
    required this.onEndVoting,
  });

  /// Distinct raters who have finished voting (matches "done").
  final int done;

  /// Distinct raters eligible to vote (matches "eligible").
  final int eligible;

  /// True while host_end_voting is in flight (button shows a spinner).
  final bool isEnding;

  /// Invoked after the host confirms the terminal dialog.
  final VoidCallback onEndVoting;

  bool get _everyoneVoted => eligible > 0 && done >= eligible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Status line above the button. At 100% it celebrates + nudges; otherwise it
    // shows live progress so the host knows how close the group is.
    final Widget status = _everyoneVoted
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 18, color: AppColors.consensus),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  eligible == 1
                      ? "You've voted — ready when you are."
                      : 'Everyone\'s voted ($done of $eligible).',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          )
        : Text(
            eligible <= 1
                ? 'End voting whenever you\'re ready.'
                : 'End voting whenever your group\'s done — $done of $eligible voted so far.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          );

    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              status,
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('end-voting-button'),
                  // At 100% use the primary accent; before that a calmer tone so
                  // it doesn't scream "press me" while votes are still coming in.
                  style: _everyoneVoted
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: cs.secondaryContainer,
                          foregroundColor: cs.onSecondaryContainer,
                        ),
                  onPressed: isEnding ? null : onEndVoting,
                  icon: isEnding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.how_to_reg),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(_everyoneVoted
                        ? 'Show results'
                        : 'End voting & show results'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
