import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../../../widgets/countdown_timer.dart';

/// Panel displayed when waiting for the host to start the phase.
class WaitingStatePanel extends StatelessWidget {
  final bool isHost;
  final int participantCount;
  final VoidCallback onStartPhase;

  const WaitingStatePanel({
    super.key,
    required this.isHost,
    required this.participantCount,
    required this.onStartPhase,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('waiting-state-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isHost ? l10n.startPhase : l10n.waiting,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (isHost) ...[
            Text(
              '$participantCount participants have joined',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('start-phase-button'),
              onPressed: onStartPhase,
              child: Text(l10n.startPhase),
            ),
          ] else
            Text(
              l10n.waitingForHostToStart,
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
                'Scheduled',
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
                    'Chat is outside schedule window',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (nextWindowStart != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Next window starts ${_formatDateTime(nextWindowStart!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (scheduleWindows.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Schedule windows:',
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
                    'Scheduled to start',
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
            'The chat will automatically start at the scheduled time.',
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
  final bool isHost;
  final VoidCallback? onAdvancePhase;
  final VoidCallback? onPhaseExpired;
  final VoidCallback? onViewAllPropositions;
  final bool isPaused;

  const ProposingStatePanel({
    super.key,
    required this.roundCustomId,
    required this.propositionsPerUser,
    required this.myPropositions,
    this.allPropositionsCount = 0,
    required this.propositionController,
    required this.onSubmit,
    this.phaseEndsAt,
    this.isHost = false,
    this.onAdvancePhase,
    this.onPhaseExpired,
    this.onViewAllPropositions,
    this.isPaused = false,
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
          // Header row with round info and timer
          Row(
            children: [
              Text(
                l10n.roundNumber(roundCustomId),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              if (phaseEndsAt != null)
                CountdownTimer(
                  endsAt: phaseEndsAt!,
                  onExpired: onPhaseExpired,
                ),
              const Spacer(),
              if (propositionsPerUser > 1)
                Text(
                  '$newSubmissions/$propositionsPerUser submitted',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              // Host: View All button to open moderation sheet
              if (isHost && allPropositionsCount > 0 && onViewAllPropositions != null) ...[
                const SizedBox(width: 8),
                Badge(
                  label: Text('$allPropositionsCount'),
                  child: IconButton(
                    icon: const Icon(Icons.list_alt),
                    tooltip: l10n.viewAllPropositions,
                    onPressed: onViewAllPropositions,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Show input if can submit more (for everyone including host)
          if (canSubmitMore) ...[
            TextField(
              key: const Key('proposition-input'),
              controller: propositionController,
              enabled: !isPaused,
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
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('submit-proposition-button'),
                onPressed: isPaused ? null : onSubmit,
                child: Text(newSubmissions == 0 ? l10n.submit : l10n.addProposition),
              ),
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
            Text(
              l10n.waitingForRatingPhase,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],

          // Host advance button
          if (isHost && onAdvancePhase != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('advance-to-rating-button'),
              onPressed: onAdvancePhase,
              icon: const Icon(Icons.skip_next),
              label: Text(l10n.endProposingStartRating),
            ),
          ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
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
          Expanded(child: Text(prop.displayContent)),
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
                      '$propositionCount proposition${propositionCount == 1 ? '' : 's'} collected',
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
          // Header row with title and timer
          Row(
            children: [
              Text(
                hasRated ? l10n.ratingComplete : l10n.ratePropositions,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              if (phaseEndsAt != null)
                CountdownTimer(
                  endsAt: phaseEndsAt!,
                  onExpired: onPhaseExpired,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.roundNumber(roundCustomId),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
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
                  Text(
                    l10n.waitingForRatingPhaseEnd,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            )
          else ...[
            Text(
              isPaused
                  ? l10n.chatIsPaused
                  : l10n.rateAllPropositions(propositionCount),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('start-rating-button'),
                onPressed: isPaused ? null : onStartRating,
                child: Text(hasStartedRating ? l10n.continueRating : l10n.startRating),
              ),
            ),
          ],

          // Host advance button
          if (isHost && onAdvancePhase != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('advance-from-rating-button'),
              onPressed: onAdvancePhase,
              icon: const Icon(Icons.skip_next),
              label: Text(l10n.endRatingStartNextRound),
            ),
          ],
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
