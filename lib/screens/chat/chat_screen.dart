import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../../services/proposition_service.dart';
import '../../widgets/error_view.dart';
import '../../core/l10n/locale_provider.dart';
import '../../widgets/chat_language_selector.dart';
import '../../widgets/glossary_term.dart';
import '../../widgets/proposition_content_card.dart';
import '../../widgets/qr_code_share.dart';
import '../rating/rating_screen.dart';
import 'widgets/previous_round_display.dart';
import 'widgets/phase_panels.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _propositionController = TextEditingController();

  // UI toggle states (not data - stay in widget)
  bool _showPreviousWinner = false;
  int _currentWinnerIndex = 0;
  int? _lastPreviousWinnerRoundId; // Track to auto-switch when new winners arrive
  int? _lastAutoNavigatedRoundId; // Track to auto-navigate to rating screen once per round
  bool _initialPhaseRecorded = false; // Whether we've recorded the phase on first load
  RoundPhase? _phaseOnOpen; // The phase when user first opened this screen

  // Prevent duplicate submissions from rapid double-clicks
  bool _isSubmitting = false;
  bool _isSkipping = false;

  // Track if we've already navigated away (to prevent double-pop)
  bool _hasNavigatedAway = false;

  // Timer to refresh UI when scheduled time arrives
  Timer? _scheduledTimeTimer;

  // App lifecycle listener to refresh state when app resumes from background
  // This fixes the bug where timer shows "expired" after returning from background
  // because realtime events may have been missed while the app was backgrounded.
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _setupScheduledTimeTimer();
    _setupLifecycleListener();
  }

  /// Sets up app lifecycle listener to refresh state when app resumes.
  /// This ensures the timer and phase data are up-to-date after the app
  /// returns from background, catching any realtime events that were missed.
  void _setupLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onResume: _onAppResume,
    );
  }

  /// Called when app resumes from background.
  /// Triggers a silent refresh to fetch fresh state from server without showing loading spinner.
  void _onAppResume() {
    if (!mounted) return;
    // Refresh the chat detail state to catch any updates missed while backgrounded
    // Use silent: true to avoid visual disruption when switching tabs
    ref.read(chatDetailProvider(_params).notifier).refresh(silent: true);
  }

  void _setupScheduledTimeTimer() {
    // Only set timer for one-time scheduled chats with future start time
    final chat = widget.chat;
    if (chat.hasSchedule &&
        chat.scheduleType == ScheduleType.once &&
        chat.scheduledStartAt != null) {
      final now = DateTime.now();
      final scheduledTime = chat.scheduledStartAt!;

      if (scheduledTime.isAfter(now)) {
        final duration = scheduledTime.difference(now);
        _scheduledTimeTimer = Timer(duration, () {
          if (mounted) {
            setState(() {});
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _scheduledTimeTimer?.cancel();
    _propositionController.dispose();
    super.dispose();
  }

  // No more sessionToken needed - auth is automatic via JWT!
  ChatDetailParams get _params => ChatDetailParams(
        chatId: widget.chat.id,
        showPreviousResults: widget.chat.showPreviousResults,
      );

  Future<void> _submitProposition() async {
    if (_propositionController.text.trim().isEmpty) return;

    // Prevent duplicate submissions from rapid double-clicks
    if (_isSubmitting) return;

    final content = _propositionController.text.trim();

    setState(() => _isSubmitting = true);
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.submitProposition(content);
      _propositionController.clear();

      // Log analytics event
      final state = ref.read(chatDetailProvider(_params)).valueOrNull;
      ref.read(analyticsServiceProvider).logPropositionSubmitted(
        chatId: widget.chat.id.toString(),
        roundNumber: state?.currentRound?.customId ?? 1,
        contentLength: content.length,
      );
    } on DuplicatePropositionException {
      // User-friendly message for duplicate propositions
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.duplicateProposition),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToSubmit(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _skipProposing() async {
    if (_isSkipping) return;
    setState(() => _isSkipping = true);
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.skipProposing();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToSubmit(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSkipping = false);
    }
  }

  Future<void> _skipRating() async {
    if (_isSkipping) return;
    setState(() => _isSkipping = true);
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.skipRating();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToSubmit(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSkipping = false);
    }
  }

  void _openRatingScreen(ChatDetailState state) {
    if (state.currentRound == null || state.myParticipant == null) return;

    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RatingScreen(
          roundId: state.currentRound!.id,
          participantId: state.myParticipant!.id,
          chatId: widget.chat.id,
          showPreviousResults: widget.chat.showPreviousResults,
        ),
      ),
    ).then((success) {
      if (success == true) {
        ref.read(chatDetailProvider(_params).notifier).markAsRated();
      }
    });
  }

  Future<void> _advanceToRating() async {
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.advanceToRating(widget.chat);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToAdvancePhase(e.toString()))),
        );
      }
    }
  }

  Future<void> _advanceFromRating() async {
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.completeRatingPhase(widget.chat);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToCompleteRating(e.toString()))),
        );
      }
    }
  }

  void _onPhaseExpired() {
    // Refresh data when phase timer expires to get new state
    ref.read(chatDetailProvider(_params).notifier).refresh();
  }

  Future<void> _deleteProposition(int propositionId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.deleteProposition(propositionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.propositionDeleted)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToDelete(e.toString()))),
        );
      }
    }
  }

  void _showAllPropositionsSheet(ChatDetailState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Consumer(
          builder: (context, ref, _) {
            // Watch provider for reactive updates
            final stateAsync = ref.watch(chatDetailProvider(_params));
            return stateAsync.when(
              data: (currentState) => _buildPropositionsSheetContent(
                context,
                scrollController,
                currentState,
                sheetContext,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(AppLocalizations.of(context).error(e.toString()))),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPropositionsSheetContent(
    BuildContext context,
    ScrollController scrollController,
    ChatDetailState state,
    BuildContext sheetContext,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final propositions = state.propositions;
    final myPropositionIds = state.myPropositions.map((p) => p.id).toSet();

    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                l10n.allPropositionsCount(propositions.length),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.hostCanModerateContent,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        // Propositions list
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: propositions.length,
            itemBuilder: (context, index) {
              final prop = propositions[index];
              final isMine = myPropositionIds.contains(prop.id);
              return _buildHostPropositionCard(context, prop, index, isMine, sheetContext);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHostPropositionCard(
    BuildContext context,
    Proposition prop,
    int index,
    bool isMine,
    BuildContext sheetContext,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PropositionContentCard(
                  content: prop.displayContent,
                  maxHeight: 100,
                  backgroundColor: isMine
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : null,
                  borderColor: isMine
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : null,
                ),
              ),
              // Don't allow deleting carried forward (winner) propositions
              if (!prop.isCarriedForward)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  onPressed: () => _confirmDeleteFromSheet(prop, sheetContext),
                  tooltip: 'Delete proposition',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          // Labels below the card
          if (isMine || prop.isCarriedForward)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Row(
                children: [
                  if (isMine)
                    Text(
                      l10n.yourPropositionLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (isMine && prop.isCarriedForward)
                    const SizedBox(width: 8),
                  if (prop.isCarriedForward)
                    Text(
                      l10n.previousWinnerLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _confirmDeleteFromSheet(Proposition prop, BuildContext sheetContext) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deletePropositionQuestion),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.areYouSureDeleteProposition),
            const SizedBox(height: 12),
            PropositionContentCard(
              content: prop.displayContent,
              maxHeight: 100,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.cannotBeUndone,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog
              _deleteProposition(prop.id);
              // Don't close sheet - it will update reactively
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteChat() async {
    final l10n = AppLocalizations.of(context);
    final chatName = ref.read(chatDetailProvider(_params)).valueOrNull?.chat?.displayName ?? widget.chat.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteChatQuestion),
        content: Text(l10n.deleteChatConfirmation(chatName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        _hasNavigatedAway = true; // Prevent double-pop from realtime event
        await ref.read(chatDetailProvider(_params).notifier).deleteChat();
        if (mounted) {
          Navigator.pop(context); // Go back to home
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.chatDeleted)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.failedToDeleteChat(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _confirmLeaveChat() async {
    final l10n = AppLocalizations.of(context);
    final chatName = ref.read(chatDetailProvider(_params)).valueOrNull?.chat?.displayName ?? widget.chat.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.leaveChatQuestion),
        content: Text(l10n.leaveChatConfirmation(chatName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.leave),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        _hasNavigatedAway = true;
        await ref.read(chatDetailProvider(_params).notifier).leaveChat();
        if (mounted) {
          // Also remove from MyChats list
          ref.read(myChatsProvider.notifier).removeChat(widget.chat.id);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.youHaveLeftChat)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.failedToLeaveChat(e.toString()))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(chatDetailProvider(_params));

    // Auto-switch to Previous Winner tab when new winners arrive
    final currentWinners = stateAsync.valueOrNull?.previousRoundWinners ?? [];
    if (currentWinners.isNotEmpty) {
      final currentRoundId = currentWinners.first.roundId;
      if (_lastPreviousWinnerRoundId != currentRoundId) {
        _lastPreviousWinnerRoundId = currentRoundId;
        // Use post-frame callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showPreviousWinner) {
            setState(() => _showPreviousWinner = true);
          }
        });
      }
    }

    // Previously pre-filled text field with previous winner — removed per user request.
    // Users should always start with an empty text field in proposing phase.

    // Record the phase when user first opens this screen, so we only
    // auto-navigate to rating if the phase *transitions* while they're here.
    // If they arrive when rating is already in progress, let them see the
    // conversation first.
    final state = stateAsync.valueOrNull;
    final currentRound = state?.currentRound;
    if (!_initialPhaseRecorded && currentRound != null) {
      _initialPhaseRecorded = true;
      _phaseOnOpen = currentRound.phase;
      // If already in rating when opened, mark this round as "already seen"
      // so we don't auto-navigate for it
      if (currentRound.phase == RoundPhase.rating) {
        _lastAutoNavigatedRoundId = currentRound.id;
      }
    }

    // Auto-navigate to rating screen only when phase transitions to rating
    // while user is already viewing this chat (once per round)
    if (currentRound != null &&
        currentRound.phase == RoundPhase.rating &&
        state != null &&
        !state.hasRated &&
        !state.hasStartedRating &&
        !state.hasSkippedRating &&
        _lastAutoNavigatedRoundId != currentRound.id) {
      _lastAutoNavigatedRoundId = currentRound.id;
      // Use post-frame callback to avoid navigation during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openRatingScreen(state);
        }
      });
    }

    // Show language picker dialog if user's language isn't in this chat's languages
    if (state?.needsLanguageSelection == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showLanguagePickerDialog(state!);
      });
    }

    // Check if chat was deleted and navigate back (only if we haven't already navigated)
    final isDeleted = stateAsync.valueOrNull?.isDeleted ?? false;
    if (isDeleted && !_hasNavigatedAway) {
      _hasNavigatedAway = true; // Prevent multiple pops
      // Use post-frame callback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.chatHasBeenDeleted)),
          );
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Check if user was kicked and navigate back
    final myParticipant = stateAsync.valueOrNull?.myParticipant;
    if (myParticipant?.status == ParticipantStatus.kicked && !_hasNavigatedAway) {
      _hasNavigatedAway = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ref.read(myChatsProvider.notifier).removeChat(widget.chat.id);
          // Show snackbar BEFORE navigating away so context is valid
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.youHaveBeenRemoved)),
          );
          // Pop all dialogs and this screen - handles case when dialog is open
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Text(
          stateAsync.valueOrNull?.chat?.displayName ?? widget.chat.displayName,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: stateAsync.whenOrNull(
              data: (state) {
                final isHost = state.myParticipant?.isHost == true;
                final isHostPaused = state.chat?.hostPaused ?? widget.chat.hostPaused;
                final pendingRequestCount = state.pendingJoinRequests.length;
                final chat = state.chat ?? widget.chat;
                final hasInviteCode = widget.chat.inviteCode != null &&
                    widget.chat.accessMethod == AccessMethod.code;
                final hasDescription =
                    (chat.displayDescription)?.trim().isNotEmpty == true;

                return <Widget>[
                  // Chat language selector — hidden when translations aren't enabled
                  ChatLanguageSelector(
                    availableLanguages: chat.translationsEnabled
                        ? chat.translationLanguages
                        : const [],
                    currentLanguageCode: state.viewingLanguageCode ?? ref.read(localeProvider).languageCode,
                    onLanguageChanged: (code) =>
                        ref.read(chatDetailProvider(_params).notifier).setViewingLanguage(code),
                  ),
                  // Share button — visible when chat has invite code
                  if (hasInviteCode)
                    IconButton(
                      key: const Key('share-button'),
                      icon: const Icon(Icons.ios_share),
                      tooltip: 'Share Chat',
                      onPressed: _showQrCode,
                    ),
                  // Info button — only if chat has description
                  if (hasDescription)
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      tooltip: AppLocalizations.of(context).chatDescription,
                      onPressed: () => _showDescription(state),
                    ),
                  // People button — always visible, badge for host with pending requests
                  IconButton(
                    icon: Badge(
                      label: Text('$pendingRequestCount'),
                      isLabelVisible: isHost && widget.chat.requireApproval && pendingRequestCount > 0,
                      child: const Icon(Icons.people),
                    ),
                    tooltip: AppLocalizations.of(context).participants,
                    onPressed: () => _showParticipantsSheet(state),
                  ),
                  // Non-host: Leave button (not for official chats)
                  if (!isHost && !widget.chat.isOfficial)
                    IconButton(
                      icon: const Icon(Icons.exit_to_app),
                      tooltip: AppLocalizations.of(context).leaveChat,
                      onPressed: _confirmLeaveChat,
                    ),
                  // Host: overflow menu with Delete (Pause/Resume hidden for now)
                  if (isHost)
                    PopupMenuButton<String>(
                      key: const Key('chat-more-menu'),
                      onSelected: (value) {
                        switch (value) {
                          case 'pause':
                            _showPauseConfirmation();
                            break;
                          case 'resume':
                            ref.read(chatDetailProvider(_params).notifier).resumeChat();
                            break;
                          case 'delete':
                            _confirmDeleteChat();
                            break;
                        }
                      },
                      itemBuilder: (menuContext) {
                        final l10n = AppLocalizations.of(menuContext);
                        return [
                          PopupMenuItem(
                            value: isHostPaused ? 'resume' : 'pause',
                            child: Row(
                              children: [
                                Icon(isHostPaused ? Icons.play_arrow : Icons.pause),
                                const SizedBox(width: 12),
                                Text(isHostPaused ? l10n.resumeChat : l10n.pauseChat),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(Icons.delete, color: Colors.red),
                                const SizedBox(width: 12),
                                Text(l10n.deleteChat,
                                    style: const TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                ];
              },
            ) ??
            const [],
      ),
      body: stateAsync.when(
        data: (state) => AnimatedOpacity(
          opacity: state.isTranslating ? 0.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Column(
          children: [
            // Phase-aware accent strip
            _PhaseAccentStrip(phase: state.currentRound?.phase),
            // Host paused banner
            if (state.chat?.hostPaused ?? widget.chat.hostPaused)
              HostPausedBanner(
                isHost: state.myParticipant?.isHost == true,
              ),
            // Chat History
            Expanded(
              child: Builder(
                builder: (bodyContext) {
                  final l10n = AppLocalizations.of(bodyContext);
                  final initialMessage = state.chat?.displayInitialMessage ?? widget.chat.displayInitialMessage;
                  final hasInitialMessage = initialMessage.trim().isNotEmpty;

                  final isHost = state.myParticipant?.isHost == true;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Always show initial message as the opening prompt
                      if (hasInitialMessage) ...[
                        _buildInitialMessageCard(l10n, initialMessage, isHost),
                        const SizedBox(height: 16),
                      ],

                      // Consensus Items
                      ...state.consensusItems.asMap().entries.expand((entry) {
                        final item = entry.value;
                        final isLastItem = entry.key == state.consensusItems.length - 1;
                        final label = item.isHostOverride
                            ? (state.chat?.hostDisplayName ?? 'Host')
                            : l10n.consensusNumber(entry.key + 1);
                        final card = _buildMessageCard(
                          label,
                          item.displayContent,
                          isPrimary: true,
                          isConsensus: !item.isHostOverride,
                        );

                        final List<Widget> widgets = [];

                        if (!isHost || !isLastItem) {
                          widgets.add(Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: card,
                            ),
                          ));
                        } else {
                          widgets.add(Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Dismissible(
                                key: ValueKey('consensus_${item.cycleId}'),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) => _confirmAndDeleteConsensus(l10n, entry.key + 1, item.cycleId),
                                onDismissed: (_) => _onConsensusDismissed(item.cycleId),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                child: card,
                              ),
                            ),
                          ));
                        }

                        // Task result card (collapsible)
                        if (item.taskResult != null) {
                          final taskResultCard = _buildTaskResultCard(item.taskResult!);
                          if (isHost && isLastItem) {
                            widgets.add(Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Dismissible(
                                key: ValueKey('task_result_${item.cycleId}'),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) => _confirmAndDeleteTaskResult(l10n, item.cycleId),
                                onDismissed: (_) => _onTaskResultDismissed(item.cycleId),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                child: taskResultCard,
                              ),
                            ));
                          } else {
                            widgets.add(Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: taskResultCard,
                            ));
                          }
                        } else {
                          // Add extra spacing when no task result
                          widgets.add(const SizedBox(height: 8));
                        }

                        return widgets;
                      }),
                    ],
                  );
                },
              ),
            ),

            // Bottom Action Area
            _buildBottomArea(state),
          ],
        )),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView.fromError(
          error,
          onRetry: () {
            ref.read(chatDetailProvider(_params).notifier).refresh();
          },
        ),
      ),
    );
  }

  Widget _buildMessageCard(String label, String content,
      {bool isPrimary = false, bool isConsensus = false}) {
    final Color borderColor;
    final Color backgroundColor;
    if (isConsensus) {
      borderColor = AppColors.consensus;
      backgroundColor = AppColors.consensusLight.withValues(alpha: 0.5);
    } else if (isPrimary) {
      borderColor = Theme.of(context).colorScheme.primary;
      backgroundColor = Theme.of(context).colorScheme.primaryContainer.withAlpha(128);
    } else {
      borderColor = Colors.transparent;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: (isPrimary || isConsensus)
            ? Border(
                left: BorderSide(
                  color: borderColor,
                  width: 4,
                ),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isConsensus
                      ? const Color(0xFF92400E) // amber-800
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: isConsensus ? FontWeight.w600 : null,
                ),
          ),
          const SizedBox(height: 4),
          Text(content),
        ],
      ),
    );
  }

  Widget _buildTaskResultCard(String taskResult) {
    return ExpansionTile(
      leading: Icon(
        Icons.search,
        size: 18,
        color: Theme.of(context).colorScheme.secondary,
      ),
      title: Text(
        'Research Results',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
            ),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.secondary.withAlpha(64),
        ),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.secondary.withAlpha(64),
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withAlpha(64),
      collapsedBackgroundColor: Theme.of(context).colorScheme.secondaryContainer.withAlpha(64),
      children: [
        Text(
          taskResult,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildInitialMessageCard(AppLocalizations l10n, String initialMessage, bool isHost) {
    final card = _buildMessageCard(
      l10n.initialMessage,
      initialMessage,
      isPrimary: true,
    );

    if (!isHost) return Center(child: card);

    return Center(
      child: Dismissible(
        key: const ValueKey('initial_message'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDeleteInitialMessage(l10n),
        onDismissed: (_) => _handleDeleteInitialMessage(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: GestureDetector(
          onLongPress: () => _showEditInitialMessageDialog(l10n, initialMessage),
          child: card,
        ),
      ),
    );
  }

  /// Confirm and delete consensus in one step (for Dismissible.confirmDismiss).
  /// Returns true only if both user confirms AND server delete succeeds,
  /// so the Dismissible only animates out on actual success.
  Future<bool> _confirmAndDeleteConsensus(AppLocalizations l10n, int number, int cycleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConsensusTitle(number)),
        content: Text(l10n.deleteConsensusMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    try {
      await ref.read(chatDetailProvider(_params).notifier).deleteConsensusOnServer(cycleId);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToDeleteConsensus(e.toString()))),
        );
      }
      return false;
    }
  }

  void _onConsensusDismissed(int cycleId) {
    ref.read(chatDetailProvider(_params).notifier).onConsensusDismissed(cycleId);
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.consensusDeleted)),
      );
    }
  }

  /// Confirm and delete task result in one step (for Dismissible.confirmDismiss).
  Future<bool> _confirmAndDeleteTaskResult(AppLocalizations l10n, int cycleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteTaskResultTitle),
        content: Text(l10n.deleteTaskResultMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    try {
      await ref.read(chatDetailProvider(_params).notifier).deleteTaskResultOnServer(cycleId);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToDeleteTaskResult(e.toString()))),
        );
      }
      return false;
    }
  }

  void _onTaskResultDismissed(int cycleId) {
    ref.read(chatDetailProvider(_params).notifier).onTaskResultDismissed(cycleId);
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.taskResultDeleted)),
      );
    }
  }

  /// Submit task result directly as consensus (no confirmation dialog).
  /// Used when isTaskResultMode is true.
  Future<void> _handleTaskResultSubmit() async {
    final content = _propositionController.text.trim();
    if (content.isEmpty) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(chatDetailProvider(_params).notifier).forceConsensus(content);
      _propositionController.clear();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.taskResultSubmitted)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToForceConsensus(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _confirmDeleteInitialMessage(AppLocalizations l10n) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteInitialMessageTitle),
        content: Text(l10n.deleteInitialMessageMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _handleDeleteInitialMessage() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(chatDetailProvider(_params).notifier).deleteInitialMessage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.initialMessageDeleted)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToDeleteInitialMessage(e.toString()))),
        );
      }
    }
  }

  void _showEditInitialMessageDialog(AppLocalizations l10n, String currentMessage) {
    final controller = TextEditingController(text: currentMessage);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editInitialMessage),
        content: TextField(
          controller: controller,
          maxLines: 5,
          minLines: 2,
          decoration: InputDecoration(
            hintText: l10n.initialMessageHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final newText = controller.text.trim();
              Navigator.pop(dialogContext);
              if (newText.isNotEmpty && newText != currentMessage) {
                _handleUpdateInitialMessage(newText);
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _handleUpdateInitialMessage(String newMessage) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(chatDetailProvider(_params).notifier).updateInitialMessage(newMessage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.initialMessageUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToUpdateInitialMessage(e.toString()))),
        );
      }
    }
  }

  Widget _buildBottomArea(ChatDetailState state) {
    final hasPreviousWinner = state.previousRoundWinners.isNotEmpty;
    final isRatingPhase = state.currentRound?.phase == RoundPhase.rating;

    // Hide the Previous Winner tab when in rating phase
    final showPreviousWinnerTab = hasPreviousWinner && !isRatingPhase;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar - shows both tabs when previous winner exists and not in rating phase
          _buildToggleTabs(state, showPreviousWinnerTab),
          // Content based on toggle
          _showPreviousWinner && showPreviousWinnerTab
              ? _buildPreviousWinnerPanel(state)
              : _buildCurrentPhasePanel(state),
        ],
      ),
    );
  }

  Widget _buildToggleTabs(ChatDetailState state, bool hasPreviousWinner) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isFirstSelected = _showPreviousWinner && hasPreviousWinner;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // Previous Winner Tab - only show when there's a previous winner
          if (hasPreviousWinner)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showPreviousWinner = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isFirstSelected
                        ? theme.colorScheme.surface
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.previousWinner,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: isFirstSelected ? FontWeight.bold : FontWeight.normal,
                      color: isFirstSelected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          // Current Phase Tab
          Expanded(
            child: GestureDetector(
              onTap: hasPreviousWinner ? () => setState(() => _showPreviousWinner = false) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: !isFirstSelected
                      ? theme.colorScheme.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(hasPreviousWinner ? 0 : 12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  _getPhaseTabLabel(state),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: !isFirstSelected ? FontWeight.bold : FontWeight.normal,
                    color: !isFirstSelected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPhaseTabLabel(ChatDetailState state) {
    final l10n = AppLocalizations.of(context);
    if (state.currentRound == null) return l10n.waiting;
    switch (state.currentRound!.phase) {
      case RoundPhase.waiting:
        return l10n.waiting;
      case RoundPhase.proposing:
        if (state.myPropositions.isEmpty) return l10n.yourProposition;
        final remaining =
            widget.chat.propositionsPerUser - state.myPropositions.length;
        return remaining > 0
            ? '${l10n.yourPropositions} (${state.myPropositions.length}/${widget.chat.propositionsPerUser})'
            : l10n.yourPropositions;
      case RoundPhase.rating:
        return state.hasRated ? l10n.done : l10n.rate;
    }
  }

  Widget _buildPreviousWinnerPanel(ChatDetailState state) {
    // Clamp index to valid range (handles case where winners count decreased)
    final clampedIndex = state.previousRoundWinners.isEmpty
        ? 0
        : _currentWinnerIndex.clamp(0, state.previousRoundWinners.length - 1);

    // Always use PreviousWinnerPanel. When showPreviousResults is enabled,
    // show the "See All Results" button that opens the grid view.
    return PreviousWinnerPanel(
      previousRoundWinners: state.previousRoundWinners,
      currentWinnerIndex: clampedIndex,
      isSoleWinner: state.isSoleWinner,
      consecutiveSoleWins: state.consecutiveSoleWins,
      confirmationRoundsRequired: widget.chat.confirmationRoundsRequired,
      currentRoundCustomId: state.currentRound?.customId,
      onWinnerIndexChanged: (index) =>
          setState(() => _currentWinnerIndex = index),
      showResultsButton: widget.chat.showPreviousResults,
      previousRoundResults: state.previousRoundResults,
      myParticipantId: state.myParticipant?.id,
      previousRoundId: state.previousRoundId,
    );
  }

  Widget _buildCurrentPhasePanel(ChatDetailState state) {
    // Use fresh chat from state for dynamic fields (schedulePaused), fall back to widget.chat
    final chat = state.chat ?? widget.chat;
    final isHost = state.myParticipant?.isHost == true;

    // FIRST: Check if chat has schedule and is paused (takes priority over round state)
    if (chat.hasSchedule) {
      // One-time schedule: check if scheduled time is in the future
      if (chat.scheduleType == ScheduleType.once &&
          chat.scheduledStartAt != null &&
          DateTime.now().isBefore(chat.scheduledStartAt!)) {
        return ScheduledWaitingPanel(
          isHost: isHost,
          scheduledStartAt: chat.scheduledStartAt,
          scheduleTimezone: chat.scheduleTimezone,
        );
      }

      // Recurring schedule: check if outside schedule window (paused)
      // This takes priority even if a round exists in waiting phase
      if (chat.scheduleType == ScheduleType.recurring && chat.schedulePaused) {
        return ScheduledWaitingPanel(
          isHost: isHost,
          isRecurring: true,
          nextWindowStart: chat.getNextWindowStart(),
          scheduleWindows: chat.scheduleWindows,
          scheduleTimezone: chat.scheduleTimezone,
        );
      }
    }

    // Credit-paused = credits exist but can't afford participant count
    final isCreditPaused = state.chatCredits != null &&
        !state.chatCredits!.canAfford(state.activeParticipantCount);

    final hasShareButton = isHost &&
        widget.chat.inviteCode != null &&
        widget.chat.accessMethod == AccessMethod.code;

    if (state.currentRound == null) {
      if (isCreditPaused) {
        return CreditPausedPanel(
          isHost: isHost,
          creditBalance: state.chatCredits!.creditBalance,
          activeParticipantCount: state.activeParticipantCount,
          onBuyCredits: isHost ? () => _openBuyCredits(state.chatCredits!.chatId) : null,
        );
      }
      return WaitingStatePanel(
        participantCount: state.participants.length,
        autoStartParticipantCount: widget.chat.autoStartParticipantCount ?? 3,
        showShareHint: hasShareButton,
      );
    }

    switch (state.currentRound!.phase) {
      case RoundPhase.waiting:
        // Check if we're waiting for rating (NEW propositions exist) vs waiting for proposing
        // Exclude carried forward propositions - those are from the previous round's winner
        // and don't count as "new" submissions for this round
        final hasNewPropositions =
            state.propositions.any((p) => !p.isCarriedForward);
        if (hasNewPropositions) {
          return WaitingForRatingPanel(
            roundCustomId: state.currentRound!.customId,
            isHost: isHost,
            propositionCount: state.propositions.length,
            onStartRating: _advanceToRating,
          );
        }
        if (isCreditPaused) {
          return CreditPausedPanel(
            isHost: isHost,
            creditBalance: state.chatCredits!.creditBalance,
            activeParticipantCount: state.activeParticipantCount,
            onBuyCredits: isHost ? () => _openBuyCredits(state.chatCredits!.chatId) : null,
          );
        }
        return WaitingStatePanel(
          participantCount: state.participants.length,
          autoStartParticipantCount: widget.chat.autoStartParticipantCount ?? 3,
          showShareHint: hasShareButton,
        );
      case RoundPhase.proposing:
        final isTaskResultMode = state.isTaskResultMode;
        return ProposingStatePanel(
          roundCustomId: state.currentRound!.customId,
          propositionsPerUser: widget.chat.propositionsPerUser,
          myPropositions: state.myPropositions,
          allPropositionsCount: isHost ? state.propositions.length : 0,
          propositionController: _propositionController,
          onSubmit: isTaskResultMode
              ? _handleTaskResultSubmit
              : _submitProposition,
          phaseEndsAt: state.currentRound!.phaseEndsAt,
          onPhaseExpired: _onPhaseExpired,
          isHost: isHost,
          onAdvancePhase: () => _advanceToRating(),
          onViewAllPropositions: isHost ? () => _showAllPropositionsSheet(state) : null,
          isPaused: chat.isPaused,
          isSubmitting: _isSubmitting || _isSkipping,
          // Skip feature
          onSkip: state.canSkip ? _skipProposing : null,
          canSkip: state.canSkip,
          skipCount: state.skipCount,
          maxSkips: state.maxSkips,
          hasSkipped: state.hasSkipped,
          isFunded: state.isMyParticipantFunded,
          isTaskResultMode: isTaskResultMode,
        );
      case RoundPhase.rating:
        return RatingStatePanel(
          roundCustomId: state.currentRound!.customId,
          hasRated: state.hasRated,
          hasStartedRating: state.hasStartedRating,
          propositionCount: state.propositions.length,
          onStartRating: () => _openRatingScreen(state),
          phaseEndsAt: state.currentRound!.phaseEndsAt,
          onPhaseExpired: _onPhaseExpired,
          isHost: isHost,
          onAdvancePhase: isHost ? () => _advanceFromRating() : null,
          isPaused: chat.isPaused,
          // Skip rating feature
          onSkipRating: state.canSkipRating ? _skipRating : null,
          canSkipRating: state.canSkipRating,
          ratingSkipCount: state.ratingSkipCount,
          maxRatingSkips: state.maxRatingSkips,
          hasSkippedRating: state.hasSkippedRating,
          isSkipping: _isSkipping,
          isFunded: state.isMyParticipantFunded,
        );
    }
  }

  Future<void> _openBuyCredits(int chatId) async {
    final l10n = AppLocalizations.of(context);

    // Show amount picker dialog
    final credits = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        int selectedCredits = 100; // Default $1
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dollars = (selectedCredits / 100).toStringAsFixed(2);
            return AlertDialog(
              title: Text(l10n.buyCredits),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: '1 credit = 1 '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GlossaryTerm(
                        term: l10n.glossaryUserRoundTitle,
                        definition: l10n.glossaryUserRoundDef,
                      ),
                    ),
                    const TextSpan(text: ' = \$0.01'),
                  ])),
                  const SizedBox(height: 16),
                  // Preset amounts
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final amount in [100, 500, 1000, 5000])
                        ChoiceChip(
                          label: Text('\$${(amount / 100).toStringAsFixed(2)}'),
                          selected: selectedCredits == amount,
                          onSelected: (_) => setDialogState(() => selectedCredits = amount),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$selectedCredits credits = \$$dollars',
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, selectedCredits),
                  child: Text(l10n.purchaseWithStripe),
                ),
              ],
            );
          },
        );
      },
    );

    if (credits == null) return;

    try {
      final billingService = ref.read(billingServiceProvider);
      final url = await billingService.createCheckoutSession(credits, chatId: chatId);
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Language picker dialog shown when user enters a chat that doesn't support their app language.
  void _showLanguagePickerDialog(ChatDetailState state) {
    final chat = state.chat ?? widget.chat;
    final languages = chat.translationLanguages;
    if (languages.isEmpty) return;

    const languageNames = {
      'en': 'English',
      'es': 'Español',
      'pt': 'Português',
      'fr': 'Français',
      'de': 'Deutsch',
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        String? selected;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final l10n = AppLocalizations.of(context);
            return AlertDialog(
              title: Text(l10n.language),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: languages.map((code) {
                  final isSelected = selected == code;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(languageNames[code] ?? code),
                    onTap: () => setDialogState(() => selected = code),
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: selected == null
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          ref
                              .read(chatDetailProvider(_params).notifier)
                              .setViewingLanguage(selected!);
                        },
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Merged participants + join requests bottom sheet.
  void _showParticipantsSheet(ChatDetailState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (sheetContext, scrollController) => Consumer(
          builder: (consumerContext, consumerRef, _) {
            final l10n = AppLocalizations.of(consumerContext);
            final theme = Theme.of(consumerContext);
            final stateAsync = consumerRef.watch(chatDetailProvider(_params));
            final participants = stateAsync.valueOrNull?.participants ?? [];
            final isHost = stateAsync.valueOrNull?.myParticipant?.isHost == true;
            final requests = stateAsync.valueOrNull?.pendingJoinRequests ?? [];
            final showRequests = isHost && widget.chat.requireApproval && requests.isNotEmpty;

            return Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        '${l10n.participants} (${participants.length})',
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Join requests section (host only)
                if (showRequests) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.group_add, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${l10n.joinRequests} (${requests.length})',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...requests.map((req) => _buildRequestCard(req)),
                  const Divider(height: 1),
                ],
                // Participants list
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: participants.length,
                    itemBuilder: (context, index) {
                      final p = participants[index];
                      return ListTile(
                        leading: CircleAvatar(child: Text(p.displayName[0])),
                        title: Text(p.displayName),
                        trailing: p.isHost
                            ? Chip(label: Text(l10n.host))
                            : isHost
                                ? IconButton(
                                    icon: const Icon(Icons.person_remove),
                                    tooltip: l10n.kickParticipant,
                                    onPressed: () {
                                      Navigator.pop(modalContext);
                                      _confirmKickParticipant(p);
                                    },
                                  )
                                : null,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showQrCode() {
    if (widget.chat.inviteCode == null) return;
    final chatName = ref.read(chatDetailProvider(_params)).valueOrNull?.chat?.displayName ?? widget.chat.displayName;

    QrCodeShareDialog.show(
      context,
      chatName: chatName,
      inviteCode: widget.chat.inviteCode!,
    );
  }

  void _showDescription(ChatDetailState? state) {
    final description = state?.chat?.displayDescription ?? widget.chat.displayDescription ?? '';
    showModalBottomSheet(
      context: context,
      builder: (modalContext) {
        final l10n = AppLocalizations.of(modalContext);
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.chatDescription,
                style: Theme.of(modalContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                description,
                style: Theme.of(modalContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }


  Future<void> _confirmKickParticipant(Participant participant) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.kickParticipantQuestion),
        content: Text(l10n.kickParticipantConfirmation(participant.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.kick),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref
            .read(chatDetailProvider(_params).notifier)
            .kickParticipant(participant.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.participantRemoved(participant.displayName))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.failedToKickParticipant(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _showPauseConfirmation() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.pauseChatQuestion),
        content: Text(l10n.pauseChatConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.pause),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(chatDetailProvider(_params).notifier).pauseChat();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.chatPausedSuccess)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.failedToPauseChat(e.toString()))),
          );
        }
      }
    }
  }


  Widget _buildRequestCard(Map<String, dynamic> req) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(req['display_name'][0].toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req['display_name'],
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  req['is_authenticated'] == true ? l10n.signedIn : l10n.guest,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary),
            onPressed: () => _handleApprove(req['id']),
            tooltip: l10n.approve,
          ),
          IconButton(
            icon:
                Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
            onPressed: () => _handleDeny(req['id']),
            tooltip: l10n.deny,
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(int requestId) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(chatDetailProvider(_params).notifier)
          .approveJoinRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.requestApproved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error(e.toString()))),
        );
      }
    }
  }

  Future<void> _handleDeny(int requestId) async {
    final l10n = AppLocalizations.of(context);
    await ref
        .read(chatDetailProvider(_params).notifier)
        .denyJoinRequest(requestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.requestDenied)),
      );
    }
  }
}

