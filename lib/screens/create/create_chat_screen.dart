import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/timezone_utils.dart';
import '../../widgets/error_view.dart';
import 'dialogs/create_chat_dialogs.dart';
import 'models/create_chat_state.dart' as state;
import 'utils/create_chat_validation.dart';
// NOTE: AdaptiveDurationSection hidden - see docs/FEATURE_REQUESTS.md
// import 'widgets/adaptive_duration_section.dart';
// NOTE: AISection hidden - not implemented yet
// import 'widgets/ai_section.dart';
import 'widgets/auto_advance_section.dart';
import 'widgets/basic_info_section.dart';
import 'widgets/consensus_section.dart';
import 'widgets/minimum_advance_section.dart';
import 'widgets/phase_start_section.dart';
// import 'widgets/proposition_limits_section.dart'; // Hidden from UI
import 'widgets/timer_section.dart';
// import 'widgets/visibility_section.dart'; // Hidden from UI

class CreateChatScreen extends ConsumerStatefulWidget {
  const CreateChatScreen({super.key});

  @override
  ConsumerState<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends ConsumerState<CreateChatScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _messageController = TextEditingController();
  final _hostNameController = TextEditingController();
  bool _needsHostName = true;

  // Basic settings (hidden from UI - using defaults)
  final AccessMethod _accessMethod = AccessMethod.code;
  final List<String> _inviteEmails = [];
  final bool _requireAuth = false;
  final bool _requireApproval = true;
  // NOTE: Manual mode removed - host can't see propositions to know when to advance.
  // Always use auto mode with timers now.
  final StartMode _startMode = StartMode.auto;
  final StartMode _ratingStartMode = StartMode.auto;
  int _autoStartCount = 3;
  bool _enableSchedule = false; // Schedule disabled by default
  bool _userModifiedThreshold = false; // Track if user manually changed thresholds

