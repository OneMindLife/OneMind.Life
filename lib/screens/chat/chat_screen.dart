import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../../services/background_audio_service.dart';
import '../../services/affirmation_service.dart';
import '../../services/proposition_service.dart';
import '../../services/remote_log_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tts_button.dart';
import '../../core/l10n/locale_provider.dart';
import '../../widgets/glossary_term.dart';
import '../../widgets/proposition_content_card.dart';
import '../../widgets/round_phase_bar.dart';
import '../../widgets/message_card.dart';
import '../../widgets/qr_code_share.dart';
import '../rating/rating_screen.dart';
import 'cycle_history_screen.dart';
import 'other_propositions_screen.dart';
import 'widgets/convergence_video_card.dart';
import 'widgets/personal_code_sheet.dart';
import 'widgets/previous_round_display.dart';
import 'widgets/phase_panels.dart';

const _languageDisplayNames = {
  'en': 'English',
  'es': 'Español',
  'pt': 'Português',
  'fr': 'Français',
  'de': 'Deutsch',
};

class ChatScreen extends ConsumerStatefulWidget {
  final Chat chat;
  final bool showShareDialog;

  const ChatScreen({super.key, required this.chat, this.showShareDialog = false});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _propositionController = TextEditingController();

  // UI toggle states (not data - stay in widget)
  int _currentWinnerIndex = 0;
  int? _lastAutoNavigatedRoundId; // Track to auto-navigate to rating screen once per round
  bool _isChatScreenTopmost = true; // Only auto-open rating if chat screen is visible
  bool _initialPhaseRecorded = false; // Whether we've recorded the phase on first load
  RoundPhase? _phaseOnOpen; // The phase when user first opened this screen

  // Affirm/Alternative gate state. R2+ rounds with a previous winner start in
  // gate mode (false). Tapping Alternative flips this to true and reveals the
  // textfield. Tapping the left chevron from the textfield returns to
  // gate mode (typed text is preserved). Reset to false on round change.
  bool _alternativeMode = false;
  // Optimistic flag: the user just tapped Affirm. Disables the Affirm
  // button immediately so it can't double-fire while the RPC + refresh
  // round-trip. Reset on round change. Server is the source of truth —
  // if the optimistic update was wrong (RPC errored), this flips back.
  bool _hasAffirmedThisRound = false;
  int? _lastSeenProposingRoundId;

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

  // Captured in initState so dispose() can call leaveChat() without touching
  // `ref` — Riverpod disposes the ConsumerState's ref BEFORE dispose() runs,
  // so ref.read from dispose() throws "Cannot use ref after the widget was disposed".
  BackgroundAudioService? _bgAudioForDispose;

