import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/error_view.dart';
import '../../widgets/qr_code_share.dart';
import '../grid_ranking/grid_ranking_screen.dart';
import 'widgets/previous_round_display.dart';
import 'widgets/phase_panels.dart';
import 'widgets/chat_settings_sheet.dart';

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

    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.submitProposition(_propositionController.text.trim());
      _propositionController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    }
  }

  void _openRatingScreen(ChatDetailState state) {
    if (state.currentRound == null || state.myParticipant == null) return;

    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => GridRankingScreen(
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

  Future<void> _startPhase() async {
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.startPhase(widget.chat);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start phase: $e')),
        );
      }
    }
  }

  Future<void> _advanceToRating() async {
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.advanceToRating(widget.chat);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to advance phase: $e')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete rating: $e')),
        );
      }
    }
  }

  void _onPhaseExpired() {
    // Refresh data when phase timer expires to get new state
    ref.read(chatDetailProvider(_params).notifier).refresh();
  }

  Future<void> _deleteProposition(int propositionId) async {
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.deleteProposition(propositionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proposition deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
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
              error: (e, _) => Center(child: Text('Error: $e')),
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
                'All Propositions (${propositions.length})',
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
            'As host, you can moderate content. Submitter identity is hidden.',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: isMine
            ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prop.displayContent),
                if (isMine) ...[
                  const SizedBox(height: 4),
                  Text(
                    '(Your proposition)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (prop.isCarriedForward) ...[
                  const SizedBox(height: 4),
                  Text(
                    '(Previous winner)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
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
    );
  }

  void _confirmDeleteFromSheet(Proposition prop, BuildContext sheetContext) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Proposition?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this proposition?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(prop.displayContent, style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteChat() async {
    final chatName = ref.read(chatDetailProvider(_params)).valueOrNull?.chat?.displayName ?? widget.chat.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat?'),
        content: Text(
          'Are you sure you want to delete "$chatName"?\n\n'
          'This will permanently delete all propositions, ratings, and history. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
            const SnackBar(content: Text('Chat deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete chat: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmLeaveChat() async {
    final chatName = ref.read(chatDetailProvider(_params)).valueOrNull?.chat?.displayName ?? widget.chat.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Chat?'),
        content: Text(
          'Are you sure you want to leave "$chatName"?\n\n'
          'You will no longer see this chat in your list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
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
            const SnackBar(content: Text('You have left the chat')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to leave chat: $e')),
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

    // Check if chat was deleted and navigate back (only if we haven't already navigated)
    final isDeleted = stateAsync.valueOrNull?.isDeleted ?? false;
    if (isDeleted && !_hasNavigatedAway) {
      _hasNavigatedAway = true; // Prevent multiple pops
      // Use post-frame callback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This chat has been deleted')),
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
          ref.read(myChatsProvider.notifier).removeChat(widget.chat.id);
          // Show snackbar BEFORE navigating away so context is valid
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You have been removed from this chat')),
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
        actions: [
          // Phase chip - always visible when in a round
          stateAsync.whenOrNull(
                data: (state) => state.currentRound != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Chip(
                          label:
                              Text(state.currentRound!.phase.name.toUpperCase()),
                          backgroundColor:
                              state.currentRound!.phase == RoundPhase.proposing
                                  ? Colors.blue.shade100
                                  : Colors.purple.shade100,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      )
                    : null,
              ) ??
              const SizedBox.shrink(),
          // Three-dot menu with all options
          stateAsync.whenOrNull(
                data: (state) {
                  final isHost = state.myParticipant?.isHost == true;
                  final isHostPaused = state.chat?.hostPaused ?? widget.chat.hostPaused;
                  final hasInviteCode = widget.chat.inviteCode != null &&
                      widget.chat.accessMethod == AccessMethod.code;
                  final pendingRequestCount = state.pendingJoinRequests.length;

                  return PopupMenuButton<String>(
                    key: const Key('chat-more-menu'),
                    icon: Badge(
                      label: Text('$pendingRequestCount'),
                      isLabelVisible: isHost && widget.chat.requireApproval && pendingRequestCount > 0,
                      child: const Icon(Icons.more_vert),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'participants':
                          _showParticipants(state);
                          break;
                        case 'settings':
                          ChatSettingsSheet.show(
                            context,
                            state.chat ?? widget.chat,
                          );
                          break;
                        case 'qr_code':
                          _showQrCode();
                          break;
                        case 'join_requests':
                          _showJoinRequests(state);
                          break;
                        case 'pause':
                          _showPauseConfirmation();
                          break;
                        case 'resume':
                          ref.read(chatDetailProvider(_params).notifier).resumeChat();
                          break;
                        case 'leave':
                          _confirmLeaveChat();
                          break;
                        case 'delete':
                          _confirmDeleteChat();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      // Participants - always visible
                      const PopupMenuItem(
                        value: 'participants',
                        child: Row(
                          children: [
                            Icon(Icons.people),
                            SizedBox(width: 12),
                            Text('Participants'),
                          ],
                        ),
                      ),
                      // Chat settings - always visible
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline),
                            SizedBox(width: 12),
                            Text('Chat Info'),
                          ],
                        ),
                      ),
                      // QR Code - host only with invite code
                      if (isHost && hasInviteCode)
                        const PopupMenuItem(
                          value: 'qr_code',
                          child: Row(
                            children: [
                              Icon(Icons.qr_code_2),
                              SizedBox(width: 12),
                              Text('Share QR Code'),
                            ],
                          ),
                        ),
                      // Join requests - host only with require_approval
                      if (isHost && widget.chat.requireApproval)
                        PopupMenuItem(
                          value: 'join_requests',
                          child: Row(
                            children: [
                              Badge(
                                label: Text('$pendingRequestCount'),
                                isLabelVisible: pendingRequestCount > 0,
                                child: const Icon(Icons.person_add),
                              ),
                              const SizedBox(width: 12),
                              const Text('Join Requests'),
                            ],
                          ),
                        ),
                      // Pause/Resume - host only
                      if (isHost)
                        PopupMenuItem(
                          value: isHostPaused ? 'resume' : 'pause',
                          child: Row(
                            children: [
                              Icon(isHostPaused ? Icons.play_arrow : Icons.pause),
                              const SizedBox(width: 12),
                              Text(isHostPaused ? 'Resume Chat' : 'Pause Chat'),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      // Leave - non-host only
                      if (!isHost)
                        const PopupMenuItem(
                          value: 'leave',
                          child: Row(
                            children: [
                              Icon(Icons.exit_to_app),
                              SizedBox(width: 12),
                              Text('Leave Chat'),
                            ],
                          ),
                        ),
                      // Delete - host only
                      if (isHost)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 12),
                              Text('Delete Chat',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: stateAsync.when(
        data: (state) => Column(
          children: [
            // Host paused banner
            if (state.chat?.hostPaused ?? widget.chat.hostPaused)
              HostPausedBanner(
                isHost: state.myParticipant?.isHost == true,
              ),
            // Chat History
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Initial Message
                  _buildMessageCard(
                    'Initial Message',
                    state.chat?.displayInitialMessage ?? widget.chat.displayInitialMessage,
                    isPrimary: true,
                  ),
                  const SizedBox(height: 16),

                  // Consensus Items
                  ...state.consensusItems.asMap().entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildMessageCard(
                        'Consensus #${entry.key + 1}',
                        entry.value.content,
                        isPrimary: true,
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Bottom Action Area
            _buildBottomArea(state),
          ],
        ),
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
      {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPrimary
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: isPrimary
            ? Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(content),
        ],
      ),
    );
  }

  Widget _buildBottomArea(ChatDetailState state) {
    final hasPreviousWinner = state.previousRoundWinners.isNotEmpty;

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
          // Tab bar toggle
          _buildToggleTabs(hasPreviousWinner, state),
          // Content based on toggle
          _showPreviousWinner && hasPreviousWinner
              ? _buildPreviousWinnerPanel(state)
              : _buildCurrentPhasePanel(state),
        ],
      ),
    );
  }

  Widget _buildToggleTabs(bool hasPreviousWinner, ChatDetailState state) {
    return Row(
      children: [
        // Previous Winner Tab
        Expanded(
          child: InkWell(
            onTap: hasPreviousWinner
                ? () => setState(() => _showPreviousWinner = true)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _showPreviousWinner && hasPreviousWinner
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : null,
                border: Border(
                  bottom: BorderSide(
                    color: _showPreviousWinner && hasPreviousWinner
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                'Previous Winner',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: hasPreviousWinner
                      ? (_showPreviousWinner
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface)
                      : Theme.of(context).colorScheme.onSurface.withAlpha(100),
                ),
              ),
            ),
          ),
        ),
        // Current Phase Tab
        Expanded(
          child: InkWell(
            onTap: () => setState(() => _showPreviousWinner = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: !_showPreviousWinner
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : null,
                border: Border(
                  bottom: BorderSide(
                    color: !_showPreviousWinner
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                _getPhaseTabLabel(state),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: !_showPreviousWinner
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getPhaseTabLabel(ChatDetailState state) {
    if (state.currentRound == null) return 'Waiting';
    switch (state.currentRound!.phase) {
      case RoundPhase.waiting:
        return 'Waiting';
      case RoundPhase.proposing:
        if (state.myPropositions.isEmpty) return 'Your Proposition';
        final remaining =
            widget.chat.propositionsPerUser - state.myPropositions.length;
        return remaining > 0
            ? 'Your Propositions (${state.myPropositions.length}/${widget.chat.propositionsPerUser})'
            : 'Your Propositions';
      case RoundPhase.rating:
        return state.hasRated ? 'Done' : 'Rate';
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

    if (state.currentRound == null) {
      return WaitingStatePanel(
        isHost: isHost,
        participantCount: state.participants.length,
        onStartPhase: _startPhase,
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
        return WaitingStatePanel(
          isHost: isHost,
          participantCount: state.participants.length,
          onStartPhase: _startPhase,
        );
      case RoundPhase.proposing:
        return ProposingStatePanel(
          roundCustomId: state.currentRound!.customId,
          propositionsPerUser: widget.chat.propositionsPerUser,
          myPropositions: state.myPropositions,
          allPropositionsCount: isHost ? state.propositions.length : 0,
          propositionController: _propositionController,
          onSubmit: _submitProposition,
          phaseEndsAt: state.currentRound!.phaseEndsAt,
          isHost: isHost,
          onAdvancePhase: () => _advanceToRating(),
          onPhaseExpired: () => _onPhaseExpired(),
          onViewAllPropositions: isHost ? () => _showAllPropositionsSheet(state) : null,
          isPaused: chat.isPaused,
        );
      case RoundPhase.rating:
        return RatingStatePanel(
          roundCustomId: state.currentRound!.customId,
          hasRated: state.hasRated,
          hasStartedRating: state.hasStartedRating,
          propositionCount: state.propositions.length,
          onStartRating: () => _openRatingScreen(state),
          phaseEndsAt: state.currentRound!.phaseEndsAt,
          onPhaseExpired: () => _onPhaseExpired(),
          isHost: isHost,
          onAdvancePhase: isHost ? () => _advanceFromRating() : null,
          isPaused: chat.isPaused,
        );
    }
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

  void _showParticipants(ChatDetailState? state) {
    showModalBottomSheet(
      context: context,
      builder: (modalContext) => Consumer(
        // Use Consumer to watch for participant changes in realtime
        builder: (consumerContext, consumerRef, _) {
          final stateAsync = consumerRef.watch(chatDetailProvider(_params));
          final participants = stateAsync.valueOrNull?.participants ?? [];
          final isHost = stateAsync.valueOrNull?.myParticipant?.isHost == true;

          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Participants (${participants.length})',
                  style: Theme.of(consumerContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                ...participants.map((p) => ListTile(
                      leading: CircleAvatar(child: Text(p.displayName[0])),
                      title: Text(p.displayName),
                      trailing: p.isHost
                          ? const Chip(label: Text('Host'))
                          : isHost
                              ? IconButton(
                                  icon: const Icon(Icons.person_remove),
                                  tooltip: 'Kick participant',
                                  onPressed: () {
                                    Navigator.pop(modalContext);
                                    _confirmKickParticipant(p);
                                  },
                                )
                              : null,
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmKickParticipant(Participant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kick Participant?'),
        content: Text(
          'Are you sure you want to remove "${participant.displayName}" from this chat?\n\n'
          'They will not be able to rejoin without approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Kick'),
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
            SnackBar(
                content: Text('${participant.displayName} has been removed')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to kick participant: $e')),
          );
        }
      }
    }
  }

  Future<void> _showPauseConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pause Chat?'),
        content: const Text(
          'This will pause the current phase timer. '
          'Participants will see that the chat is paused by the host.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pause'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(chatDetailProvider(_params).notifier).pauseChat();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat paused')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to pause chat: $e')),
          );
        }
      }
    }
  }

  void _showJoinRequests(ChatDetailState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (sheetContext, scrollController) => Consumer(
          // Use Consumer to watch for state changes in realtime
          builder: (consumerContext, consumerRef, _) {
            final stateAsync = consumerRef.watch(chatDetailProvider(_params));
            final requests =
                stateAsync.valueOrNull?.pendingJoinRequests ?? [];

            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join Requests (${requests.length})',
                    style: Theme.of(consumerContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Approve or deny requests to join this chat.',
                    style: Theme.of(consumerContext).textTheme.bodySmall?.copyWith(
                          color: Theme.of(consumerContext)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  if (requests.isEmpty)
                    _buildEmptyRequestsState()
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          final req = requests[index];
                          return _buildRequestCard(req);
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyRequestsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('No pending requests',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('New requests will appear here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
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
                  req['is_authenticated'] == true ? 'Signed in' : 'Guest',
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
            tooltip: 'Approve',
          ),
          IconButton(
            icon:
                Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
            onPressed: () => _handleDeny(req['id']),
            tooltip: 'Deny',
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(int requestId) async {
    try {
      await ref
          .read(chatDetailProvider(_params).notifier)
          .approveJoinRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request approved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleDeny(int requestId) async {
    await ref
        .read(chatDetailProvider(_params).notifier)
        .denyJoinRequest(requestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request denied')),
      );
    }
  }
}