  // Grouped settings - use test-friendly defaults
  // Timer: 3 minutes for quick testing
  state.TimerSettings _timerSettings = const state.TimerSettings(
    useSameDuration: true,
    proposingPreset: 'custom',
    ratingPreset: 'custom',
    proposingDuration: 180, // 3 minutes
    ratingDuration: 180, // 3 minutes
  );
  state.MinimumSettings _minimumSettings = state.MinimumSettings.defaults();
  state.AutoAdvanceSettings _autoAdvanceSettings =
      state.AutoAdvanceSettings.defaults();
  // Adaptive duration hidden - always use defaults (see docs/FEATURE_REQUESTS.md)
  final state.AdaptiveDurationSettings _adaptiveSettings =
      state.AdaptiveDurationSettings.defaults();
  // Schedule: one-time, 1 hour in future (schedule is hidden by default)
  state.ScheduleSettings _scheduleSettings = state.ScheduleSettings.defaults();
  // AI settings hidden - not implemented yet
  final state.AISettings _aiSettings = state.AISettings.defaults();
  state.ConsensusSettings _consensusSettings =
      state.ConsensusSettings.defaults();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _detectTimezone();
    _loadHostDisplayName();
  }

  void _loadHostDisplayName() {
    final authService = ref.read(authServiceProvider);
    final name = authService.displayName;
    if (name != null && name.isNotEmpty) {
      _hostNameController.text = name;
      setState(() => _needsHostName = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _messageController.dispose();
    _hostNameController.dispose();
    super.dispose();
  }

  Future<void> _detectTimezone() async {
    final detectedTz = await detectUserTimezone();
    if (mounted) {
      setState(() {
        _scheduleSettings = _scheduleSettings.copyWith(timezone: detectedTz);
      });
    }
  }

  /// Smart pre-population: update threshold suggestions based on participant count.
  /// Suggests threshold = 80% of participants (rounded up) for good participation.
  void _onAutoStartCountChanged(int count) {
    setState(() {
      _autoStartCount = count;

      // Suggest threshold = 80% of participants (rounded up), with floor of 3
      if (!_userModifiedThreshold) {
        final suggestedThreshold = ((count * 0.8).ceil()).clamp(3, count);
        _autoAdvanceSettings = _autoAdvanceSettings.copyWith(
          proposingThresholdCount: suggestedThreshold,
          ratingThresholdCount: (suggestedThreshold * 0.8).ceil().clamp(2, count),
        );

        // Also update minimum settings to not exceed participant count
        if (_minimumSettings.proposingMinimum > count) {
          _minimumSettings = _minimumSettings.copyWith(proposingMinimum: count);
        }
      }
    });
  }

  Future<void> _createChat() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;

    // Validate host name is provided
    final hostName = _hostNameController.text.trim();
    if (hostName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterYourName),
        ),
      );
      return;
    }

    // Validate invite-only requires at least one email
    if (_accessMethod == AccessMethod.inviteOnly && _inviteEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.addEmailForInviteOnly),
        ),
      );
      return;
    }

    // Validate adaptive duration settings
    if (_adaptiveSettings.enabled) {
      final error = CreateChatValidation.validateAdaptiveDuration(
        proposingDuration: _timerSettings.proposingDuration,
        ratingDuration: _timerSettings.ratingDuration,
        minDuration: _adaptiveSettings.minDurationSeconds,
        maxDuration: _adaptiveSettings.maxDurationSeconds,
      );
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }
    }

    // Validate schedule settings (schedule is independent of facilitation mode)
    if (_enableSchedule) {
      final scheduleError = CreateChatValidation.validateSchedule(
        type: _scheduleSettings.type,
        scheduledStartAt: _scheduleSettings.scheduledStartAt,
      );
      if (scheduleError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(scheduleError)),
        );
        return;
      }

      // Note: Timer/window validation is handled by the pause/resume feature
      // which preserves phase time when windows close mid-phase
    }

    setState(() => _isLoading = true);

    try {
      final chatService = ref.read(chatServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final authService = ref.read(authServiceProvider);

      // Save host name to auth metadata if not already set
      if (_needsHostName) {
        await authService.setDisplayName(hostName);
      }

      final chat = await chatService.createChat(
        name: _nameController.text.trim(),
        initialMessage: _messageController.text.trim(),
        accessMethod: _accessMethod,
        requireAuth: _requireAuth,
        requireApproval: _requireApproval,
        startMode: _startMode,
        hostDisplayName: hostName,
        ratingStartMode: _ratingStartMode,
        autoStartParticipantCount:
            _startMode == StartMode.auto ? _autoStartCount : null,
        proposingDurationSeconds: _timerSettings.proposingDuration,
        ratingDurationSeconds: _timerSettings.ratingDuration,
        proposingMinimum: _minimumSettings.proposingMinimum,
        ratingMinimum: _minimumSettings.ratingMinimum,
        proposingThresholdPercent: _autoAdvanceSettings.enableProposing
            ? _autoAdvanceSettings.proposingThresholdPercent
            : null,
        proposingThresholdCount: _autoAdvanceSettings.enableProposing
            ? _autoAdvanceSettings.proposingThresholdCount
            : null,
        ratingThresholdPercent: null, // Removed - only count threshold used for rating
        ratingThresholdCount: _autoAdvanceSettings.enableRating
            ? _autoAdvanceSettings.ratingThresholdCount
            : null,
        enableAiParticipant: _aiSettings.enabled,
        aiPropositionsCount:
            _aiSettings.enabled ? _aiSettings.propositionCount : null,
        confirmationRoundsRequired:
            _consensusSettings.confirmationRoundsRequired,
        showPreviousResults: _consensusSettings.showPreviousResults,
        propositionsPerUser: _consensusSettings.propositionsPerUser,
        adaptiveDurationEnabled: _adaptiveSettings.enabled,
        adaptiveAdjustmentPercent: _adaptiveSettings.adjustmentPercent,
        minPhaseDurationSeconds: _adaptiveSettings.minDurationSeconds,
        maxPhaseDurationSeconds: _adaptiveSettings.maxDurationSeconds,
        // Schedule settings (independent of startMode/facilitation)
        scheduleType: _enableSchedule
            ? (_scheduleSettings.type == state.ScheduleType.once
                ? ScheduleType.once
                : ScheduleType.recurring)
            : null,
        scheduleTimezone:
            _enableSchedule ? _scheduleSettings.timezone : null,
        scheduledStartAt: _enableSchedule &&
                _scheduleSettings.type == state.ScheduleType.once
            ? _scheduleSettings.scheduledStartAt
            : null,
        scheduleWindows: _enableSchedule &&
                _scheduleSettings.type == state.ScheduleType.recurring
            ? _scheduleSettings.windows.map((w) => ScheduleWindow.fromTimeOfDay(
                  startDay: w.startDay,
                  startTime: w.startTime,
                  endDay: w.endDay,
                  endTime: w.endTime,
                )).toList()
            : null,
        visibleOutsideSchedule: _scheduleSettings.visibleOutsideSchedule,
      );

      // Join as host (auth.uid() is used automatically)
      final hostParticipant = await participantService.joinChat(
        chatId: chat.id,
        displayName: hostName,
        isHost: true,
      );

      // Send email invites if using invite-only mode
      int invitesSent = 0;
      if (_accessMethod == AccessMethod.inviteOnly && _inviteEmails.isNotEmpty) {
        final inviteService = ref.read(inviteServiceProvider);
        final results = await inviteService.sendInvites(
          chatId: chat.id,
          emails: _inviteEmails,
          invitedByParticipantId: hostParticipant.id,
          chatName: chat.name,
          inviteCode: chat.inviteCode ?? '',
          inviterName: hostName,
        );
        invitesSent = results.length;
      }

      // Log analytics event
      ref.read(analyticsServiceProvider).logChatCreated(
        chatId: chat.id.toString(),
        hasAiParticipant: _aiSettings.enabled,
        confirmationRounds: _consensusSettings.confirmationRoundsRequired,
        autoAdvanceProposing: _autoAdvanceSettings.enableProposing,
        autoAdvanceRating: _autoAdvanceSettings.enableRating,
      );

      if (mounted) {
        CreateChatDialogs.showSuccess(
          context: context,
          chat: chat,
          accessMethod: _accessMethod,
          invitesSent: invitesSent,
          onContinue: () => Navigator.pop(context, chat),
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createChatTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Host name section - only show if name not already set
            if (_needsHostName) ...[
              Text(
                l10n.yourName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('host_name_field'),
                controller: _hostNameController,
                decoration: InputDecoration(
                  labelText: l10n.displayName,
                  hintText: l10n.enterYourName,
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.pleaseEnterYourName;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
            ],
            BasicInfoSection(
              nameController: _nameController,
              messageController: _messageController,
            ),
            // VisibilitySection hidden - defaults to invite code with approval required
            // VisibilitySection(
            //   accessMethod: _accessMethod,
            //   inviteEmails: _inviteEmails,
            //   requireAuth: _requireAuth,
            //   requireApproval: _requireApproval,
            //   onAccessMethodChanged: (v) => setState(() => _accessMethod = v),
            //   onEmailsChanged: (v) => setState(() => _inviteEmails = v),
            //   onRequireAuthChanged: (v) => setState(() => _requireAuth = v),
            //   onRequireApprovalChanged: (v) =>
            //       setState(() => _requireApproval = v),
            // ),
            // NOTE: PhaseStartSection hidden - using defaults:
            // - Always auto mode (manual removed - host can't see propositions)
            // - Auto-start count = 3 (minimum needed for meaningful consensus)
            // - Schedule disabled
            // const SizedBox(height: 32),
            // PhaseStartSection(
            //   autoStartCount: _autoStartCount,
            //   enableSchedule: _enableSchedule,
            //   scheduleSettings: _scheduleSettings,
            //   onAutoStartCountChanged: _onAutoStartCountChanged,
            //   onEnableScheduleChanged: (v) =>
            //       setState(() => _enableSchedule = v),
            //   onScheduleSettingsChanged: (v) =>
            //       setState(() => _scheduleSettings = v),
            // ),
            const SizedBox(height: 32),
            TimerSection(
              settings: _timerSettings,
              onChanged: (v) => setState(() => _timerSettings = v),
            ),
            // NOTE: MinimumAdvanceSection hidden - using defaults:
            // - proposingMinimum = 3 (need 3+ ideas before phase can end)
            // - ratingMinimum = 2 (each idea needs 2+ ratings)
            // const SizedBox(height: 32),
            // MinimumAdvanceSection(
            //   settings: _minimumSettings,
            //   onChanged: (v) => setState(() => _minimumSettings = v),
            //   startMode: _startMode,
            //   autoStartCount: _autoStartCount,
            //   proposingDuration: _timerSettings.proposingDuration,
            //   proposingThreshold: _autoAdvanceSettings.enableProposing
            //       ? _autoAdvanceSettings.proposingThresholdCount
            //       : null,
            // ),
            // NOTE: AutoAdvanceSection hidden - using smart defaults:
            // - Proposing: ends when 100% of participants have acted (submitted OR skipped)
            // - Rating: ends when each proposition has 10 ratings (enough signal)
            // const SizedBox(height: 32),
            // AutoAdvanceSection(
            //   settings: _autoAdvanceSettings,
            //   autoStartCount: _autoStartCount,
            //   onChanged: (v) {
            //     setState(() {
            //       _autoAdvanceSettings = v;
            //       _userModifiedThreshold = true;
            //     });
            //   },
            // ),
            // NOTE: AISection hidden - not implemented yet
            // const SizedBox(height: 32),
            // AISection(
            //   settings: _aiSettings,
            //   onChanged: (v) => setState(() => _aiSettings = v),
            // ),
            // PropositionLimitsSection hidden - default to 1 proposition per user
            // PropositionLimitsSection(
            //   propositionsPerUser: _consensusSettings.propositionsPerUser,
            //   onChanged: (v) => setState(() {
            //     _consensusSettings =
            //         _consensusSettings.copyWith(propositionsPerUser: v);
            //   }),
            // ),
            const SizedBox(height: 32),
            ConsensusSection(
              settings: _consensusSettings,
              onChanged: (v) => setState(() => _consensusSettings = v),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _createChat,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : Text(l10n.createChat),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
