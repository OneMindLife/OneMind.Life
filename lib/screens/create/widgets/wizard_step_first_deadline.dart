import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import '../utils/cadence.dart';
import 'form_inputs.dart';
import 'wizard_common.dart';

/// Dedicated wizard step (Always-Active chats only): "When should the first
/// phase end?" — the cadence anchor.
///
/// Shown right AFTER the timing step so the constrained window and suggestion
/// cards always know the chosen duration. Replaces the old "Schedule details"
/// screen for Always Active (which had nothing left to configure once the
/// start-time toggle was removed — an Always-Active chat starts the moment
/// it's created).
///
/// The anchor is EXPLICIT user data: "Full duration" (anchor null) is the
/// default and means plain duration chaining — no hidden grid, no silent
/// overrides. See docs/CADENCE_ANCHOR_SPEC.md.
class WizardStepFirstDeadline extends StatelessWidget {
  final TimerSettings timerSettings;

  /// The chosen end of the first phase. null = "Full duration" (no cadence).
  final DateTime? cadenceAnchorAt;
  final void Function(DateTime?) onCadenceAnchorChanged;

  /// Auto-detected device timezone (IANA), shown in the preview line.
  final String timezoneName;

  /// Adaptive durations mutate phase lengths, which would silently kill a
  /// cadence grid — the controls are unavailable while adaptive is on.
  final bool adaptiveEnabled;

  final VoidCallback onContinue;

  /// Injectable clock for tests. Defaults to [DateTime.now].
  final DateTime Function()? nowProvider;

  const WizardStepFirstDeadline({
    super.key,
    required this.timerSettings,
    required this.cadenceAnchorAt,
    required this.onCadenceAnchorChanged,
    required this.onContinue,
    this.timezoneName = 'UTC',
    this.adaptiveEnabled = false,
    this.nowProvider,
  });

  DateTime get _now => (nowProvider ?? DateTime.now)();

  bool get _controlsAvailable =>
      !adaptiveEnabled &&
      isCadenceCoherent(
        timerSettings.proposingDuration,
        timerSettings.ratingDuration,
      );

  Duration get _phaseDuration =>
      Duration(seconds: timerSettings.proposingDuration);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WizardStepLayout(
      icon: Icons.flag_outlined,
      title: l10n.wizardFirstDeadlineLabel,
      // The chat starts on create; this step only decides when the first
      // phase closes.
      subtitle: l10n.wizardFirstDeadlineStartsNow,
      onContinue: onContinue,
      children: [
        if (_controlsAvailable)
          _CadenceAnchorSection(
            now: _now,
            duration: _phaseDuration,
            anchor: cadenceAnchorAt,
            timezoneName: timezoneName,
            onAnchorChanged: onCadenceAnchorChanged,
          )
        else
          // Incoherent durations (unequal / not dividing 24h) can't carry a
          // daily rhythm. Say so — never gate silently.
          WizardInfoPanel(
            icon: Icons.info_outline,
            child: Text(
              l10n.wizardFirstDeadlineUnavailable,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

/// The cadence anchor controls: one card per option (full duration, the
/// duration's suggested rhythm, a custom time) plus a live preview panel of
/// the resulting daily rhythm.
class _CadenceAnchorSection extends StatelessWidget {
  final DateTime now;
  final Duration duration;
  final DateTime? anchor;
  final String timezoneName;
  final void Function(DateTime?) onAnchorChanged;

  const _CadenceAnchorSection({
    required this.now,
    required this.duration,
    required this.anchor,
    required this.timezoneName,
    required this.onAnchorChanged,
  });

  Future<void> _pickTime(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final window = anchorWindow(now, duration);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(anchor ?? window.earliest),
    );
    if (picked == null || !context.mounted) return;
    final resolved = anchorForPickedTime(picked, now, duration);
    if (resolved == null) {
      // Constrained picker: the picked wall time has no occurrence inside
      // [now + runway, now + duration]. Reject VISIBLY — never adjust the
      // user's stated choice silently.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.wizardCadenceTimeUnavailable(
            TimeOfDay.fromDateTime(window.earliest).format(context),
            TimeOfDay.fromDateTime(window.latest).format(context),
          )),
        ),
      );
      return;
    }
    onAnchorChanged(resolved);
  }

  String _format(BuildContext context, DateTime value) =>
      TimeOfDay.fromDateTime(value).format(context);

