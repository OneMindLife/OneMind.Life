import 'package:flutter/material.dart';
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
                    'Chat Settings',
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
                  'Basic Info',
                  [
                    _buildSettingRow(context, 'Name', chat.displayName),
                    if (chat.hostDisplayName != null)
                      _buildSettingRow(context, 'Host', chat.hostDisplayName!),
                    _buildSettingRow(context, 'Initial Message', chat.displayInitialMessage),
                    if (chat.displayDescription != null && chat.displayDescription!.isNotEmpty)
                      _buildSettingRow(context, 'Description', chat.displayDescription!),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  'Access & Visibility',
                  [
                    _buildSettingRow(
                      context,
                      'Access Method',
                      _formatAccessMethod(chat.accessMethod),
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
                      'Require Approval',
                      chat.requireApproval ? 'Yes' : 'No',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  'Facilitation',
                  [
                    _buildSettingRow(
                      context,
                      'Start Mode',
                      chat.startMode == StartMode.auto ? 'Auto' : 'Manual',
                    ),
                    if (chat.startMode == StartMode.auto &&
                        chat.autoStartParticipantCount != null)
                      _buildSettingRow(
                        context,
                        'Auto-Start Threshold',
                        '${chat.autoStartParticipantCount} participants',
                      ),
                    _buildSettingRow(
                      context,
                      'Rating Start Mode',
                      chat.ratingStartMode == StartMode.auto ? 'Auto' : 'Manual',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  'Timers',
                  [
                    _buildSettingRow(
                      context,
                      'Proposing Duration',
                      _formatDuration(chat.proposingDurationSeconds),
                    ),
                    _buildSettingRow(
                      context,
                      'Rating Duration',
                      _formatDuration(chat.ratingDurationSeconds),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  'Minimum Requirements',
                  [
                    _buildSettingRow(
                      context,
                      'Proposing Minimum',
                      '${chat.proposingMinimum} propositions',
                    ),
                    _buildSettingRow(
                      context,
                      'Rating Minimum',
                      '${chat.ratingMinimum} avg raters per proposition',
                    ),
                  ],
                ),
                if (chat.proposingThresholdCount != null ||
                    chat.ratingThresholdCount != null) ...[
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    'Early Advance Thresholds',
                    [
                      if (chat.proposingThresholdCount != null)
                        _buildSettingRow(
                          context,
                          'Proposing Threshold',
                          '${chat.proposingThresholdCount} propositions',
                        ),
                      if (chat.ratingThresholdCount != null)
                        _buildSettingRow(
                          context,
                          'Rating Threshold',
                          '${chat.ratingThresholdCount} avg raters',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  'Consensus',
                  [
                    _buildSettingRow(
                      context,
                      'Confirmation Rounds',
                      '${chat.confirmationRoundsRequired} consecutive wins',
                    ),
                    _buildSettingRow(
                      context,
                      'Propositions Per User',
                      '${chat.propositionsPerUser}',
                    ),
                    _buildSettingRow(
                      context,
                      'Show Previous Results',
                      chat.showPreviousResults ? 'Yes' : 'No',
                    ),
                  ],
                ),
                if (chat.enableAiParticipant) ...[
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    'AI Participant',
                    [
                      _buildSettingRow(context, 'Enabled', 'Yes'),
                      if (chat.aiPropositionsCount != null)
                        _buildSettingRow(
                          context,
                          'AI Propositions',
                          '${chat.aiPropositionsCount} per round',
                        ),
                    ],
                  ),
                ],
                if (chat.hasSchedule) ...[
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    'Schedule',
                    [
                      _buildSettingRow(
                        context,
                        'Schedule Type',
                        chat.scheduleType == ScheduleType.once
                            ? 'One-time'
                            : 'Recurring',
                      ),
                      _buildSettingRow(
                        context,
                        'Timezone',
                        chat.scheduleTimezone,
                      ),
                      if (chat.scheduleType == ScheduleType.once &&
                          chat.scheduledStartAt != null)
                        _buildSettingRow(
                          context,
                          'Scheduled Start',
                          _formatDateTime(chat.scheduledStartAt!),
                        ),
                      if (chat.scheduleType == ScheduleType.recurring &&
                          chat.scheduleWindows.isNotEmpty)
                        _buildSettingRow(
                          context,
                          'Windows',
                          '${chat.scheduleWindows.length} configured',
                        ),
                      _buildSettingRow(
                        context,
                        'Visible Outside Schedule',
                        chat.visibleOutsideSchedule ? 'Yes' : 'No',
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

  String _formatAccessMethod(AccessMethod method) {
    switch (method) {
      case AccessMethod.public:
        return 'Public';
      case AccessMethod.code:
        return 'Invite Code';
      case AccessMethod.inviteOnly:
        return 'Invite Only';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds seconds';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return '$minutes minute${minutes == 1 ? '' : 's'}';
    } else if (seconds < 86400) {
      final hours = seconds ~/ 3600;
      return '$hours hour${hours == 1 ? '' : 's'}';
    } else {
      final days = seconds ~/ 86400;
      return '$days day${days == 1 ? '' : 's'}';
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
