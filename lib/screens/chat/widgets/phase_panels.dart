import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../../../widgets/countdown_timer.dart';
import '../../../widgets/proposition_content_card.dart';

/// Panel displayed when waiting for more participants to join.
/// The phase starts automatically when enough participants join.
class WaitingStatePanel extends StatelessWidget {
  final int participantCount;
  final int autoStartParticipantCount;

  const WaitingStatePanel({
    super.key,
    required this.participantCount,
    this.autoStartParticipantCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = autoStartParticipantCount - participantCount;
    final waitingCount = remaining > 0 ? remaining : 0;

    return Container(
      key: const Key('waiting-state-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.waiting,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.waitingForMoreParticipants(waitingCount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// Panel displayed when a scheduled chat hasn't started yet.
/// Shows when the chat will start (one-time) or when the next window opens (recurring).
class ScheduledWaitingPanel extends StatelessWidget {
  final bool isHost;
  final DateTime? scheduledStartAt; // For one-time schedules
  final bool isRecurring;
  final DateTime? nextWindowStart; // For recurring schedules
  final List<ScheduleWindow> scheduleWindows; // All configured windows
  final String scheduleTimezone;

  const ScheduledWaitingPanel({
    super.key,
    required this.isHost,
    this.scheduledStartAt,
    this.isRecurring = false,
    this.nextWindowStart,
    this.scheduleWindows = const [],
    required this.scheduleTimezone,
  });

  String _formatTimezoneDisplay(String tz) {
    if (tz == 'UTC') return 'UTC';
    final parts = tz.split('/');
    if (parts.length < 2) return tz;
    return parts.last.replaceAll('_', ' ');
  }

  String _formatDateTime(DateTime dt) {
    // Convert UTC to local time for display
    final local = dt.isUtc ? dt.toLocal() : dt;
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final month = local.month;
    final day = local.day;
    return '$month/$day at $hour:$minute $period';
  }

  String _formatWindow(ScheduleWindow w) {
    String formatTime(String time) {
      final parts = time.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = parts.length > 1 ? parts[1] : '00';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final period = hour >= 12 ? 'PM' : 'AM';
      return '$displayHour:$minute $period';
    }

    String capitalize(String s) => s[0].toUpperCase() + s.substring(1);

    if (w.startDay == w.endDay) {
      return '${capitalize(w.startDay)}: ${formatTime(w.startTime)} - ${formatTime(w.endTime)}';
    }
    return '${capitalize(w.startDay)} ${formatTime(w.startTime)} → ${capitalize(w.endDay)} ${formatTime(w.endTime)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tzDisplay = _formatTimezoneDisplay(scheduleTimezone);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.scheduled,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withAlpha(50),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isRecurring) ...[
                  Text(
                    l10n.chatOutsideSchedule,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (nextWindowStart != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.nextWindowStarts(_formatDateTime(nextWindowStart!)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (scheduleWindows.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.scheduleWindows,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...scheduleWindows.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        _formatWindow(w),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )),
                  ],
                ] else if (scheduledStartAt != null) ...[
                  Text(
                    l10n.scheduledToStart,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(scheduledStartAt!),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.public,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tzDisplay,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.chatWillAutoStart,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Panel for the proposing phase where users submit their ideas.
class ProposingStatePanel extends StatelessWidget {
  final int roundCustomId;
  final int propositionsPerUser;
  final List<Proposition> myPropositions;
  final int allPropositionsCount;
  final TextEditingController propositionController;
  final VoidCallback onSubmit;
  final DateTime? phaseEndsAt;
  final VoidCallback? onPhaseExpired;
  final bool isHost;
  final VoidCallback? onAdvancePhase;
  final VoidCallback? onViewAllPropositions;
  final bool isPaused;
  final bool isSubmitting; // Prevent double-clicks
  // Skip feature
  final VoidCallback? onSkip;
  final bool canSkip;
  final int skipCount;
  final int maxSkips;
  final bool hasSkipped;

  const ProposingStatePanel({
    super.key,
    required this.roundCustomId,
    required this.propositionsPerUser,
    required this.myPropositions,
    this.allPropositionsCount = 0,
    required this.propositionController,
    required this.onSubmit,
    this.phaseEndsAt,
    this.onPhaseExpired,
    this.isHost = false,
    this.onAdvancePhase,
    this.onViewAllPropositions,
    this.isPaused = false,
    this.isSubmitting = false,
    this.onSkip,
    this.canSkip = false,
    this.skipCount = 0,
    this.maxSkips = 0,
    this.hasSkipped = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Don't count carried forward propositions against the submission limit
    // Carried forward propositions show in Previous Winner tab, not here
    final newSubmissions = myPropositions.where((p) => !p.isCarriedForward).length;
    final canSubmitMore = newSubmissions < propositionsPerUser;

    return Container(
      key: const Key('proposing-state-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Submission count (for multi-proposition mode)
          if (propositionsPerUser > 1) ...[
            Row(
              children: [
                const Spacer(),
                Text(
                  l10n.submittedCount(newSubmissions, propositionsPerUser),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Show skip indicator if user has skipped
          if (hasSkipped) ...[
            Container(
              key: const Key('skipped-indicator'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.skip_next,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.skipped,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.waitingForRatingPhase,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (phaseEndsAt != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  CountdownTimer(
                    endsAt: phaseEndsAt!,
                    onExpired: onPhaseExpired,
                    showIcon: false,
                  ),
                  Text(
                    ')',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ]
          // Show input if can submit more (for everyone including host)
          else if (canSubmitMore) ...[
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: propositionController,
              builder: (context, value, child) {
                return TextField(
                  key: const Key('proposition-input'),
                  controller: propositionController,
                  enabled: !isPaused && !hasSkipped,
                  decoration: InputDecoration(
                    hintText: isPaused
                        ? l10n.chatIsPaused
                        : newSubmissions == 0
                            ? l10n.shareYourIdea
                            : l10n.addAnotherIdea,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    suffixIcon: value.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => propositionController.clear(),
                            tooltip: l10n.clear,
                          )
                        : null,
                  ),
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 200,
                );
              },
            ),
            const SizedBox(height: 8),
            // Show submit and skip buttons in a row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    key: const Key('submit-proposition-button'),
                    onPressed: isPaused || isSubmitting ? null : onSubmit,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSubmitting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Text(newSubmissions == 0 ? l10n.submit : l10n.addProposition),
                        if (phaseEndsAt != null && !isSubmitting) ...[
                          const SizedBox(width: 4),
                          const Text('('),
                          CountdownTimer(
                            endsAt: phaseEndsAt!,
                            onExpired: onPhaseExpired,
                            showIcon: false,
                          ),
                          const Text(')'),
                        ],
                      ],
                    ),
                  ),
                ),
                // Show skip button if user can skip and hasn't submitted yet
                if (canSkip && newSubmissions == 0 && maxSkips > 0) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const Key('skip-proposing-button'),
                    onPressed: isPaused || isSubmitting ? null : onSkip,
                    child: Text(l10n.skip),
                  ),
                ],
              ],
            ),
          ] else if (newSubmissions > 0) ...[
            // Regular user after submitting: show their submissions
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: myPropositions.where((p) => !p.isCarriedForward).length,
                itemBuilder: (context, index) {
                  final props = myPropositions.where((p) => !p.isCarriedForward).toList();
                  return _buildPropositionCard(context, props[index], index, isMine: true);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.waitingForRatingPhase,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (phaseEndsAt != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  CountdownTimer(
                    endsAt: phaseEndsAt!,
                    onExpired: onPhaseExpired,
                    showIcon: false,
                  ),
                  Text(
                    ')',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ],

          // Host advance button - hidden for MVP
          // if (isHost && onAdvancePhase != null) ...[
          //   const SizedBox(height: 16),
          //   const Divider(),
          //   const SizedBox(height: 8),
          //   OutlinedButton.icon(
          //     key: const Key('advance-to-rating-button'),
          //     onPressed: onAdvancePhase,
          //     icon: const Icon(Icons.skip_next),
          //     label: Text(l10n.endProposingStartRating),
          //   ),
          // ],
        ],
      ),
    );
  }

  Widget _buildPropositionCard(
    BuildContext context,
    Proposition prop,
    int index, {
    bool isMine = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (propositionsPerUser > 1)
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          Expanded(
            child: PropositionContentCard(
              content: prop.displayContent,
              maxHeight: 100,
            ),
          ),
        ],
      ),
    );
  }

}

/// Panel displayed when waiting for the host to start the rating phase.
/// This appears after proposing ends when rating_start_mode is 'manual'.
class WaitingForRatingPanel extends StatelessWidget {
  final int roundCustomId;
  final bool isHost;
  final int propositionCount;
  final VoidCallback onStartRating;

  const WaitingForRatingPanel({
    super.key,
    required this.roundCustomId,
    required this.isHost,
    required this.propositionCount,
    required this.onStartRating,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      key: const Key('waiting-for-rating-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.hourglass_empty,
                size: 20,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.proposingComplete,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.roundNumber(roundCustomId),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withAlpha(50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.secondary.withAlpha(50),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      propositionCount == 1
                          ? l10n.propositionCollected(propositionCount)
                          : l10n.propositionsCollected(propositionCount),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isHost
                      ? l10n.reviewPropositionsStartRating
                      : l10n.waitingForHostToStartRating,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isHost) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('start-rating-phase-button'),
              onPressed: onStartRating,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.startRatingPhase),
            ),
          ],
        ],
      ),
    );
  }
}

/// Panel for the rating phase.
class RatingStatePanel extends StatelessWidget {
  final int roundCustomId;
  final bool hasRated;
  final bool hasStartedRating;
  final int propositionCount;
  final VoidCallback onStartRating;
  final DateTime? phaseEndsAt;
  final VoidCallback? onPhaseExpired;
  final bool isHost;
  final VoidCallback? onAdvancePhase;
  final bool isPaused;

  const RatingStatePanel({
    super.key,
    required this.roundCustomId,
    required this.hasRated,
    this.hasStartedRating = false,
    required this.propositionCount,
    required this.onStartRating,
    this.phaseEndsAt,
    this.onPhaseExpired,
    this.isHost = false,
    this.onAdvancePhase,
    this.isPaused = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('rating-state-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasRated)
            Container(
              key: const Key('rating-complete-indicator'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.waitingForRatingPhaseEnd,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  if (phaseEndsAt != null) ...[
                    const SizedBox(width: 8),
                    CountdownTimer(
                      endsAt: phaseEndsAt!,
                      onExpired: onPhaseExpired,
                      showIcon: false,
                    ),
                  ],
                ],
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('start-rating-button'),
                onPressed: isPaused ? null : onStartRating,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(hasStartedRating ? l10n.continueRating : l10n.startRating),
                    if (phaseEndsAt != null) ...[
                      const SizedBox(width: 4),
                      const Text('('),
                      CountdownTimer(
                        endsAt: phaseEndsAt!,
                        onExpired: onPhaseExpired,
                        showIcon: false,
                      ),
                      const Text(')'),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // Host advance button - hidden for MVP
          // if (isHost && onAdvancePhase != null) ...[
          //   const SizedBox(height: 16),
          //   const Divider(),
          //   const SizedBox(height: 8),
          //   OutlinedButton.icon(
          //     key: const Key('advance-from-rating-button'),
          //     onPressed: onAdvancePhase,
          //     icon: const Icon(Icons.skip_next),
          //     label: Text(l10n.endRatingStartNextRound),
          //   ),
          // ],
        ],
      ),
    );
  }
}

/// Banner displayed when the chat is paused by the host.
/// This should be shown at the top of the chat screen body.
class HostPausedBanner extends StatelessWidget {
  final bool isHost;
  final VoidCallback? onResume;

  const HostPausedBanner({
    super.key,
    required this.isHost,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      key: const Key('host-paused-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          Icon(
            Icons.pause_circle,
            color: Colors.orange.shade800,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isHost ? l10n.chatPaused : l10n.chatPausedByHostTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isHost
                      ? l10n.timerStoppedTapResume
                      : l10n.hostPausedPleaseWait,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