  @override
  void initState() {
    super.initState();
    _setupScheduledTimeTimer();
    _setupLifecycleListener();
    final bgUrl = widget.chat.backgroundAudioUrl;
    if (bgUrl != null && bgUrl.isNotEmpty) {
      final service = ref.read(backgroundAudioServiceProvider);
      _bgAudioForDispose = service;
      service.enterChat(bgUrl);
    }
    if (widget.showShareDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.chat.accessMethod == AccessMethod.personalCode) {
          // For personal_code chats, show the code management sheet
          final state = ref.read(chatDetailProvider(_params)).valueOrNull;
          if (state != null) _showPersonalCodeSheet(state);
        } else if (widget.chat.inviteCode != null) {
          _showQrCode();
        }
      });
    }
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
    _bgAudioForDispose?.leaveChat();
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
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stack) {
      final state = ref.read(chatDetailProvider(_params)).valueOrNull;
      RemoteLog.log(
        'proposition_submit_error',
        e.toString(),
        {
          'error_type': e.runtimeType.toString(),
          'chat_id': widget.chat.id,
          'chat_name': widget.chat.displayName,
          'round_id': state?.currentRound?.id,
          'round_number': state?.currentRound?.customId,
          'participant_id': state?.myParticipant?.id,
          'content_length': content.length,
          'stack': stack.toString().split('\n').take(12).join('\n'),
        },
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        context.showErrorMessage(l10n.failedToSubmit(e.toString()));
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
        context.showErrorMessage(l10n.failedToSubmit(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isSkipping = false);
    }
  }

  /// Submits an affirmation of the carried-forward winner via the
  /// `affirm_round` RPC. The button is gated by the same conditions as
  /// the gate render itself (R2+ proposing, allow_skip_proposing, no
  /// submission, no prior skip, not already affirmed in this round).
  /// Optimistic: locally flag affirmed so the gate disappears
  /// immediately; server-side trigger may auto-resolve the round if all
  /// active participants have acted.
  Future<void> _affirmRound() async {
    if (_isSkipping) return;
    final state = ref.read(chatDetailProvider(_params)).valueOrNull;
    final roundId = state?.currentRound?.id;
    if (roundId == null) return;
    setState(() {
      _isSkipping = true;
      _hasAffirmedThisRound = true;
    });
    try {
      await ref.read(affirmationServiceProvider).affirm(roundId);
      // No explicit refresh — the optimistic flag flips the gate locally,
      // and existing realtime subscriptions on rounds/round_winners pick
      // up any auto-resolve consequences. Refreshing the whole chat
      // state here causes a full rebuild that visually feels like a
      // page reload.
    } on AffirmationException catch (e) {
      if (e.reason == AffirmationFailure.alreadyAffirmed) {
        // Server already had this affirmation — local state is already
        // in sync, just keep _hasAffirmedThisRound true.
      } else {
        if (mounted) {
          setState(() => _hasAffirmedThisRound = false);
          final l10n = AppLocalizations.of(context);
          context.showErrorMessage(l10n.failedToSubmit(e.message));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasAffirmedThisRound = false);
        final l10n = AppLocalizations.of(context);
        context.showErrorMessage(l10n.failedToSubmit(e.toString()));
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
        context.showErrorMessage(l10n.failedToSubmit(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isSkipping = false);
    }
  }

  /// Push a screen and track that the chat screen is no longer topmost.
  /// This prevents auto-navigation to rating while viewing sub-screens.
  Future<T?> _pushScreen<T>(Route<T> route) {
    _isChatScreenTopmost = false;
    return Navigator.push<T>(context, route).then((result) {
      _isChatScreenTopmost = true;
      return result;
    });
  }

  void _openRatingScreen(ChatDetailState state) {
    if (state.currentRound == null || state.myParticipant == null) return;

    _pushScreen<bool>(
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
        context.showErrorMessage(l10n.failedToAdvancePhase(e.toString()));
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
        context.showErrorMessage(l10n.failedToCompleteRating(e.toString()));
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
    } catch (e) {
      if (mounted) {
        context.showErrorMessage(l10n.failedToDelete(e.toString()));
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
        }
      } catch (e) {
        if (mounted) {
          context.showErrorMessage(l10n.failedToDeleteChat(e.toString()));
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
          context.showInfoSnackBar(l10n.youHaveLeftChat);
        }
      } catch (e) {
        if (mounted) {
          context.showErrorMessage(l10n.failedToLeaveChat(e.toString()));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(chatDetailProvider(_params));


    // Previously pre-filled text field with emerging idea — removed per user request.
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

    // Reset Affirm/Alternative gate state when the proposing round changes.
    // Each new round starts back at the gate with an empty text field.
    if (currentRound != null &&
        currentRound.phase == RoundPhase.proposing &&
        _lastSeenProposingRoundId != currentRound.id) {
      _lastSeenProposingRoundId = currentRound.id;
      if (_alternativeMode ||
          _hasAffirmedThisRound ||
          _propositionController.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _alternativeMode = false;
            _hasAffirmedThisRound = false;
          });
          _propositionController.clear();
        });
      }
    }

    // Auto-navigate to rating screen only when phase transitions to rating
    // while user is viewing the chat screen (not cycle history, results, etc.)
    if (currentRound != null &&
        currentRound.phase == RoundPhase.rating &&
        state != null &&
        !state.hasRated &&
        !state.hasStartedRating &&
        !state.hasSkippedRating &&
        _isChatScreenTopmost &&
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
          context.showInfoSnackBar(l10n.chatHasBeenDeleted);
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
          context.showInfoSnackBar(l10n.youHaveBeenRemoved);
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
                final isPersonalCode = chat.accessMethod == AccessMethod.personalCode;
                final hasInviteCode = widget.chat.inviteCode != null && !isPersonalCode;
                final hasDescription =
                    (chat.displayDescription)?.trim().isNotEmpty == true;

                final availableLanguages = chat.translationsEnabled
                    ? chat.translationLanguages
                    : const <String>[];
                final hasLanguageChoice = availableLanguages.length > 1;
                final currentLanguageCode = state.viewingLanguageCode ??
                    ref.read(localeProvider).languageCode;

                return <Widget>[
                  // Participants button — visible for all chats including
                  // public (host still sees a pending-request badge count).
                  // Framed as "who's here / how aligned are we" rather than
                  // a competitive ranking, to fit the NCDD positioning.
                  IconButton(
                    icon: Badge(
                      label: Text('$pendingRequestCount'),
                      isLabelVisible: isHost && widget.chat.requireApproval && pendingRequestCount > 0,
                      child: const Icon(Icons.groups),
                    ),
                    tooltip: AppLocalizations.of(context).participants,
                    onPressed: () => _showParticipantsSheet(state),
                  ),
                  // Share button — visible when chat has invite code (not for personal_code)
                  if (hasInviteCode)
                    IconButton(
                      key: const Key('share-button'),
                      icon: const Icon(Icons.ios_share),
                      tooltip: 'Share Chat',
                      onPressed: _showQrCode,
                    ),
                  // Generate code button — for hosts of personal_code chats
                  if (isPersonalCode && isHost)
                    IconButton(
                      key: const Key('generate-code-button'),
                      icon: const Icon(Icons.vpn_key),
                      tooltip: AppLocalizations.of(context).personalCodes,
                      onPressed: () => _showPersonalCodeSheet(state),
                    ),
                  // Info button — only if chat has description
                  if (hasDescription)
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      tooltip: AppLocalizations.of(context).chatDescription,
                      onPressed: () => _showDescription(state),
                    ),
                  // Overflow menu — language row (opens picker dialog),
                  // leave (non-host), pause / delete (host).
                  PopupMenuButton<String>(
                    key: const Key('chat-more-menu'),
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      switch (value) {
                        case 'language':
                          _showLanguagePicker(
                            availableLanguages: availableLanguages,
                            currentLanguageCode: currentLanguageCode,
                          );
                          break;
                        case 'music':
                          ref
                              .read(backgroundAudioEnabledProvider.notifier)
                              .toggle();
                          break;
                        case 'leave':
                          _confirmLeaveChat();
                          break;
                        case 'pause':
                          _showPauseConfirmation();
                          break;
                        case 'resume':
                          ref
                              .read(chatDetailProvider(_params).notifier)
                              .resumeChat();
                          break;
                        case 'delete':
                          _confirmDeleteChat();
                          break;
                      }
                    },
                    itemBuilder: (menuContext) {
                      final l10n = AppLocalizations.of(menuContext);
                      final entries = <PopupMenuEntry<String>>[];

                      // Music toggle — only when this chat has background audio.
                      final bgAudioUrl = state.chat?.backgroundAudioUrl ??
                          widget.chat.backgroundAudioUrl;
                      if (bgAudioUrl != null && bgAudioUrl.isNotEmpty) {
                        final musicOn = ref.read(backgroundAudioEnabledProvider);
                        entries.add(PopupMenuItem<String>(
                          key: const Key('chat-menu-music-toggle'),
                          value: 'music',
                          child: Row(
                            children: [
                              Icon(musicOn ? Icons.music_off : Icons.music_note),
                              const SizedBox(width: 12),
                              Text(musicOn ? l10n.turnMusicOff : l10n.turnMusicOn),
                            ],
                          ),
                        ));
                        entries.add(const PopupMenuDivider());
                      }

                      if (hasLanguageChoice) {
                        entries.add(PopupMenuItem<String>(
                          value: 'language',
                          child: Row(
                            children: [
                              const Icon(Icons.translate),
                              const SizedBox(width: 12),
                              Expanded(child: Text(l10n.language)),
                              Text(
                                _languageDisplayNames[currentLanguageCode] ??
                                    currentLanguageCode,
                                style: Theme.of(menuContext)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(menuContext)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                        ));
                        // Always followed by leave (non-host) or pause+delete (host).
                        entries.add(const PopupMenuDivider());
                      }

                      if (!isHost) {
                        entries.add(PopupMenuItem<String>(
                          value: 'leave',
                          child: Row(
                            children: [
                              const Icon(Icons.exit_to_app),
                              const SizedBox(width: 12),
                              Text(l10n.leaveChat),
                            ],
                          ),
                        ));
                      }

                      if (isHost) {
                        entries.add(PopupMenuItem<String>(
                          value: isHostPaused ? 'resume' : 'pause',
                          child: Row(
                            children: [
                              Icon(isHostPaused
                                  ? Icons.play_arrow
                                  : Icons.pause),
                              const SizedBox(width: 12),
                              Text(isHostPaused
                                  ? l10n.resumeChat
                                  : l10n.pauseChat),
                            ],
                          ),
                        ));
                        entries.add(const PopupMenuDivider());
                        entries.add(PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(Icons.delete, color: Colors.red),
                              const SizedBox(width: 12),
                              Text(l10n.deleteChat,
                                  style: const TextStyle(color: Colors.red)),
                            ],
                          ),
                        ));
                      }

                      return entries;
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
            // Round status bar — sits directly under the AppBar with a
            // phase-colored accent strip above and below. The strip's
            // color signals the active phase on both edges of the bar.
            PhaseAccentStrip(phase: state.currentRound?.phase),
            _buildTopPhaseBar(state),
            PhaseAccentStrip(phase: state.currentRound?.phase),
            // Note: HostPausedBanner used to render here; it now replaces the
            // bottom phase panel entirely (see _buildCurrentPhasePanel).
            // Chat History
            Expanded(
              child: Builder(
                builder: (bodyContext) {
                  final l10n = AppLocalizations.of(bodyContext);
                  final initialMessage = state.chat?.displayInitialMessage ?? widget.chat.displayInitialMessage;
                  final hasInitialMessage = initialMessage.trim().isNotEmpty;

                  final isHost = state.myParticipant?.isHost == true;

                  final messageChildren = [
                      // Always show initial message as the opening prompt
                      if (hasInitialMessage) ...[
                        _buildInitialMessageCard(l10n, initialMessage, isHost),
                        const SizedBox(height: 16),
                      ],

                      // Consensus Items
                      ...state.consensusItems.asMap().entries.expand((entry) {
                        final item = entry.value;
                        final isLastItem = entry.key == state.consensusItems.length - 1;
                        final card = GestureDetector(
                          onTap: () => _pushScreen(
                            MaterialPageRoute(
                              builder: (_) => CycleHistoryScreen(
                                cycleId: item.cycleId,
                                convergenceContent: item.displayContent,
                                convergenceNumber: entry.key + 1,
                              ),
                            ),
                          ),
                          child: MessageCard(
                            label: l10n.convergenceNumber(entry.key + 1),
                            content: item.displayContent,
                            isPrimary: true,
                            isConsensus: !item.isHostOverride,
                            mediaAbove: item.videoUrl != null
                                ? ConvergenceVideoCard(
                                    videoUrl: item.videoUrl!,
                                    chatId: widget.chat.id.toString(),
                                    source: 'cycle_winner',
                                    cycleId: item.cycleId,
                                    scrubBarColor: Theme.of(bodyContext).colorScheme.primary,
                                  )
                                : null,
                            trailing: TtsButton(
                              text: item.displayContent,
                              audioUrl: item.audioUrl,
                              chatId: widget.chat.id.toString(),
                              source: 'cycle_winner',
                              cycleId: item.cycleId,
                            ),
                          ),
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

                      // Inline Current Leader (rating phase), Previous Winner, or placeholder
                      _buildLeaderOrWinnerOrPlaceholder(state),
                  ];

                  return Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: messageChildren,
                      ),
                    ),
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
    final audioUrl = widget.chat.initialMessageAudioUrl;
    final videoUrl = widget.chat.initialMessageVideoUrl;
    final Widget card = MessageCard(
      label: l10n.initialMessageLabel,
      content: initialMessage,
      isPrimary: true,
      mediaAbove: videoUrl != null
          ? ConvergenceVideoCard(
              key: ValueKey('initial-video-${widget.chat.id}'),
              videoUrl: videoUrl,
              chatId: widget.chat.id.toString(),
              source: 'initial_message',
            )
          : null,
      trailing: TtsButton(
        text: initialMessage,
        audioUrl: audioUrl,
        chatId: widget.chat.id.toString(),
        source: 'initial_message',
      ),
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
        context.showErrorMessage(l10n.failedToDeleteConsensus(e.toString()));
      }
      return false;
    }
  }

  void _onConsensusDismissed(int cycleId) {
    ref.read(chatDetailProvider(_params).notifier).onConsensusDismissed(cycleId);
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
        context.showErrorMessage(l10n.failedToDeleteTaskResult(e.toString()));
      }
      return false;
    }
  }

  void _onTaskResultDismissed(int cycleId) {
    ref.read(chatDetailProvider(_params).notifier).onTaskResultDismissed(cycleId);
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
        context.showSuccessSnackBar(l10n.taskResultSubmitted);
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        context.showErrorMessage(l10n.failedToForceConsensus(e.toString()));
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
    } catch (e) {
      if (mounted) {
        context.showErrorMessage(l10n.failedToDeleteInitialMessage(e.toString()));
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
    } catch (e) {
      if (mounted) {
        context.showErrorMessage(l10n.failedToUpdateInitialMessage(e.toString()));
      }
    }
  }

  /// Round status bar rendered directly under the AppBar. Visible only
  /// when an active round is in proposing or rating phase. Returns an
  /// empty widget otherwise (waiting / no round / etc).
  Widget _buildTopPhaseBar(ChatDetailState state) {
    final currentRound = state.currentRound;
    if (currentRound == null) return const SizedBox.shrink();
    final isProposing = currentRound.phase == RoundPhase.proposing;
    final isRating = currentRound.phase == RoundPhase.rating;
    if (!isProposing && !isRating) return const SizedBox.shrink();
    final chat = state.chat ?? widget.chat;
    int? participationPercent;
    if (isProposing) {
      // A participant counts as "done" for participation % if they
      // submitted, skipped, OR affirmed. Use a Set union so a participant
      // who somehow appears in two paths (e.g., a server-side race) is
      // only counted once.
      final donePIds = <int>{
        ...state.propositions
            .where((p) => p.participantId != null && !p.isCarriedForward)
            .map((p) => p.participantId!),
        ...state.participantsWhoSkippedProposing,
        ...state.participantsWhoAffirmed,
      };
      final proposingDone = donePIds.length;
      participationPercent = state.participants.isNotEmpty
          ? (proposingDone * 100 / state.participants.length).round()
          : 0;
    } else {
      participationPercent = state.ratingProgressPercent;
    }
    // When the chat is host-paused mid-round, swap the timer for the
    // "Paused" indicator (matching the in-panel host-paused fallback).
    final isHostPaused = chat.hostPaused;
    return RoundPhaseBar(
      roundNumber: currentRound.customId,
      isProposing: isProposing,
      phaseEndsAt: isHostPaused ? null : currentRound.phaseEndsAt,
      onPhaseExpired: _onPhaseExpired,
      participationPercent: participationPercent,
      isPaused: isHostPaused,
      // Both edges use phase-colored accent strips rendered by the
      // parent. The bar itself shows no plain dividers.
      showTopDivider: false,
      showBottomDivider: false,
    );
  }

  Widget _buildBottomArea(ChatDetailState state) {
    return _buildCurrentPhasePanel(state);
  }

  int _clampedWinnerIndex(ChatDetailState state) {
    return state.previousRoundWinners.isEmpty
        ? 0
        : _currentWinnerIndex.clamp(0, state.previousRoundWinners.length - 1);
  }

  /// Inline Previous Winner card shown in the scrollable message list,
  /// below the last convergence item. Shares winner index state with
  /// the bottom panel version.
  Widget _buildTopCandidatePlaceholder({int? currentCycleId, int roundNumber = 1, int convergenceNumber = 1}) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: currentCycleId != null
            ? () => _pushScreen(
                  MaterialPageRoute(
                    builder: (_) => CycleHistoryScreen(
                      cycleId: currentCycleId,
                      convergenceContent: '...',
                      convergenceNumber: convergenceNumber,
                      showOngoingPlaceholder: false,
                    ),
                  ),
                )
            : null,
        child: UnconstrainedBox(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 64,
            ),
            child: PropositionContentCard(
              content: '...',
              label: l10n.chatTourPlaceholderTitle,
              borderColor: AppColors.consensus,
              glowColor: AppColors.consensus,
            ),
          ),
        ),
      ),
    );
  }

  /// Shows previous winner if exists, or placeholder.
  /// During rating phase we deliberately do NOT expose any in-progress
  /// data (current leader, scored propositions, etc.) — exposing it would
  /// let a user who finished rating share their screen with a user who
  /// hasn't proposed/rated yet, which is a cheating vector.
  Widget _buildLeaderOrWinnerOrPlaceholder(ChatDetailState state) {
    // Waiting state (no round, or round in waiting phase with no new
    // submissions yet): show the waiting message inline. The bottom panel
    // goes empty in this case so the user doesn't see two layers of "we
    // are waiting." Credit-paused state is excluded — the panel still
    // shows the CreditPausedPanel and we keep the placeholder above it.
    if (_inWaitingState(state)) {
      return _buildInlineWaitingState(state);
    }
    // Rating phase (funded participants): replace the proposition / winner
    // cards with the rating action UI (Start Rating + optional Skip, or
    // Done / Skipped indicators after the user acts). Unfunded spectators
    // keep the previous-winner / placeholder card; the panel below handles
    // their spectator banner.
    if (state.currentRound?.phase == RoundPhase.rating &&
        state.isMyParticipantFunded) {
      return _buildInlineRatingAction(state);
    }
    if (state.previousRoundWinners.isNotEmpty) {
      return _buildInlinePreviousWinner(state);
    }
    // R1 post-submit (proposing only): show the user's submission card.
    // Note: in rating phase the rating-action branch above returns first,
    // so the card is NOT shown during rating — only during proposing
    // after they submit. (Earlier comment claimed "stays visible through
    // rating"; that was aspirational and contradicted the actual flow.)
    final newSubs =
        state.myPropositions.where((p) => !p.isCarriedForward).length;
    if (newSubs > 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 64),
            child: _buildSubmittedPropCards(state),
          ),
        ),
      );
    }
    // R1 (no previous winner) skip case: the skipped indicator branch
    // inside _buildInlinePreviousWinner only fires when a previous winner
    // exists. Without this fallback, a host who skips on the first round
    // of a new cycle falls through to the empty placeholder card. Show
    // the same chip + "Waiting for next phase" subtext used elsewhere.
    if (state.hasSkipped &&
        state.currentRound?.phase == RoundPhase.proposing) {
      return _buildInlineSkippedIndicator();
    }
    if (_inputInChatScroll(state)) {
      return _buildR1InlineInput(state);
    }
    // Paused (host or schedule) with nothing else to surface: hide the
    // placeholder. The dedicated paused banner explains the state, so the
    // empty placeholder above it just reads as visual clutter.
    final chat = state.chat ?? widget.chat;
    if (chat.isPaused) return const SizedBox.shrink();
    return _buildTopCandidatePlaceholder();
  }

  /// Inline "Skipped" chip + "Waiting for next phase" subtext used when
  /// the user has skipped proposing this round. Reused from both the R1
  /// fallback path (no previous winner) and the R2+ previous-winner
  /// branch so the post-skip UI is identical regardless of whether a
  /// carried-forward winner exists.
  Widget _buildInlineSkippedIndicator() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              key: const Key('inline-skipped-indicator'),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.skip_next,
                      color: theme.colorScheme.onSurfaceVariant, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    l10n.skipped,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.waitingForNextPhase,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the styled card(s) for the user's submitted proposition(s).
  /// Sizes to its parent — caller wraps in Expanded / centered constraint
  /// as appropriate for the surrounding layout.
  Widget _buildSubmittedPropCards(ChatDetailState state) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final myProps = state.myPropositions
        .where((p) => !p.isCarriedForward)
        .toList();
    if (myProps.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < myProps.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          PropositionContentCard(
            content: myProps[i].content,
            label: l10n.yourProposition,
            borderColor: AppColors.consensus,
            glowColor: AppColors.consensus,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.waitingForNextPhase,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// A card-style proposition input matching PreviousWinnerPanel's
  /// container. The label "Your proposition" sits above an editable
  /// textfield. The trailing button at the right is contextual: send
  /// when there's text, otherwise [emptyAction] (skip in R1, exit-alternative
  /// in R2+ alternative sub-view).
  Widget _buildPropositionInputCard({
    required ChatDetailState state,
    required Key textFieldKey,
    required Key submitKey,
    required Key emptyKey,
    required VoidCallback? emptyOnPressed,
    required String emptyTooltip,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chat = state.chat ?? widget.chat;
    final disabledByMutation =
        chat.isPaused || _isSubmitting || _isSkipping;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.consensus,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.consensus.withValues(alpha: 0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: AppColors.consensus.withValues(alpha: 0.1),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.yourProposition,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _propositionController,
                      builder: (context, value, child) {
                        return TextField(
                          key: textFieldKey,
                          controller: _propositionController,
                          enabled: !chat.isPaused,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: l10n.shareYourIdea,
                            hintStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            counterText: '',
                          ),
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 200,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _propositionController,
                    builder: (context, value, child) {
                      final textEmpty = value.text.trim().isEmpty;
                      // Text-only button (was icon-only) so the alternative
                      // microcopy can reference "Send your idea" with a
                      // clearly labeled target. Empty state re-uses
                      // emptyTooltip as the label (e.g. "Skip" in R1).
                      return FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.consensus,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.consensus
                              .withValues(alpha: 0.3),
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        key: textEmpty ? emptyKey : submitKey,
                        onPressed: disabledByMutation
                            ? null
                            : textEmpty
                                ? emptyOnPressed
                                : _submitProposition,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : Text(
                                textEmpty ? emptyTooltip : l10n.send,
                              ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
    );
  }

  Widget _buildR1InlineInput(ChatDetailState state) {
    final l10n = AppLocalizations.of(context);
    final chat = state.chat ?? widget.chat;
    final canSkipR1 = chat.allowSkipProposing && state.canSkip;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _buildPropositionInputCard(
        state: state,
        textFieldKey: const Key('inline-r1-input'),
        submitKey: const Key('inline-r1-submit-button'),
        emptyKey: const Key('inline-r1-skip-button'),
        emptyOnPressed:
            chat.allowSkipProposing && canSkipR1 ? _skipProposing : null,
        emptyTooltip: l10n.skip,
      ),
    );
  }

  /// True when the chat is in a "waiting" state — either no round
  /// exists yet (pre-cycle) or the round is in waiting phase with no
  /// new propositions queued. Excludes credit-paused (handled by the
  /// in-panel CreditPausedPanel) and the WaitingForRatingPanel sub-case
  /// (proposing finished, host needs to start rating manually).
  bool _inWaitingState(ChatDetailState state) {
    final chat = state.chat ?? widget.chat;
    final isCreditPaused = state.chatCredits != null &&
        !state.chatCredits!.canAfford(state.activeParticipantCount);
    if (isCreditPaused) return false;
    final currentRound = state.currentRound;
    if (currentRound == null) {
      // Pre-cycle (chat-level start_mode pending). Skip if the chat is
      // host-paused — that has its own banner.
      if (chat.hostPaused) return false;
      return true;
    }
    if (currentRound.phase != RoundPhase.waiting) return false;
    final hasNewPropositions =
        state.propositions.any((p) => !p.isCarriedForward);
    return !hasNewPropositions;
  }

  /// Renders the "Waiting for N more participants" message in the chat
  /// scroll. Mirrors the content of WaitingStatePanel; the panel itself
  /// runs in compactMode (renders nothing) so the chat doesn't show
  /// two layers of waiting UI.
  Widget _buildInlineWaitingState(ChatDetailState state) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chat = state.chat ?? widget.chat;
    final hasShareButton = state.myParticipant?.isHost == true &&
        widget.chat.inviteCode != null &&
        widget.chat.accessMethod == AccessMethod.code;
    final autoStart = chat.autoStartParticipantCount ?? 3;
    final remaining = autoStart - state.participants.length;
    final waitingCount = remaining > 0 ? remaining : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: const Key('inline-waiting-state'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.waiting,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.waitingForMoreParticipants(waitingCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasShareButton && state.participants.length <= 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.ios_share,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.noMembersYetShareHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Renders the rating-phase action UI in the chat scroll: Start /
  /// Continue Rating (filled CTA) + optional Skip, or Done / Skipped
  /// indicators once the user has acted. Replaces the proposition /
  /// previous winner cards during rating since they're not directly
  /// relevant while the user is voting.
  Widget _buildInlineRatingAction(ChatDetailState state) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chat = state.chat ?? widget.chat;

    // After rating action (done OR skipped): chip + the same
    // "Waiting for next phase" subtext used in the proposing-phase
    // indicators, so all five exit states (submit / affirm / skip-prop /
    // rate-done / skip-rating) share the same closing line.
    if (state.hasRated) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                key: const Key('inline-rating-complete-indicator'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      l10n.done,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.waitingForNextPhase,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (state.hasSkippedRating) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                key: const Key('inline-rating-skipped-indicator'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.skip_next,
                        color: theme.colorScheme.secondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      l10n.skipped,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.waitingForNextPhase,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final disabled = chat.isPaused || _isSkipping;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('inline-start-rating-button'),
                  onPressed:
                      disabled ? null : () => _openRatingScreen(state),
                  icon: const Icon(Icons.how_to_vote_outlined, size: 18),
                  label: Text(state.hasStartedRating
                      ? l10n.continueRating
                      : l10n.startRating),
                ),
                if (state.canSkipRating && !state.hasStartedRating)
                  OutlinedButton(
                    key: const Key('inline-skip-rating-button'),
                    onPressed: disabled ? null : _skipRating,
                    child: Text(l10n.skip),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              chat.allowSkipRating
                  ? l10n.ratingMicrocopy
                  : l10n.ratingMicrocopyNoSkip,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// True when the user-facing input lives in the chat scroll instead of
  /// the bottom panel. The panel goes minimal (phase bar only) and the
  /// chat scroll renders one of:
  ///   - R1 proposing: a plain textfield + send/skip
  ///   - R2+ proposing with skips: the Affirm/Alternative gate (or alternative
  ///     textfield/winner sub-views inside it)
  ///
  /// Returns false when the user has already submitted, skipped, or the
  /// chat config doesn't fit (R2+ without skips falls back to the in-panel
  /// input as before).
  bool _inputInChatScroll(ChatDetailState state) {
    final currentRound = state.currentRound;
    if (currentRound == null) return false;
    if (currentRound.phase != RoundPhase.proposing) return false;
    if (state.isTaskResultMode) return false;
    if (state.hasSkipped) return false;
    // Affirmed users have no further action this round — surface the
    // winner card + Affirmed indicator instead of the gate UI.
    if (state.hasAffirmed || _hasAffirmedThisRound) return false;
    // Unfunded spectators see the in-panel spectator banner — keep the
    // panel rendering its full layout for them.
    if (!state.isMyParticipantFunded) return false;
    // R1: no previous winner → inline R1 input. R2+: gate flow regardless
    // of allow_skip_proposing — Affirm has its own RPC and is always
    // available when a carried-forward winner exists. Skip remains
    // gated by allow_skip_proposing inside the gate's empty-text icon.
    return true;
  }

  Widget _buildInlinePreviousWinner(ChatDetailState state) {
    final l10nForLabel = AppLocalizations.of(context);
    // When the user has affirmed, the winner card itself becomes the
    // confirmation. Swap the "Round X Winner" label for "You affirmed"
    // so the card reads as the action result; the separate orange chip
    // beneath it goes away.
    final affirmedThisRound =
        (state.hasAffirmed || _hasAffirmedThisRound) &&
            state.currentRound?.phase == RoundPhase.proposing;
    final winnerCard = PreviousWinnerPanel(
      previousRoundWinners: state.previousRoundWinners,
      currentWinnerIndex: _clampedWinnerIndex(state),
      roundNumber: (state.currentRound?.customId ?? 2) - 1,
      labelOverride: affirmedThisRound ? l10nForLabel.yourAffirmation : null,
      onWinnerIndexChanged: (index) =>
          setState(() => _currentWinnerIndex = index),
      onTap: state.currentCycle != null
          ? () {
              _pushScreen(
                MaterialPageRoute(
                  builder: (_) => CycleHistoryScreen(
                    cycleId: state.currentCycle!.id,
                    convergenceContent:
                        state.previousRoundWinners.first.displayContent ??
                            '',
                    convergenceNumber: state.consensusItems.length + 1,
                  ),
                ),
              );
            }
          : null,
    );

    final inGateFlow = _inputInChatScroll(state);
    // R2+ post-submit: show the submitted prop card alone. The previous
    // winner is intentionally hidden — once the user has put a fresh
    // proposition forward, going back to "see what you're competing
    // with" would invite second-guessing without changing the outcome.
    final newSubs =
        state.myPropositions.where((p) => !p.isCarriedForward).length;
    if (newSubs > 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _buildSubmittedPropCards(state),
      );
    }

    // Affirmed: the PreviousWinnerPanel above already swaps its label
    // to "Your affirmation" (see labelOverride) so the card itself
    // doubles as the confirmation. We just append the
    // waiting-for-next-phase subtext; the standalone orange chip has
    // been retired.
    if (affirmedThisRound) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            winnerCard,
            const SizedBox(height: 8),
            Text(
              l10n.waitingForNextPhase,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Skipped (during proposing): show ONLY the muted "Skipped" chip
    // and the waiting subtext — no winner card. Skip is "I'm stepping
    // back this round"; surfacing the winner anyway would feel like
    // shoving the thing they opted out of in their face. Submit and
    // affirm still get a card because they ARE contributions; skip is
    // the absence of one.
    final skippedThisRound = state.hasSkipped &&
        state.currentRound?.phase == RoundPhase.proposing;
    if (skippedThisRound) {
      return _buildInlineSkippedIndicator();
    }

    // Rating phase / other non-gate states with no submission: just
    // the winner card (no chevron, no input).
    if (!inGateFlow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: winnerCard,
      );
    }

    final l10n = AppLocalizations.of(context);
    final chat = state.chat ?? widget.chat;
    final disabledByMutation =
        chat.isPaused || _isSubmitting || _isSkipping;

    // Alternative mode: textfield card centered (same width as the gate winner
    // card) with two buttons below — [Back] (returns to the gate, typed
    // text preserved) and [Skip] (casts a skip). Layout parallels the
    // gate's [Affirm] [Alternative] row beneath the winner card. Send is the
    // filled icon inside the card and acts as the primary action; both
    // buttons below are outlined.
    if (_alternativeMode) {
      final canSkip =
          chat.allowSkipProposing && state.canSkip && !disabledByMutation;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width - 64),
                child: _buildPropositionInputCard(
                  state: state,
                  textFieldKey: const Key('inline-alternative-input'),
                  submitKey: const Key('inline-alternative-submit-button'),
                  emptyKey: const Key('inline-alternative-submit-disabled'),
                  emptyOnPressed: null,
                  emptyTooltip: l10n.send,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    key: const Key('inline-alternative-back-button'),
                    onPressed: disabledByMutation
                        ? null
                        : () => setState(() => _alternativeMode = false),
                    child: Text(l10n.gateBack),
                  ),
                  if (chat.allowSkipProposing)
                    OutlinedButton(
                      key: const Key('inline-alternative-skip-button'),
                      onPressed: canSkip ? _skipProposing : null,
                      child: Text(l10n.skip),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                chat.allowSkipProposing
                    ? l10n.alternativeMicrocopy
                    : l10n.alternativeMicrocopyNoSkip,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    // Affirm is a first-class action with its own RPC; it does NOT
    // depend on the chat's allow_skip_proposing flag. Any active
    // participant in R2+ proposing may affirm as long as they haven't
    // submitted, skipped, or affirmed already. The DB mirrors these
    // checks — see migration 20260501070000_decouple_affirm_from_skip_config.
    // Both the optimistic local flag (_hasAffirmedThisRound) and the
    // server-synced hasAffirmed gate the button so it stays disabled
    // across hot restarts.
    final canAffirmInline = !state.hasSkipped &&
        !state.hasAffirmed &&
        !_hasAffirmedThisRound &&
        state.myPropositions.where((p) => !p.isCarriedForward).isEmpty;

    // Gate: winner card + Affirm/Alternative buttons + microcopy.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          winnerCard,
          const SizedBox(height: 12),
          Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  key: const Key('gate-affirm-button'),
                  onPressed: canAffirmInline && !disabledByMutation
                      ? _affirmRound
                      : null,
                  child: Text(l10n.gateAffirm),
                ),
                OutlinedButton(
                  key: const Key('gate-alternative-button'),
                  onPressed: disabledByMutation
                      ? null
                      : () => setState(() => _alternativeMode = true),
                  child: Text(l10n.gateAlternative),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.gateMicrocopy,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPhasePanel(ChatDetailState state) {
    // Use fresh chat from state for dynamic fields (schedulePaused), fall back to widget.chat
    final chat = state.chat ?? widget.chat;
    final isHost = state.myParticipant?.isHost == true;

    // Host pause replaces the entire bottom panel — there are no actions
    // available while paused, so we don't render the misleading
    // "waiting for participants" / disabled-textfield UI underneath.
    // If a round was in progress when pause hit, keep the RoundPhaseBar
    // visible above the banner so users still see "Round X, Proposing"
    // context (the bar itself shows "Paused" since phase_ends_at is null).
    if (chat.hostPaused) {
      final banner = HostPausedBanner(
        isHost: isHost,
        onResume: isHost
            ? () => ref
                .read(chatDetailProvider(_params).notifier)
                .resumeChat()
            : null,
      );
      final activeRound = state.currentRound;
      if (activeRound != null &&
          (activeRound.phase == RoundPhase.proposing ||
              activeRound.phase == RoundPhase.rating)) {
        // Participation % is meaningful even when paused — it tracks
        // user actions (submitted/skipped/rated), not time. Compute it
        // the same way the live ProposingStatePanel/RatingStatePanel do.
        int? participationPercent;
        if (activeRound.phase == RoundPhase.proposing) {
          final submitters = state.propositions
              .where((p) => p.participantId != null && !p.isCarriedForward)
              .map((p) => p.participantId)
              .toSet()
              .length;
          final done = submitters + state.participantsWhoSkippedProposing.length;
          participationPercent = state.participants.isNotEmpty
              ? (done * 100 / state.participants.length).round()
              : 0;
        } else {
          participationPercent = state.ratingProgressPercent;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundPhaseBar(
              roundNumber: activeRound.customId,
              isProposing: activeRound.phase == RoundPhase.proposing,
              phaseEndsAt: null, // signals Paused indicator
              isPaused: true,
              participationPercent: participationPercent,
            ),
            banner,
          ],
        );
      }
      return banner;
    }

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
      // Waiting message lives inline in the chat scroll. Panel goes
      // empty so we don't show two layers of "waiting" UI.
      return WaitingStatePanel(
        participantCount: state.participants.length,
        autoStartParticipantCount: widget.chat.autoStartParticipantCount ?? 3,
        showShareHint: hasShareButton,
        compactMode: true,
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
        // Waiting inline; panel empty.
        return WaitingStatePanel(
          participantCount: state.participants.length,
          autoStartParticipantCount: widget.chat.autoStartParticipantCount ?? 3,
          showShareHint: hasShareButton,
          compactMode: true,
        );
      case RoundPhase.proposing:
        final isTaskResultMode = state.isTaskResultMode;
        // Participation %: (submitters + skippers + affirmers) / total
        // participants. Set union so a single participant counted via
        // multiple paths is only counted once.
        final donePIds = <int>{
          ...state.propositions
              .where((p) => p.participantId != null && !p.isCarriedForward)
              .map((p) => p.participantId!),
          ...state.participantsWhoSkippedProposing,
          ...state.participantsWhoAffirmed,
        };
        final proposingDone = donePIds.length;
        final proposingPercent = state.participants.isNotEmpty
            ? (proposingDone * 100 / state.participants.length).round()
            : 0;
        // Affirm/Alternative gate flow (R2+ with previous winner, skips allowed).
        // While the user is at the gate or refining in place, the gate UI
        // lives in the chat scroll above and the panel stays minimal
        // (phase bar only). The panel also collapses for the three
        // post-action states so the inline cards are the single source
        // of truth and we never double-render an indicator.
        final inGateFlow = _inputInChatScroll(state);
        final affirmedThisRound =
            state.hasAffirmed || _hasAffirmedThisRound;
        final skippedThisRound = state.hasSkipped;
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
          onViewOtherPropositions: () => _pushScreen(
            MaterialPageRoute(
              builder: (_) => OtherPropositionsScreen(params: _params),
            ),
          ),
          isPaused: chat.isPaused,
          isSubmitting: _isSubmitting || _isSkipping,
          onSkip: chat.allowSkipProposing ? _skipProposing : null,
          canSkip: state.canSkip,
          skipCount: state.skipCount,
          maxSkips: state.maxSkips,
          hasSkipped: state.hasSkipped,
          isFunded: state.isMyParticipantFunded,
          isTaskResultMode: isTaskResultMode,
          participationPercent: proposingPercent,
          gateMode:
              inGateFlow || affirmedThisRound || skippedThisRound,
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
          onSkipRating: state.canSkipRating ? _skipRating : null,
          canSkipRating: state.canSkipRating,
          ratingSkipCount: state.ratingSkipCount,
          maxRatingSkips: state.maxRatingSkips,
          hasSkippedRating: state.hasSkippedRating,
          isSkipping: _isSkipping,
          isFunded: state.isMyParticipantFunded,
          participationPercent: state.ratingProgressPercent,
          // Action UI lives in chat scroll above; panel only shows the
          // phase bar at the bottom of the screen.
          compactMode: state.isMyParticipantFunded,
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
        context.showErrorMessage(e.toString());
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
    final leaderboardFuture = ref.read(chatServiceProvider).getChatLeaderboard(widget.chat.id);
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
            final currentState = stateAsync.valueOrNull;
            final participants = currentState?.participants ?? [];
            final isHost = currentState?.myParticipant?.isHost == true;
            final requests = currentState?.pendingJoinRequests ?? [];
            final showRequests = isHost && widget.chat.requireApproval && requests.isNotEmpty;

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: leaderboardFuture,
              builder: (fbContext, snapshot) {
                // Build ranking map: participant_id -> position (1-based)
                final rankings = <int, int>{};
                if (snapshot.hasData) {
                  final ranked = snapshot.data!
                      .where((e) => e['avg_rank'] != null)
                      .toList()
                    ..sort((a, b) => (b['avg_rank'] as num).compareTo(a['avg_rank'] as num));
                  for (var i = 0; i < ranked.length; i++) {
                    rankings[ranked[i]['participant_id'] as int] = i + 1;
                  }
                }

                // Sort participants: ranked first (by position), then unranked
                final sortedParticipants = List<Participant>.from(participants)
                  ..sort((a, b) {
                    final ra = rankings[a.id];
                    final rb = rankings[b.id];
                    if (ra != null && rb != null) return ra.compareTo(rb);
                    if (ra != null) return -1;
                    if (rb != null) return 1;
                    return 0;
                  });

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
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.groups,
                                  size: 20,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '${l10n.participants} (${sortedParticipants.length})',
                                style: theme.textTheme.titleMedium,
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    Navigator.pop(sheetContext),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 28),
                            child: Text(
                              l10n.participantsRankingExplainer,
                              style:
                                  theme.textTheme.bodySmall?.copyWith(
                                color: theme
                                    .colorScheme.onSurfaceVariant,
                              ),
                            ),
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
                    // Participants list. Per-user "Done" state was
                    // intentionally removed: the round status bar's
                    // progress % already shows how close the round is
                    // to closing, and naming individual stragglers
                    // creates social pressure that works against
                    // letting each voice contribute at its own pace.
                    // Host badge is gone (every participant reads as
                    // an equal voice); kick lives on long-press.
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: sortedParticipants.length,
                        itemBuilder: (context, index) {
                          final p = sortedParticipants[index];
                          final position = rankings[p.id];
                          final rankText = position != null ? '#$position' : '—';
                          final canKick = isHost && !p.isHost;
                          return ListTile(
                            leading: CircleAvatar(child: Text(rankText)),
                            title: Text(p.displayName),
                            onLongPress: canKick
                                ? () {
                                    Navigator.pop(modalContext);
                                    _confirmKickParticipant(p);
                                  }
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
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

  void _showPersonalCodeSheet(ChatDetailState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => PersonalCodeSheet(
        chatId: widget.chat.id,
        chatName: state.chat?.displayName ?? widget.chat.displayName,
      ),
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
      } catch (e) {
        if (mounted) {
          context.showErrorMessage(l10n.failedToKickParticipant(e.toString()));
        }
      }
    }
  }

  Future<void> _showLanguagePicker({
    required List<String> availableLanguages,
    required String currentLanguageCode,
  }) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.language),
        children: [
          for (final code in availableLanguages)
            ListTile(
              key: Key('chat-language-option-$code'),
              leading: Icon(
                code == currentLanguageCode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(_languageDisplayNames[code] ?? code),
              onTap: () => Navigator.of(ctx).pop(code),
            ),
        ],
      ),
    );
    if (picked != null && picked != currentLanguageCode) {
      ref
          .read(chatDetailProvider(_params).notifier)
          .setViewingLanguage(picked);
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
      } catch (e) {
        if (mounted) {
          context.showErrorMessage(l10n.failedToPauseChat(e.toString()));
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
    } catch (e) {
      if (mounted) {
        context.showErrorMessage(l10n.failedToApproveRequest(e.toString()));
      }
    }
  }

  Future<void> _handleDeny(int requestId) async {
    await ref
        .read(chatDetailProvider(_params).notifier)
        .denyJoinRequest(requestId);
  }
}

/// Subtle colored strip at the top of the chat body showing current phase.

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
      chipColor = theme.colorScheme.tertiaryContainer;
      iconColor = theme.colorScheme.onTertiaryContainer;
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