  Widget _optionCard(BuildContext context, CadenceChip chip) {
    final l10n = AppLocalizations.of(context);
    switch (chip) {
      case FullDurationChip():
        return WizardSelectCard(
          icon: Icons.hourglass_bottom,
          title: l10n.wizardChipFullDuration,
          description: l10n.wizardCadenceFullDurationDesc(
            formatDurationDescription('custom', duration.inSeconds, l10n),
          ),
          selected: anchor == null,
          onTap: () => onAnchorChanged(null),
        );
      case AmPmRhythmChip(:final value):
        return WizardSelectCard(
          icon: Icons.wb_twilight,
          title: l10n.wizardChipAmPmRhythm,
          description:
              l10n.wizardCadenceFirstDeadlineAt(_format(context, value)),
          selected: anchor == value,
          onTap: () => onAnchorChanged(value),
        );
      case DailyTimeChip():
        // 24h durations: the picker IS the rhythm choice — any anchor means
        // "same time daily".
        final current = anchor;
        return WizardSelectCard(
          icon: Icons.event_repeat,
          title: l10n.wizardChipDailyTime,
          description: current != null
              ? l10n.wizardCadenceFirstDeadlineAt(_format(context, current))
              : l10n.wizardCadencePickExactly,
          selected: current != null,
          unselectedTrailing: Icons.edit_outlined,
          onTap: () => _pickTime(context),
        );
      case OnTheHourChip(:final value):
        return WizardSelectCard(
          icon: Icons.schedule,
          title: l10n.wizardChipOnTheHour,
          description:
              l10n.wizardCadenceFirstDeadlineAt(_format(context, value)),
          selected: anchor == value,
          onTap: () => onAnchorChanged(value),
        );
    }
  }

  /// The custom-time card, shown when the suggested rhythm is a fixed value
  /// (3am/3pm, on the hour) so any other wall time is still reachable.
  Widget _customCard(BuildContext context, DateTime? suggestedValue) {
    final l10n = AppLocalizations.of(context);
    final current = anchor;
    final isCustom = current != null && current != suggestedValue;
    return WizardSelectCard(
      icon: Icons.more_time,
      title: l10n.wizardCadenceCustomTime,
      description: isCustom
          ? l10n.wizardCadenceFirstDeadlineAt(_format(context, current))
          : l10n.wizardCadencePickExactly,
      selected: isCustom,
      unselectedTrailing: Icons.edit_outlined,
      onTap: () => _pickTime(context),
    );
  }

  String _previewText(BuildContext context, DateTime anchor) {
    final l10n = AppLocalizations.of(context);
    final flips = previewFlipTimes(anchor, duration);
    if (flips.length == 1) {
      return l10n.wizardCadencePreviewOne(
        flips.first.format(context),
        timezoneName,
      );
    }
    // The template is "… at {t1} / {t2} …": fold all but the last flip time
    // into t1 so 3+-flip rhythms (6h, 4h, …) render naturally.
    final formatted = flips.map((t) => t.format(context)).toList();
    return l10n.wizardCadencePreviewTwo(
      formatted.sublist(0, formatted.length - 1).join(' / '),
      formatted.last,
      timezoneName,
    );
  }

  String _shorterRel(DateTime anchor) {
    final remaining = anchor.difference(now);
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chips = chipsFor(duration, now);
    final currentAnchor = anchor;
    // The one non-full-duration suggestion (null for 24h, where the daily
    // card opens the picker itself).
    final suggestedValue = chips
        .map((c) => switch (c) {
              AmPmRhythmChip(:final value) => value,
              OnTheHourChip(:final value) => value,
              _ => null,
            })
        .nonNulls
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardSectionLabel(l10n.wizardFirstDeadlineQuestion),
        const SizedBox(height: 12),
        for (final chip in chips) ...[
          _optionCard(context, chip),
          const SizedBox(height: 16),
        ],
        if (suggestedValue != null) ...[
          _customCard(context, suggestedValue),
          const SizedBox(height: 16),
        ],
        if (currentAnchor != null)
          WizardInfoPanel(
            icon: Icons.update,
            highlight: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _previewText(context, currentAnchor),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (currentAnchor.isBefore(now.add(duration))) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.wizardCadenceShorterNotice(
                        _shorterRel(currentAnchor)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
