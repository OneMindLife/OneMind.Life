import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';
import 'setting_input_card.dart';

/// Auto-advance section for early phase advancement.
/// Simplified: just count-based thresholds, no confusing percentage.
class AutoAdvanceSection extends StatelessWidget {
  final AutoAdvanceSettings settings;
  final void Function(AutoAdvanceSettings) onChanged;

  /// Auto-start count (kept for compatibility but not used for max limits)
  final int? autoStartCount;

  const AutoAdvanceSection({
    super.key,
    required this.settings,
    required this.onChanged,
    this.autoStartCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.autoAdvanceAt),
        Text(
          l10n.skipTimerEarly,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        // Proposing threshold toggle
        SwitchListTile(
          title: Text(l10n.enableAutoAdvanceProposing),
          value: settings.enableProposing,
          onChanged: (v) => onChanged(settings.copyWith(enableProposing: v)),
          contentPadding: EdgeInsets.zero,
        ),
        if (settings.enableProposing) ...[
          const SizedBox(height: 8),
          SettingInputCard(
            label: l10n.minParticipantsSubmit,
            description:
                l10n.proposingThresholdPreviewSimple(settings.proposingThresholdCount),
            value: settings.proposingThresholdCount,
            onChanged: (v) =>
                onChanged(settings.copyWith(proposingThresholdCount: v)),
            min: 3,
            max: 100,
          ),
        ],
        const SizedBox(height: 16),
        // Rating threshold toggle
        SwitchListTile(
          title: Text(l10n.enableAutoAdvanceRating),
          value: settings.enableRating,
          onChanged: (v) => onChanged(settings.copyWith(enableRating: v)),
          contentPadding: EdgeInsets.zero,
        ),
        if (settings.enableRating) ...[
          const SizedBox(height: 8),
          SettingInputCard(
            label: l10n.minAvgRaters,
            description: l10n.ratingThresholdPreview(settings.ratingThresholdCount),
            value: settings.ratingThresholdCount,
            onChanged: (v) =>
                onChanged(settings.copyWith(ratingThresholdCount: v)),
            min: 2,
            max: 100,
          ),
        ],
      ],
    );
  }
}
