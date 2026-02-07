import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';
import '../models/create_chat_state.dart';
import 'form_inputs.dart';
import 'setting_input_card.dart';

/// Minimum to advance section with dynamic helper text explaining
/// how duration, threshold, and minimum interact.
class MinimumAdvanceSection extends StatelessWidget {
  final MinimumSettings settings;
  final void Function(MinimumSettings) onChanged;

  /// Optional context for dynamic helper text (only shown in auto mode)
  final StartMode? startMode;
  final int? autoStartCount;
  final int? proposingDuration;
  final int? proposingThreshold;

  const MinimumAdvanceSection({
    super.key,
    required this.settings,
    required this.onChanged,
    this.startMode,
    this.autoStartCount,
    this.proposingDuration,
    this.proposingThreshold,
  });

  String _formatDuration(int seconds) {
    if (seconds >= 86400) {
      final days = seconds ~/ 86400;
      return '$days day${days > 1 ? 's' : ''}';
    } else if (seconds >= 3600) {
      final hours = seconds ~/ 3600;
      return '$hours hour${hours > 1 ? 's' : ''}';
    } else if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      return '$minutes min';
    } else {
      return '$seconds sec';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showAutoHelper = startMode == StartMode.auto &&
        proposingDuration != null &&
        proposingThreshold != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.minimumToAdvance),
        Text(
          l10n.timeExtendsAutomatically,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        SettingInputCard(
          label: l10n.proposingMinimum,
          description: l10n.proposingMinimumDesc(settings.proposingMinimum),
          value: settings.proposingMinimum,
          onChanged: (v) => onChanged(settings.copyWith(proposingMinimum: v)),
          min: 3, // Minimum 3: users can't rate own, so need 2+ visible to each
          max: 100, // Not capped by auto-start count - more can join later
        ),
        const SizedBox(height: 12),
        SettingInputCard(
          label: l10n.ratingMinimum,
          description: l10n.ratingMinimumDesc(settings.ratingMinimum),
          value: settings.ratingMinimum,
          onChanged: (v) => onChanged(settings.copyWith(ratingMinimum: v)),
          min: 2, // Minimum 2 for meaningful alignment
        ),
        // Dynamic helper text showing how the settings interact (auto mode only)
        if (showAutoHelper) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.phaseFlowExplanation(
                      _formatDuration(proposingDuration!),
                      proposingThreshold!,
                      settings.proposingMinimum,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

