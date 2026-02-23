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
import 'widgets/wizard_step_agents.dart';
import 'widgets/wizard_step_host_name.dart';
import 'widgets/wizard_step_indicator.dart';
import 'widgets/wizard_step_question.dart';
import 'widgets/wizard_step_timing.dart';

/// Multi-step wizard for creating a new chat.
/// Transforms the form into 2 focused steps for better UX.
class CreateChatWizard extends ConsumerStatefulWidget {
  const CreateChatWizard({super.key});

  @override
  ConsumerState<CreateChatWizard> createState() => _CreateChatWizardState();
}

class _CreateChatWizardState extends ConsumerState<CreateChatWizard> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Form keys for validation
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _messageController = TextEditingController();
  final _hostNameController = TextEditingController();
  bool _needsHostName = true;

  // Basic settings (hidden from UI - using defaults)
  final AccessMethod _accessMethod = AccessMethod.code;
  final List<String> _inviteEmails = [];
  final bool _requireAuth = false;
  final bool _requireApproval = true;
  final StartMode _startMode = StartMode.auto;
  final StartMode _ratingStartMode = StartMode.auto;
  final int _autoStartCount = 3;
  final bool _enableSchedule = false;

  // Timer settings - default to 5 minutes
  state.TimerSettings _timerSettings = const state.TimerSettings(
    useSameDuration: true,
    proposingPreset: '5min',
    ratingPreset: '5min',
    proposingDuration: 300,
    ratingDuration: 300,
  );

  // Other settings with defaults
  final state.MinimumSettings _minimumSettings = state.MinimumSettings.defaults();
  final state.AutoAdvanceSettings _autoAdvanceSettings =
      state.AutoAdvanceSettings.defaults();
  final state.AdaptiveDurationSettings _adaptiveSettings =
      state.AdaptiveDurationSettings.defaults();
  state.ScheduleSettings _scheduleSettings = state.ScheduleSettings.defaults();
  state.AgentSettings _agentSettings = state.AgentSettings.defaults();
  final state.ConsensusSettings _consensusSettings =
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
    _pageController.dispose();
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

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  int get _totalSteps => _needsHostName ? 4 : 3;

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  Future<void> _createChat() async {
    final l10n = AppLocalizations.of(context)!;

    // Validate host name is provided
    final hostName = _hostNameController.text.trim();
    if (_needsHostName && hostName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterYourName)),
      );
      return;
    }

    // Validate invite-only requires at least one email
    if (_accessMethod == AccessMethod.inviteOnly && _inviteEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.addEmailForInviteOnly)),
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

    // Validate schedule settings
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

      final messageText = _messageController.text.trim();
      final chat = await chatService.createChat(
        name: _nameController.text.trim(),
        initialMessage: messageText.isNotEmpty ? messageText : null,
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
        ratingThresholdPercent: 100, // 100% = all eligible raters must rate (capped to participants-1)
        ratingThresholdCount: _autoAdvanceSettings.enableRating
            ? _autoAdvanceSettings.ratingThresholdCount
            : null,
        enableAiParticipant: false, // AI proposer retired
        aiPropositionsCount: null,
        enableAgents: _agentSettings.enabled,
        proposingAgentCount: _agentSettings.agentCount,
        ratingAgentCount: _agentSettings.agentsAlsoRate
            ? _agentSettings.agentCount
            : 0,
        agentInstructions: _agentSettings.customizeAgents && _agentSettings.sharedInstructions.isNotEmpty
            ? _agentSettings.sharedInstructions
            : null,
        agentConfigs: _agentSettings.customizeAgents && _agentSettings.customizeIndividually
            ? _agentSettings.agents.map((a) => a.toJson()).toList()
            : null,
        confirmationRoundsRequired:
            _consensusSettings.confirmationRoundsRequired,
        showPreviousResults: _consensusSettings.showPreviousResults,
        propositionsPerUser: _consensusSettings.propositionsPerUser,
        adaptiveDurationEnabled: _adaptiveSettings.enabled,
        adaptiveAdjustmentPercent: _adaptiveSettings.adjustmentPercent,
        minPhaseDurationSeconds: _adaptiveSettings.minDurationSeconds,
        maxPhaseDurationSeconds: _adaptiveSettings.maxDurationSeconds,
        scheduleType: _enableSchedule
            ? (_scheduleSettings.type == state.ScheduleType.once
                ? ScheduleType.once
                : ScheduleType.recurring)
            : null,
        scheduleTimezone: _enableSchedule ? _scheduleSettings.timezone : null,
        scheduledStartAt: _enableSchedule &&
                _scheduleSettings.type == state.ScheduleType.once
            ? _scheduleSettings.scheduledStartAt
            : null,
        scheduleWindows: _enableSchedule &&
                _scheduleSettings.type == state.ScheduleType.recurring
            ? _scheduleSettings.windows
                .map((w) => ScheduleWindow.fromTimeOfDay(
                      startDay: w.startDay,
                      startTime: w.startTime,
                      endDay: w.endDay,
                      endTime: w.endTime,
                    ))
                .toList()
            : null,
        visibleOutsideSchedule: _scheduleSettings.visibleOutsideSchedule,
      );

      // Join as host
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
        hasAiParticipant: _agentSettings.enabled,
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
          onContinue: () {
            Navigator.pop(context, chat);
          },
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[CreateChatWizard] Error creating chat: $e');
      debugPrint('[CreateChatWizard] Stack trace: $stackTrace');
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
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            WizardStepIndicator(
              currentStep: _currentStep,
              totalSteps: _totalSteps,
            ),

            // Step content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentStep = index);
                },
                children: [
                  // Step 1: The Question (chat name + initial message)
                  WizardStepQuestion(
                    nameController: _nameController,
                    messageController: _messageController,
                    formKey: _step1FormKey,
                    onContinue: _nextStep,
                  ),

                  // Step 2: Set the Pace (timers)
                  WizardStepTiming(
                    timerSettings: _timerSettings,
                    onTimerSettingsChanged: (settings) {
                      setState(() => _timerSettings = settings);
                    },
                    onBack: _previousStep,
                    onContinue: _nextStep,
                  ),

                  // Step 3: AI Agents
                  WizardStepAgents(
                    agentSettings: _agentSettings,
                    onAgentSettingsChanged: (settings) {
                      setState(() => _agentSettings = settings);
                    },
                    onBack: _previousStep,
                    onContinue: _nextStep,
                    onCreate: _createChat,
                    needsHostName: _needsHostName,
                    isLoading: _isLoading,
                  ),

                  // Step 4: Host name (only if not already set)
                  if (_needsHostName)
                    WizardStepHostName(
                      hostNameController: _hostNameController,
                      formKey: _step2FormKey,
                      onBack: _previousStep,
                      onCreate: _createChat,
                      isLoading: _isLoading,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
