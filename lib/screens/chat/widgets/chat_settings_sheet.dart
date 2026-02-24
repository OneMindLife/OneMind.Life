import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../models/models.dart';

/// A bottom sheet that displays all chat settings in read-only mode.
/// Visible to all participants.
class ChatSettingsSheet extends StatelessWidget {
  final Chat chat;

  const ChatSettingsSheet({super.key, required this.chat});

  static void show(BuildContext context, Chat chat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ChatSettingsSheet(chat: chat),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.chatSettings,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Settings list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(
                  context,
                  AppLocalizations.of(context)!.basicInfo,
                  [
                    _buildSettingRow(context, AppLocalizations.of(context)!.chatName, chat.displayName),
                    if (chat.hostDisplayName != null)
                      _buildSettingRow(context, AppLocalizations.of(context)!.host, chat.hostDisplayName!),
                    if (chat.displayDescription != null && chat.displayDescription!.isNotEmpty)
                      _buildSettingRow(context, AppLocalizations.of(context)!.chatDescription, chat.displayDescription!),
                    if (chat.displayInitialMessage.isNotEmpty)
                      _buildSettingRow(context, AppLocalizations.of(context)!.initialMessage, chat.displayInitialMessage),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  AppLocalizations.of(context)!.accessAndVisibility,
                  [
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.accessMethod,
                      _formatAccessMethod(context, chat.accessMethod),
                    ),
                    // TODO: Re-enable when user authentication is implemented
                    // See docs/FEATURE_REQUESTS.md - "User Authentication"
                    // _buildSettingRow(
                    //   context,
                    //   'Require Authentication',
                    //   chat.requireAuth ? 'Yes' : 'No',
                    // ),
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.requireApproval,
                      chat.requireApproval ? AppLocalizations.of(context)!.yes : AppLocalizations.of(context)!.no,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  AppLocalizations.of(context)!.facilitation,
                  [
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.startMode,
                      chat.startMode == StartMode.auto ? AppLocalizations.of(context)!.autoMode : AppLocalizations.of(context)!.manual,
                    ),
                    if (chat.startMode == StartMode.auto &&
                        chat.autoStartParticipantCount != null)
                      _buildSettingRow(
                        context,
                        AppLocalizations.of(context)!.autoStartThreshold,
                        '${chat.autoStartParticipantCount} ${AppLocalizations.of(context)!.participants}',
                      ),
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.ratingStartMode,
                      chat.ratingStartMode == StartMode.auto ? AppLocalizations.of(context)!.autoMode : AppLocalizations.of(context)!.manual,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  AppLocalizations.of(context)!.timers,
                  [
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.proposingDuration,
                      _formatDuration(context, chat.proposingDurationSeconds),
                    ),
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.ratingDuration,
                      _formatDuration(context, chat.ratingDurationSeconds),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  AppLocalizations.of(context)!.minimumRequirements,
                  [
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.proposingMinimum,
                      '${chat.proposingMinimum} ${AppLocalizations.of(context)!.propositions}',
                    ),
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.ratingMinimum,
                      '${chat.ratingMinimum} ${AppLocalizations.of(context)!.avgRatersPerProposition}',
                    ),
                  ],
                ),
                if (chat.proposingThresholdCount != null ||
                    chat.ratingThresholdCount != null) ...[
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    AppLocalizations.of(context)!.earlyAdvanceThresholds,
                    [
                      if (chat.proposingThresholdCount != null)
                        _buildSettingRow(
                          context,
                          AppLocalizations.of(context)!.proposingThreshold,
                          '${chat.proposingThresholdCount} ${AppLocalizations.of(context)!.propositions}',
                        ),
                      if (chat.ratingThresholdCount != null)
                        _buildSettingRow(
                          context,
                          AppLocalizations.of(context)!.ratingThreshold,
                          AppLocalizations.of(context)!.nAvgRaters(chat.ratingThresholdCount!.toDouble()),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  AppLocalizations.of(context)!.consensus,
                  [
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.confirmationRounds,
                      AppLocalizations.of(context)!.nConsecutiveWins(chat.confirmationRoundsRequired),
                    ),
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.propositionsPerUser,
                      '${chat.propositionsPerUser}',
                    ),
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.showPreviousResults,
                      chat.showPreviousResults ? AppLocalizations.of(context)!.yes : AppLocalizations.of(context)!.no,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  AppLocalizations.of(context)!.translationsSection,
                  [
                    _buildSettingRow(
                      context,
                      AppLocalizations.of(context)!.translationLanguagesLabel,
                      chat.translationLanguages.join(', '),
                    ),
                    if (chat.translationsEnabled)
                      _buildSettingRow(
                        context,
                        AppLocalizations.of(context)!.autoTranslateLabel,
                        AppLocalizations.of(context)!.yes,
                      ),
                  ],
                ),
                if (chat.enableAiParticipant) ...[
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    AppLocalizations.of(context)!.aiParticipant,
                    [
                      _buildSettingRow(context, AppLocalizations.of(context)!.enabled, AppLocalizations.of(context)!.yes),
                      if (chat.aiPropositionsCount != null)
                        _buildSettingRow(
                          context,
                          AppLocalizations.of(context)!.aiPropositions,
                          '${chat.aiPropositionsCount} ${AppLocalizations.of(context)!.perRound}',
                        ),
                    ],
                  ),
                ],
                if (chat.hasSchedule) ...[
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    AppLocalizations.of(context)!.schedule,
                    [
                      _buildSettingRow(
                        context,
                        AppLocalizations.of(context)!.scheduleType,
                        chat.scheduleType == ScheduleType.once
                            ? AppLocalizations.of(context)!.oneTime
                            : AppLocalizations.of(context)!.recurring,
                      ),
                      _buildSettingRow(
                        context,
                        AppLocalizations.of(context)!.timezone,
                        chat.scheduleTimezone,
                      ),
                      if (chat.scheduleType == ScheduleType.once &&
                          chat.scheduledStartAt != null)
                        _buildSettingRow(
                          context,
                          AppLocalizations.of(context)!.scheduledStart,
                          _formatDateTime(chat.scheduledStartAt!),
                        ),
                      if (chat.scheduleType == ScheduleType.recurring &&
                          chat.scheduleWindows.isNotEmpty)
                        _buildSettingRow(
                          context,
                          AppLocalizations.of(context)!.windows,
                          '${chat.scheduleWindows.length} ${AppLocalizations.of(context)!.configured}',
                        ),
                      _buildSettingRow(
                        context,
                        AppLocalizations.of(context)!.visibleOutsideSchedule,
                        chat.visibleOutsideSchedule ? AppLocalizations.of(context)!.yes : AppLocalizations.of(context)!.no,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildSettingRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAccessMethod(BuildContext context, AccessMethod method) {
    switch (method) {
      case AccessMethod.public:
        return AppLocalizations.of(context)!.publicAccess;
      case AccessMethod.code:
        return AppLocalizations.of(context)!.inviteCodeAccess;
      case AccessMethod.inviteOnly:
        return AppLocalizations.of(context)!.inviteOnlyAccess;
    }
  }

  String _formatDuration(BuildContext context, int seconds) {
    final l10n = AppLocalizations.of(context)!;
    if (seconds < 60) {
      return l10n.nSeconds(seconds);
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return l10n.nMinutes(minutes);
    } else if (seconds < 86400) {
      final hours = seconds ~/ 3600;
      return l10n.nHours(hours);
    } else {
      final days = seconds ~/ 86400;
      return l10n.nDays(days);
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
