import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/analytics_service.dart';
import '../../utils/timezone_utils.dart';
import '../../widgets/error_view.dart';
import 'models/create_chat_state.dart' as state;
import 'utils/cadence.dart';
import 'utils/create_chat_validation.dart';
import '../../widgets/name_section.dart';
import 'widgets/wizard_step_agents.dart';
import 'widgets/wizard_step_auto_advance.dart';
import 'widgets/wizard_step_convergence.dart';
import 'widgets/wizard_step_first_deadline.dart';
import 'widgets/wizard_step_host_name.dart';
import 'widgets/wizard_step_indicator.dart';
import 'widgets/wizard_step_participation.dart';
import 'widgets/wizard_step_question.dart';
import 'widgets/wizard_step_schedule.dart';
import 'widgets/wizard_step_timing.dart';
import 'widgets/wizard_step_translations.dart';
import 'widgets/wizard_step_visibility.dart';

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

  // Analytics funnel tracking
  late final AnalyticsService _analytics;
  bool _chatCreated = false;
  // Step order depends on the schedule mode (both branches are 10 steps):
  //  * Always Active skips the schedule-config screen entirely (nothing to
  //    configure — the chat starts the moment it's created) and instead gets
  //    a dedicated "First deadline" step AFTER timing, so the cadence anchor
  //    always knows the chosen duration.
  //  * Once/recurring keep schedule-config and have no cadence step.
  // Creators without a display name get an extra final "host name" step
  // (creating auto-joins them as host, so a name is required).
  List<String> get _stepNames => [
    'question', 'visibility', 'schedule',
    if (_scheduleMode == ScheduleMode.always)
      ...['timing', 'first_deadline']
    else
      ...['schedule_config', 'timing'],
    'auto_advance', 'participation', 'convergence', 'translations', 'agents',
    if (_needsHostName) 'host_name',
  ];
  String _stepName(int i) {
    final names = _stepNames;
    return (i >= 0 && i < names.length) ? names[i] : 'step_$i';
  }

  // Form keys for validation
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _messageController = TextEditingController();
  // Host name gate: creating auto-joins the creator as host, so a display
  // name is required before create. Users without one get a dedicated final
  // step ('host_name'); users with one never see it. Captured ONCE at wizard
  // open — saving the name during create must not reshuffle the live pages.
  final _hostNameController = TextEditingController();
  late final bool _needsHostName;

  // Visibility setting (user-selectable in step 2). Default Private.
  AccessMethod _accessMethod = AccessMethod.code;
  final List<String> _inviteEmails = [];
  final bool _requireAuth = false;
  bool _requireApproval = false;
  final StartMode _startMode = StartMode.auto;
  final StartMode _ratingStartMode = StartMode.auto;
  // Start as soon as the host joins (count == 1) so creators can participate
  // immediately — AI seat-fill provides ideas to vote on for a solo/sparse
  // group, and humans who join during the 12h proposing window take part too.
  final int _autoStartCount = 1;
  bool _enableSchedule = false;
  // Explicit schedule mode (the picker can't derive it: "Always Active" and
  // "Specific time" map differently onto enableSchedule underneath).
  ScheduleMode _scheduleMode = ScheduleMode.always;

  // Cadence anchor: the user-chosen end of the FIRST phase (timing step).
  // null = no cadence, plain duration chaining — the default. Only meaningful
  // for Always-Active chats with coherent (equal, 24h-dividing) durations;
  // cleared VISIBLY whenever the mode or durations stop supporting it (the
  // anchor section disappears and the state resets to null).
  DateTime? _cadenceAnchorAt;

  // Timer settings - default to Custom, 12 hours per phase
  state.TimerSettings _timerSettings = const state.TimerSettings(
    useSameDuration: true,
    proposingPreset: 'custom',
    ratingPreset: 'custom',
    proposingDuration: 43200, // 12 hours
    ratingDuration: 43200, // 12 hours
  );

  // Other settings with defaults
  final state.MinimumSettings _minimumSettings = state.MinimumSettings.defaults();
  state.AutoAdvanceSettings _autoAdvanceSettings =
      state.AutoAdvanceSettings.defaults();
  final state.AdaptiveDurationSettings _adaptiveSettings =
      state.AdaptiveDurationSettings.defaults();
  state.ScheduleSettings _scheduleSettings = state.ScheduleSettings.defaults();
  // Default agents ON, but propose-only (agentsAlsoRate:false → ratingAgentCount
  // 0): agents seed ideas without voting in the rating phase.
  state.AgentSettings _agentSettings =
      state.AgentSettings.defaults().copyWith(enabled: true, agentsAlsoRate: false);
  state.TranslationSettings _translationSettings = state.TranslationSettings.defaults();
  state.SkipSettings _skipSettings = state.SkipSettings.defaults();
  // Default to Instant mode (confirmationRoundsRequired:1 — winner locks in
  // immediately, no 2nd confirmation round).
  state.ConsensusSettings _consensusSettings =
      state.ConsensusSettings.defaults().copyWith(confirmationRoundsRequired: 1);

  /// Rating UX: 'matches' (pairwise, default) or 'grid' (0-100 placement).
  String _ratingMode = 'matches';

  /// Matches objective: 'winner_only' (default) or 'full_rank'.
  String _matchObjective = 'winner_only';

  bool _isLoading = false;
  bool _translationLanguageInitialized = false;

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(analyticsServiceProvider);
    _needsHostName = !ref.read(authServiceProvider).hasDisplayName;
    // Default: Always Active — the chat begins the moment it's created
    // (auto-start on the host's join; _autoStartCount == 1), so creators
    // participate immediately. The optional first-deadline cadence anchor is
    // chosen on the timing step.
    _detectTimezone();
    _analytics.logCreateChatOpened();
    _analytics.logCreateChatStepViewed(stepIndex: 0, stepName: _stepName(0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_translationLanguageInitialized) {
      _translationLanguageInitialized = true;
      final locale = Localizations.localeOf(context);
      final langCode = locale.languageCode;
      // Use user's locale if it's one of our supported languages
      const supported = {'en', 'es', 'pt', 'fr', 'de'};
      final defaultLang = supported.contains(langCode) ? langCode : 'en';
      _translationSettings = state.TranslationSettings(
        enabled: false,
        languages: {defaultLang},
      );
    }
  }

  @override
  void dispose() {
    if (!_chatCreated) {
      _analytics.logCreateChatAbandoned(
        lastStepIndex: _currentStep,
        lastStepName: _stepName(_currentStep),
      );
    }
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

  void _onScheduleModeChanged(ScheduleMode mode) {
    setState(() {
      _scheduleMode = mode;
      switch (mode) {
        case ScheduleMode.always:
          // Always Active = starts the moment it's created, no schedule.
          _enableSchedule = false;
        case ScheduleMode.once:
          _enableSchedule = true;
          _scheduleSettings =
              _scheduleSettings.copyWith(type: state.ScheduleType.once);
          // Cadence is Always-Active-only: leaving the mode clears the anchor
          // (the timing-step section disappears with it — visibly, not silently).
          _cadenceAnchorAt = null;
        case ScheduleMode.recurring:
          _enableSchedule = true;
          _scheduleSettings = _scheduleSettings.copyWith(
            type: state.ScheduleType.recurring,
            windows: _scheduleSettings.windows.isEmpty
                ? [state.ScheduleWindow.defaults()]
                : null,
          );
          _cadenceAnchorAt = null;
      }
    });
  }

  void _onTimerSettingsChanged(state.TimerSettings settings) {
    setState(() {
      _timerSettings = settings;
      // Durations no longer coherent -> the First-deadline step's controls
      // become unavailable and the anchor resets to null (visibly).
      if (!isCadenceCoherent(
        settings.proposingDuration,
        settings.ratingDuration,
      )) {
        _cadenceAnchorAt = null;
      }
    });
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _analytics.logCreateChatStepViewed(
      stepIndex: step,
      stepName: _stepName(step),
    );
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  int get _totalSteps => _needsHostName ? 11 : 10;

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
    // Name gate: creating auto-joins the creator as host, so resolve the
    // stored display name or save the one typed on the agents step.
    final hostName = await commitNameSection(ref, _hostNameController);
    if (hostName == null) {
      if (mounted) context.showErrorMessage(l10n.pleaseEnterName);
      return;
    }

    // Validate invite-only requires at least one email
    if (_accessMethod == AccessMethod.inviteOnly && _inviteEmails.isEmpty) {
      context.showErrorMessage(l10n.addEmailForInviteOnly);
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
        context.showErrorMessage(error);
        return;
      }
    }

    // Validate schedule settings
    if (_enableSchedule) {
      final scheduleError = CreateChatValidation.validateSchedule(
        type: _scheduleSettings.type,
        scheduledStartAt: _scheduleSettings.scheduledStartAt,
        scheduledEndAt: _scheduleSettings.scheduledEndAt,
      );
      if (scheduleError != null) {
        context.showErrorMessage(scheduleError);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final chatService = ref.read(chatServiceProvider);
      final participantService = ref.read(participantServiceProvider);

      final messageText = _messageController.text.trim();
      final chat = await chatService.createChat(
        name: _nameController.text.trim(),
        initialMessage: messageText.isNotEmpty ? messageText : null,
        // The cadence anchor is explicit user data from the timing step
        // (Always-Active only; state is cleared on mode change, but guard
        // anyway so a stale anchor can never ride along).
        cadenceAnchorAt:
            _scheduleMode == ScheduleMode.always ? _cadenceAnchorAt : null,
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
        ratingThresholdPercent: _autoAdvanceSettings.enableRating
            ? _autoAdvanceSettings.ratingThresholdPercent
            : null, // null => rating auto-advance fully disabled (timer-only)
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
        ratingMode: _ratingMode,
        matchObjective: _matchObjective,
        adaptiveDurationEnabled: _adaptiveSettings.enabled,
        adaptiveAdjustmentPercent: _adaptiveSettings.adjustmentPercent,
        minPhaseDurationSeconds: _adaptiveSettings.minDurationSeconds,
        maxPhaseDurationSeconds: _adaptiveSettings.maxDurationSeconds,
        scheduleType: _enableSchedule
            ? (_scheduleSettings.type == state.ScheduleType.once
                ? ScheduleType.once
                : ScheduleType.recurring)
            : null,
        // Always-Active chats always carry the auto-detected device timezone:
        // it is the reference zone for the cadence grid (and harmless without
        // an anchor). Scheduled modes send it with their schedule as before.
        scheduleTimezone:
            (_enableSchedule || _scheduleMode == ScheduleMode.always)
                ? _scheduleSettings.timezone
                : null,
        scheduledStartAt: _enableSchedule &&
                _scheduleSettings.type == state.ScheduleType.once
            ? _scheduleSettings.scheduledStartAt
            : null,
        scheduledEndAt: _enableSchedule &&
                _scheduleSettings.type == state.ScheduleType.once
            ? _scheduleSettings.scheduledEndAt
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
        translationsEnabled: _translationSettings.enabled,
        translationLanguages: _translationSettings.languages.toList(),
        allowSkipProposing: _skipSettings.allowSkipProposing,
        allowSkipRating: _skipSettings.allowSkipRating,
      );

      // Join as host
      final hostParticipant = await participantService.joinChat(
        chatId: chat.id,
        displayName: hostName,
        isHost: true,
      );

      // Send email invites if using invite-only mode
      if (_accessMethod == AccessMethod.inviteOnly && _inviteEmails.isNotEmpty) {
        final inviteService = ref.read(inviteServiceProvider);
        await inviteService.sendInvites(
          chatId: chat.id,
          emails: _inviteEmails,
          invitedByParticipantId: hostParticipant.id,
          chatName: chat.name,
          inviteCode: chat.inviteCode ?? '',
          inviterName: hostName,
        );
      }

      // Log analytics event
      ref.read(analyticsServiceProvider).logChatCreated(
        chatId: chat.id.toString(),
        hasAiParticipant: _agentSettings.enabled,
        confirmationRounds: _consensusSettings.confirmationRoundsRequired,
        autoAdvanceProposing: _autoAdvanceSettings.enableProposing,
        autoAdvanceRating: _autoAdvanceSettings.enableRating,
      );
      _chatCreated = true;

      if (mounted) {
        Navigator.pop(context, chat);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorMessage(e.toString());
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _currentStep == 0
              ? () => Navigator.pop(context)
              : _previousStep,
        ),
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

                  // Step 2: Who Can Join? (public/private toggle)
                  WizardStepVisibility(
                    accessMethod: _accessMethod,
                    onAccessMethodChanged: (method) {
                      setState(() => _accessMethod = method);
                    },
                    onContinue: _nextStep,
                  ),

                  // Step 3: Set a schedule (mode picker)
                  WizardStepSchedule(
                    scheduleMode: _scheduleMode,
                    onScheduleModeChanged: _onScheduleModeChanged,
                    onContinue: _nextStep,
                  ),

                  // Always Active: timing then the dedicated First-deadline
                  // step (the schedule-config screen is skipped — nothing to
                  // configure). Other modes: schedule-config then timing.
                  if (_scheduleMode == ScheduleMode.always) ...[
                    WizardStepTiming(
                      timerSettings: _timerSettings,
                      onTimerSettingsChanged: _onTimerSettingsChanged,
                      onContinue: _nextStep,
                    ),
                    WizardStepFirstDeadline(
                      timerSettings: _timerSettings,
                      cadenceAnchorAt: _cadenceAnchorAt,
                      onCadenceAnchorChanged: (anchor) {
                        setState(() => _cadenceAnchorAt = anchor);
                      },
                      timezoneName: _scheduleSettings.timezone,
                      adaptiveEnabled: _adaptiveSettings.enabled,
                      onContinue: _nextStep,
                    ),
                  ] else ...[
                    WizardStepScheduleConfig(
                      scheduleMode: _scheduleMode,
                      scheduleSettings: _scheduleSettings,
                      onScheduleSettingsChanged: (settings) {
                        setState(() => _scheduleSettings = settings);
                      },
                      onContinue: _nextStep,
                    ),
                    WizardStepTiming(
                      timerSettings: _timerSettings,
                      onTimerSettingsChanged: _onTimerSettingsChanged,
                      onContinue: _nextStep,
                    ),
                  ],

                  // Step 4: Auto-advance (early advance toggle)
                  WizardStepAutoAdvance(
                    autoAdvanceSettings: _autoAdvanceSettings,
                    onAutoAdvanceSettingsChanged: (settings) {
                      setState(() => _autoAdvanceSettings = settings);
                    },
                    onContinue: _nextStep,
                  ),

                  // Step 5: Participation (skip settings)
                  WizardStepParticipation(
                    skipSettings: _skipSettings,
                    onSkipSettingsChanged: (settings) {
                      setState(() => _skipSettings = settings);
                    },
                    onContinue: _nextStep,
                  ),

                  // Step 5: Convergence (instant vs confirmation rounds)
                  WizardStepConvergence(
                    consensusSettings: _consensusSettings,
                    onConsensusSettingsChanged: (settings) {
                      setState(() => _consensusSettings = settings);
                    },
                    ratingMode: _ratingMode,
                    onRatingModeChanged: (mode) {
                      setState(() => _ratingMode = mode);
                    },
                    matchObjective: _matchObjective,
                    onMatchObjectiveChanged: (obj) {
                      setState(() => _matchObjective = obj);
                    },
                    onContinue: _nextStep,
                  ),

                  // Step 9: Translations
                  WizardStepTranslations(
                    translationSettings: _translationSettings,
                    onTranslationSettingsChanged: (settings) {
                      setState(() => _translationSettings = settings);
                    },
                    onContinue: _nextStep,
                  ),

                  // AI Agents — final step unless a host-name step follows
                  WizardStepAgents(
                    agentSettings: _agentSettings,
                    onAgentSettingsChanged: (settings) {
                      setState(() => _agentSettings = settings);
                    },
                    onContinue: _nextStep,
                    onCreate: _createChat,
                    isFinalStep: !_needsHostName,
                    isLoading: _isLoading,
                  ),

                  // Host name gate (only for creators with no display name)
                  if (_needsHostName)
                    WizardStepHostName(
                      controller: _hostNameController,
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