/// Subtle colored strip at the top of the chat body showing current phase.
class _PhaseAccentStrip extends StatelessWidget {
  final RoundPhase? phase;

  const _PhaseAccentStrip({this.phase});

  @override
  Widget build(BuildContext context) {
    if (phase == null) return const SizedBox.shrink();

    final Color color;
    switch (phase!) {
      case RoundPhase.proposing:
        color = AppColors.proposing;
      case RoundPhase.rating:
        color = AppColors.rating;
      case RoundPhase.waiting:
        color = AppColors.waiting;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 3,
      color: color.withValues(alpha: 0.6),
    );
  }
}

/// Compact credit balance chip displayed in the AppBar for hosts.
class _CreditBalanceChip extends StatelessWidget {
  final int balance;
  final int participantCount;
  final VoidCallback? onTap;

  const _CreditBalanceChip({
    required this.balance,
    required this.participantCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color chipColor;
    final Color iconColor;
    if (balance == 0) {
      chipColor = theme.colorScheme.errorContainer;
      iconColor = theme.colorScheme.error;
    } else if (balance < participantCount) {
      chipColor = Colors.amber.shade100;
      iconColor = Colors.amber.shade800;
    } else {
      chipColor = theme.colorScheme.surfaceContainerHighest;
      iconColor = theme.colorScheme.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        key: const Key('credit-balance-chip'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.toll,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 4),
              Text(
                '$balance',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: iconColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
