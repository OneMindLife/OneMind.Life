import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/perf_logger.dart';
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
import '../../services/matches/match_pair_selector.dart' show MatchObjective;
import '../../services/remote_log_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/name_section.dart';
import '../../widgets/tts_button.dart';
import '../../core/l10n/locale_provider.dart';
import '../../widgets/glossary_term.dart';
import '../../widgets/proposition_content_card.dart';
import '../../widgets/ranked_leaderboard.dart';
import '../../widgets/round_phase_bar.dart';
import '../../widgets/message_card.dart';
import '../../widgets/qr_code_share.dart';
import '../../widgets/invite_share_sheet.dart';
import '../rating/rating_screen.dart';
import '../rating/read_only_results_screen.dart';
import 'cycle_history_screen.dart';
import 'other_propositions_screen.dart';
import 'widgets/personal_code_sheet.dart';
import 'widgets/previous_round_display.dart';
import 'widgets/matches_rating_panel.dart';
import 'widgets/host_end_voting_bar.dart';
import 'widgets/phase_panels.dart';
import 'widgets/seed_options_dialog.dart';
import 'widgets/tree_stack_section.dart';
import '../../config/env_config.dart';
import '../../config/quick_chat_guard.dart';

const _languageDisplayNames = {
  'en': 'English',
  'es': 'Español',
  'pt': 'Português',
  'fr': 'Français',
  'de': 'Deutsch',
};

/// Whether tapping the round-winner card opens the just-completed round's FULL
/// rankings (winner + losers) instead of the cycle-history (round-winners)
/// list. True for instant chats (`confirmationRounds == 1`) AND for all quick
/// chats (`maxCycles == 1`) — even convergence ones — because a quick chat is
/// too short to have a multi-cycle history worth browsing; the group just
/// wants the full results of the round they finished. Only full-wizard
/// multi-cycle chats keep the cycle-history view on tap.
bool winnerTapShowsRoundResults({
  required int confirmationRounds,
  required int? maxCycles,
}) =>
    confirmationRounds == 1 || maxCycles == 1;

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
  // RT-RACE-DEBUG: previous bar values, used to log only on change.
  // Remove fields together with the call site before merge.
  int? _rtRaceLastBarPercent;
  RoundPhase? _rtRaceLastBarPhase;
  int? _rtRaceLastBarRoundId;
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
  // Guards the host Start button against a double-fire (the cause of duplicate
  // cycles/rounds). Set on tap, never reset on success — the waiting panel
  // (and its button) is replaced by the proposing UI once start lands.
  bool _isStarting = false;

  /// One-shot guard for the host's seed dialog (see [_maybeShowSeedDialog]).
  /// SESSION-GLOBAL (static, keyed by chat id), not per-State: the home
  /// auto-open flow can mount ChatScreen more than once in quick succession,
  /// and a second mount races the cycle creation (currentRound still null on
  /// its first bootstrap) — a per-State flag let the dialog show twice.
  static final Set<int> _seedPromptShownFor = <int>{};

  /// Quick-chat host proposing UI: the share block is the persistent base
  /// layer; the host's own input is behind an "Add your own idea" toggle.
  bool _hostInputExpanded = false;
  bool _isSkipping = false;

  // Track if we've already navigated away (to prevent double-pop)
  bool _hasNavigatedAway = false;

  // Quick-create preview "Invite others to rank these": disables the CTA
  // while the real chat is being created so it can't double-fire.
  bool _isCreatingRealChat = false;
  bool _isEndingVoting = false;

  /// Lazily-loaded ranking for the inline ended-state leaderboard (matches
  /// mode). Cached so panel rebuilds don't refetch. See [_loadEndedRanking].
  Future<List<Proposition>>? _endedRankingFuture;

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
    // C15 tree mode: entering the chat starts a FRESH walk from position 1.
    // (The provider deliberately survives in-visit rebuilds — realtime
    // refreshes must not wipe a built stack — but a new screen entry resets.)
    if (widget.chat.branchingEnabled) {
      Future.microtask(() {
        if (mounted) {
          ref.read(treeChoicesProvider(widget.chat.id).notifier).state = {};
          ref.read(treeOpenLevelsProvider(widget.chat.id).notifier).state = {};
        }
      });
    }
    final analytics = ref.read(analyticsServiceProvider);
    analytics.logScreenView(screenName: 'chat_detail');
    analytics.logChatOpened(chatId: widget.chat.id.toString());
    _setupScheduledTimeTimer();
    _setupLifecycleListener();
    final bgUrl = widget.chat.backgroundAudioUrl;
    if (bgUrl != null && bgUrl.isNotEmpty) {
      final service = ref.read(backgroundAudioServiceProvider);
      _bgAudioForDispose = service;
      service.enterChat(bgUrl);
    }
    // Preview chats never expose share/invite — suppress the auto-show.
    if (widget.showShareDialog && !widget.chat.isPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.chat.accessMethod == AccessMethod.personalCode) {
          // For personal_code chats, show the code management sheet
          final state = ref.read(chatDetailProvider(_params)).valueOrNull;
          if (state != null) _showPersonalCodeSheet(state);
        } else if (widget.chat.inviteCode != null) {
          _showQrCode(auto: true);
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

  /// The authoritative rating mode for this chat. `widget.chat` can be a stale
  /// snapshot from the Home dashboard list — `get_my_chats_dashboard` returns
  /// an explicit column list that omits `rating_mode`, so `Chat.fromJson`
  /// defaults it to 'grid'. The bootstrap RPC (`state.chat`) carries the real
  /// value via `to_jsonb(c.*)`, so prefer it; fall back to `widget.chat` before
  /// the bootstrap lands. Without this, a matches chat's results render the
  /// 0–100 grid instead of the ranked view.
  String get _effectiveRatingMode =>
      ref.read(chatDetailProvider(_params)).valueOrNull?.chat?.ratingMode ??
      widget.chat.ratingMode;

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
    // Skipping proposing opts the user out of the round (no idea submitted),
    // so confirm first — same treatment as the matches "Done" leave action.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip this round?'),
        content: const Text("You won't submit an idea this round."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
      // Instant-ranking chats finalize the moment the last rater is done — nudge
      // the timer processor so the result isn't delayed to the next cron tick.
      if (_isInstantRanking) {
        await ref.read(chatServiceProvider).triggerProcessTimers();
      }
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

  // ---- Quick-create (instant ranking) flow helpers -------------------------
  //
  // These are all gated by the caller on the quick-create conditions
  // (confirmationRoundsRequired == 1, isPreview, endedAt != null). They are
  // inert for normal grid/convergence chats.

  /// True when this chat is an "instant ranking" quick-create chat:
  /// exactly ONE round per cycle. For these, after the single round the chat
  /// ends and we jump straight to the full rankings (skipping cycle history).
  bool get _isInstantRanking => widget.chat.confirmationRoundsRequired == 1;

  /// Tapping the round-winner card jumps straight to the just-completed
  /// round's FULL rankings (winner + losers) instead of opening the
  /// cycle-history (round-winners) list. See [winnerTapShowsRoundResults].
  bool get _winnerTapShowsRoundResults => winnerTapShowsRoundResults(
        confirmationRounds: widget.chat.confirmationRoundsRequired,
        maxCycles: widget.chat.maxCycles,
      );

  /// Resolve the just-completed round (id + display number) from state for the
  /// instant-ranking flow. Prefers `previousRoundWinners` (carries the winning
  /// round's id); falls back to the current round when it's the one that just
  /// resolved. Returns null if no completed round can be sourced from state.
  ({int roundId, int roundNumber})? _completedRoundFromState(
      ChatDetailState? state) {
    if (state == null) return null;
    final winners = state.previousRoundWinners;
    if (winners.isNotEmpty) {
      final roundId = winners.first.roundId;
      // previousRoundWinners don't carry a customId; the current round's
      // customId (if present) is the same round in the single-round case,
      // otherwise fall back to 1 (instant chats only ever have round 1).
      final number = state.currentRound?.customId ?? 1;
      return (roundId: roundId, roundNumber: number);
    }
    // No winners list yet — fall back to a completed current round.
    final round = state.currentRound;
    if (round != null && round.winningPropositionId != null) {
      return (roundId: round.id, roundNumber: round.customId);
    }
    return null;
  }

  /// Reusable results loader: fetches the round's propositions (pre-sorted by
  /// finalRating desc by the service) + rater count, then pushes the
  /// read-only full-rankings screen. Mirrors the loader in
  /// CycleHistoryScreen._openRoundResults.
  Future<void> _openRoundResults(int roundId, int roundNumber) async {
    final svc = ref.read(propositionServiceProvider);
    final lang = ref.read(localeProvider).languageCode;
    final results = await Future.wait([
      svc.getPropositionsWithRatings(roundId, languageCode: lang),
      svc.getRaterCount(roundId),
    ]);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReadOnlyResultsScreen(
          propositions: results[0] as List<Proposition>,
          roundNumber: roundNumber,
          roundId: roundId,
          ratingMode: _effectiveRatingMode,
          raterCount: results[1] as int,
        ),
      ),
    );
  }

  /// Open the full rankings for the finished round. Resolves the round id from
  /// state when present, else queries the DB — an ENDED chat's bootstrap is empty
  /// (no active cycle), so state alone can't supply the completed round.
  Future<void> _resolveAndOpenResults(ChatDetailState? state) async {
    var completed = _completedRoundFromState(state);
    if (completed == null) {
      final latest =
          await ref.read(chatServiceProvider).getLatestRoundForChat(widget.chat.id);
      if (latest != null) {
        completed = (roundId: latest.id, roundNumber: latest.customId);
      }
    }
    if (completed == null || !mounted) return;
    // Aha/value-delivered moment: the group's ranked outcome is about to be on
    // screen. Fires for every chat type (quick + full wizard) through this one
    // funnel — segmentable by rating_mode / is_quick_chat / round_number.
    ref.read(analyticsServiceProvider).logResultsViewed(
          chatId: widget.chat.id.toString(),
          roundNumber: completed.roundNumber,
          ratingMode: _effectiveRatingMode,
          isQuickChat: widget.chat.maxCycles == 1,
        );
    await _openRoundResults(completed.roundId, completed.roundNumber);
  }

  /// Resolve the completed round (state → DB fallback) and fetch its
  /// propositions, pre-sorted desc by finalRating — the data for the inline
  /// ended-state leaderboard. Returns empty if no completed round resolves.
  Future<List<Proposition>> _loadEndedRanking(ChatDetailState? state) async {
    var completed = _completedRoundFromState(state);
    if (completed == null) {
      final latest = await ref
          .read(chatServiceProvider)
          .getLatestRoundForChat(widget.chat.id);
      if (latest != null) {
        completed = (roundId: latest.id, roundNumber: latest.customId);
      }
    }
    if (completed == null) return const [];
    final lang = ref.read(localeProvider).languageCode;
    return ref
        .read(propositionServiceProvider)
        .getPropositionsWithRatings(completed.roundId, languageCode: lang);
  }

  /// Host ends the rating phase NOW (real quick-create chats): confirm the
  /// terminal action, tally votes as they stand via host_end_voting (which
  /// locks in the winner and ends the chat), then open the rankings — the
  /// button promised "show results", so we deliver them, not the ended panel.
  Future<void> _endVoting(ChatDetailState state) async {
    if (_isEndingVoting) return;
    // Confirm ONLY when ending EARLY — i.e. people who are present haven't
    // finished voting and would be cut off. When everyone present is done
    // (any count, including solo), the host's explicit tap is enough; *not*
    // tapping is how they wait for more. We deliberately don't surface WHICH
    // people are outstanding — naming stragglers is the social pressure
    // OneMind avoids; the count is all the host needs to decide.
    final eligible = state.matchesEligibleRaters;
    final done = state.matchesDoneRaters;
    final endingEarly = eligible > 0 && done < eligible;
    if (endingEarly) {
      final outstanding = eligible - done;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('End voting early?'),
          content: Text(
            "$outstanding of $eligible here ${outstanding == 1 ? "hasn't" : "haven't"} "
            'voted yet. End now and the result is final — their votes won\'t '
            "count, and this can't be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep voting open'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('End anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _isEndingVoting = true);
    try {
      await ref.read(chatServiceProvider).hostEndVoting(widget.chat.id);
      ref.read(analyticsServiceProvider).logQuickCreateVotingEnded();
      if (!mounted) return;
      // Stay in the chat — the ended-matches body already renders the ranked
      // leaderboard (Question → results). Pushing a separate results screen on
      // top would be redundant; just refresh into the ended state.
      ref.read(chatDetailProvider(_params).notifier).refresh(silent: true);
    } catch (e) {
      if (mounted) context.showErrorMessage('Could not end voting: $e');
    } finally {
      if (mounted) setState(() => _isEndingVoting = false);
    }
  }

  /// Preview "Invite others to rank these": re-creates a REAL (non-preview)
  /// chat from the same options and seeds the same prioritization round, then
  /// replaces the current preview screen with the real chat (which shows the
  /// share button).
  Future<void> _createRealChatFromPreview(ChatDetailState state) async {
    if (_isCreatingRealChat) return;
    setState(() => _isCreatingRealChat = true);
    try {
      final chatService = ref.read(chatServiceProvider);
      final auth = ref.read(authServiceProvider);
      await auth.ensureSignedIn();
      // Name gate: stored display name, or prompt (never auto-generated).
      if (!mounted) return;
      final hostName = await ensureDisplayNameInteractive(context, ref);
      if (hostName == null) {
        setState(() => _isCreatingRealChat = false);
        return;
      }
      final participant = ref.read(participantServiceProvider);

      // GROUP path (the preview used AI agents to stand in for participants): the
      // real run is humans-only — no agents, no seeded options. Real people propose
      // ideas, then everyone ranks them. Starts once a few participants have joined.
      if (widget.chat.enableAgents) {
        final real = await chatService.createChat(
          name: widget.chat.name,
          initialMessage: widget.chat.initialMessage,
          accessMethod: AccessMethod.code,
          requireAuth: false,
          requireApproval: false,
          startMode: StartMode.auto,
          autoStartParticipantCount: 3, // start when host + ~2 invitees are in
          hostDisplayName: hostName,
          proposingDurationSeconds: 86400,
          ratingDurationSeconds: 86400,
          proposingMinimum: 3,
          ratingMinimum: 2,
          enableAiParticipant: false,
          confirmationRoundsRequired: 1,
          showPreviousResults: true,
          propositionsPerUser: 1,
          ratingMode: 'matches',
          matchObjective: 'winner_only',
          allowSkipProposing: true,
          allowSkipRating: true,
          maxCycles: 1,
          isPreview: false,
        );
        await participant.joinChat(
            chatId: real.id, displayName: hostName, isHost: true);
        ref.read(analyticsServiceProvider).logQuickCreateChatCreated(
              fork: 'group', mode: 'real', source: 'invite_from_preview');
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ChatScreen(chat: real, showShareDialog: true)),
        );
        return;
      }

      // OPTIONS path: clone the same option list into a fresh real chat to rank.
      // State.propositions is populated in-session, but an ended chat's bootstrap
      // is empty — fall back to fetching the completed round's propositions.
      var options = state.propositions
          .map((p) => (p.displayContent).trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (options.length < 2) {
        final latest = await chatService.getLatestRoundForChat(widget.chat.id);
        if (latest != null) {
          final props = await ref
              .read(propositionServiceProvider)
              .getPropositionsWithRatings(latest.id,
                  languageCode: ref.read(localeProvider).languageCode);
          options = props
              .map((p) => p.displayContent.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
      if (options.length < 2) {
        throw 'Could not find the options to rank';
      }

      final real = await chatService.createChat(
        name: widget.chat.name,
        initialMessage: widget.chat.initialMessage,
        accessMethod: AccessMethod.code,
        requireAuth: false,
        requireApproval: false,
        startMode: StartMode.manual,
        hostDisplayName: hostName,
        proposingDurationSeconds: 86400,
        ratingDurationSeconds: 86400,
        proposingMinimum: 3,
        ratingMinimum: 2,
        enableAiParticipant: false,
        confirmationRoundsRequired: 1,
        showPreviousResults: true,
        propositionsPerUser: 1,
        ratingMode: 'matches',
        matchObjective: 'full_rank',
        allowSkipProposing: true,
        allowSkipRating: true,
        maxCycles: 1,
        isPreview: false,
      );
      await participant.joinChat(
        chatId: real.id,
        displayName: hostName,
        isHost: true,
      );
      await chatService.seedPrioritizationRound(
        chatId: real.id,
        options: options,
        // No timer: the real shared chat shows no countdown. It finalizes when the
        // host taps "End voting & show results" (host_end_voting). A clock would
        // just confuse invitees ("why is this on a deadline?").
        ratingDurationSeconds: null,
      );
      ref.read(analyticsServiceProvider).logQuickCreateChatCreated(
            fork: 'options', mode: 'real', source: 'invite_from_preview');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(chat: real, showShareDialog: true)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingRealChat = false);
        context.showErrorMessage('Could not create chat: $e');
      }
    }
  }

  Future<void> _advanceToRating() async {
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.advanceToRating(widget.chat);
      if (widget.chat.maxCycles == 1) {
        ref.read(analyticsServiceProvider).logQuickChatAdvanced();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        context.showErrorMessage(l10n.failedToAdvancePhase(e.toString()));
      }
    }
  }

  /// One-time host prompt for a fresh group quick chat (no cycle yet):
  /// "Already have the options?" Seed → seed_prioritization_round → straight
  /// to voting. Dismiss (any path) → start the proposing phase (the group
  /// supplies the ideas). Replaces the old /create fork screen AND the
  /// waiting-state Start tap for quick chats — the dialog always resolves
  /// into a started phase.
  ///
  /// Guarded by [_seedPromptHandled] (one shot per screen mount) and the
  /// no-cycle condition: once resolved a cycle exists, so a refresh or
  /// re-mount can never re-show it. A host who closed the tab mid-dialog
  /// gets it again on return — they never answered.
  void _maybeShowSeedDialog(ChatDetailState state) {
    if (_seedPromptShownFor.contains(widget.chat.id)) return;
    final chat = state.chat ?? widget.chat;
    if (chat.maxCycles != 1 ||
        chat.startMode != StartMode.manual ||
        chat.isPreview) {
      return;
    }
    if (state.myParticipant?.isHost != true) return;
    if (state.currentRound != null) return; // already started or seeded
    if ((state.chat?.endedAt ?? widget.chat.endedAt) != null) return;
    _seedPromptShownFor.add(widget.chat.id);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final analytics = ref.read(analyticsServiceProvider);
      analytics.logSeedDialogShown();
      final question = (state.chat?.displayInitialMessage ??
              widget.chat.displayInitialMessage)
          .trim();
      final result = await SeedOptionsDialog.show(
        context,
        question: question.isNotEmpty ? question : widget.chat.displayName,
      );
      if (!mounted) return;
      final options = result.options;
      if (options != null && options.length >= 2) {
        analytics.logSeedDialogSeeded(optionCount: options.length);
        try {
          await ref.read(chatServiceProvider).seedPrioritizationRound(
                chatId: widget.chat.id,
                options: options,
                // No timer: the real shared chat shows no countdown and
                // finalizes via host_end_voting.
                ratingDurationSeconds: null,
              );
          await ref.read(chatDetailProvider(_params).notifier).refresh();
        } catch (e) {
          if (!mounted) return;
          // Most likely a cycle already exists (stale state / double fire).
          // Refresh to whatever the server says; worst case the host types
          // their options as ideas in proposing.
          ref.read(chatDetailProvider(_params).notifier).refresh();
          final l10n = AppLocalizations.of(context);
          context.showErrorMessage(l10n.failedToAdvancePhase(e.toString()));
        }
      } else {
        analytics.logSeedDialogDismissed(
            method: result.dismissMethod ?? 'barrier_or_back');
        await _startChat();
      }
    });
  }

  /// Host (manual mode) starts the chat: creates the first cycle + proposing
  /// round with no timer. Used by the Start button in the waiting state.
  Future<void> _startChat() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    try {
      final notifier = ref.read(chatDetailProvider(_params).notifier);
      await notifier.startPhase(widget.chat);
      if (widget.chat.maxCycles == 1) {
        ref.read(analyticsServiceProvider).logQuickChatStarted();
      }
      // Intentionally do NOT reset _isStarting on success: the chat is now in
      // proposing, the waiting panel is gone, and keeping it set closes the
      // window where a stale-state re-tap could create a second cycle.
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
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
        state != null) {
      // RT-RACE-DEBUG: log every guard evaluation while phase=rating so
      // we can see hasSkippedRating / hasStartedRating values at the
      // exact moment auto-nav decided. Remove with field decls before
      // merge.
      PerfLogger.start(
        'rt_race.autonav_check',
        chatId: state.chat?.id,
        roundId: currentRound.id,
        payload: {
          'has_rated': state.hasRated,
          'has_started': state.hasStartedRating,
          'has_skipped': state.hasSkippedRating,
          'topmost': _isChatScreenTopmost,
          'last_nav': _lastAutoNavigatedRoundId,
          'will_fire': !state.hasRated &&
              !state.hasStartedRating &&
              !state.hasSkippedRating &&
              _isChatScreenTopmost &&
              _lastAutoNavigatedRoundId != currentRound.id,
        },
      );
    }
    if (currentRound != null &&
        currentRound.phase == RoundPhase.rating &&
        state != null &&
        // Matches mode rates inline in the bottom panel — no full-screen grid.
        state.chat?.ratingMode != 'matches' &&
        !state.hasRated &&
        !state.hasStartedRating &&
        !state.hasSkippedRating &&
        _isChatScreenTopmost &&
        _lastAutoNavigatedRoundId != currentRound.id) {
      _lastAutoNavigatedRoundId = currentRound.id;
      PerfLogger.start('rt_race.autonav_fire',
          chatId: state.chat?.id, roundId: currentRound.id);
      // Use post-frame callback to avoid navigation during build.
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

    // (No auto-open of results when an instant-ranking chat ends — the user
    // reaches the full rankings via the explicit "See full rankings" button or
    // by tapping the winner card. Auto-navigating away was too jarring.)

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
        // Quick chats are sealed single-use tools — no "back to my dashboard".
        // The host's back would go to the create form; a joiner's back lands on
        // /home (the dashboard they should never see). The forward exit is
        // "Create another" at the end. (Browser/system back still works.)
        automaticallyImplyLeading: widget.chat.maxCycles != 1,
        // Quick chats (maxCycles == 1) auto-name the chat after the question,
        // which then duplicates the question already shown in the topic card.
        // Show the OneMind wordmark instead: de-dupes, and brands every shared
        // / screenshotted quick chat. The question stays prominent in the card.
        title: widget.chat.maxCycles == 1
            ? Text(
                'OneMind',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              )
            : Text(
                stateAsync.valueOrNull?.chat?.displayName ??
                    widget.chat.displayName,
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
                // Preview chats never show share/invite (they're solo,
                // ephemeral). Only the real chat created via "Invite others"
                // surfaces the share button.
                final hasInviteCode = widget.chat.inviteCode != null &&
                    !isPersonalCode &&
                    !widget.chat.isPreview;
                final hasDescription =
                    (chat.displayDescription)?.trim().isNotEmpty == true;

                final availableLanguages = chat.translationsEnabled
                    ? chat.translationLanguages
                    : const <String>[];
                final hasLanguageChoice = availableLanguages.length > 1;
                final currentLanguageCode = state.viewingLanguageCode ??
                    ref.read(localeProvider).languageCode;

                // Quick chats (maxCycles == 1) are sealed, single-use tools:
                // one action (Invite) + a glanceable count. No participant
                // roster (random usernames make names meaningless — only the
                // count is useful), and no overflow (pause/delete/leave don't
                // apply to a throwaway chat). See the participants-sheet comment.
                if (chat.maxCycles == 1) {
                  final cs = Theme.of(context).colorScheme;
                  return <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.groups,
                                size: 20, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text('${state.activeParticipantCount}',
                                style: Theme.of(context).textTheme.titleSmall),
                          ],
                        ),
                      ),
                    ),
                    if (hasInviteCode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton.icon(
                          key: const Key('share-button'),
                          onPressed: () {
                            ref
                                .read(analyticsServiceProvider)
                                .logQuickChatShare(source: 'invite');
                            _showQrCode();
                          },
                          icon: const Icon(Icons.ios_share, size: 18),
                          label: const Text('Invite'),
                        ),
                      ),
                  ];
                }

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
                    onPressed: () => _showParticipantsSheet(),
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
        data: (state) {
          _maybeShowSeedDialog(state);
          return AnimatedOpacity(
          opacity: state.isTranslating ? 0.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Column(
          children: [
            // Round status region under the AppBar. Regular chats get the full
            // status bar (round #, phase, participation, timer) framed by
            // phase-colored accent strips; quick-create matches chats (host-
            // controlled, no timer) get a minimal treatment. See
            // _buildTopStatusRegion.
            _buildTopStatusRegion(state),
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
                  // Matches (survey) chats that have ended: the ranked
                  // leaderboard below is the payoff and already crowns #1, so a
                  // consensus "Winner #1" card here would just duplicate it.
                  final isEndedMatches =
                      (state.chat?.endedAt ?? widget.chat.endedAt) != null &&
                          widget.chat.ratingMode == 'matches';

                  // C15 tree mode: the walkable stack REPLACES the blue
                  // winner chain (position 1 opens as options; the user
                  // selects forward). See TreeStackSection.
                  final treeMode = (state.chat?.branchingEnabled ??
                          widget.chat.branchingEnabled) &&
                      state.myParticipant != null &&
                      (state.consensusItems.isNotEmpty ||
                          state.currentRound != null);
                  // Fresh branching chat (no winners yet): the tree section
                  // renders the live ROOT round as position 1's contest.
                  final treeRootLive =
                      treeMode && state.consensusItems.isEmpty;

                  final messageChildren = [
                      // Always show initial message as the opening prompt
                      if (hasInitialMessage) ...[
                        _buildInitialMessageCard(l10n, initialMessage, isHost),
                        const SizedBox(height: 16),
                      ],

                      // Consensus Items (suppressed for ended matches surveys —
                      // the leaderboard below already shows the winner at #1).
                      if (!isEndedMatches && !treeMode)
                        ...state.consensusItems.asMap().entries.expand((entry) {
                        final item = entry.value;
                        final isLastItem = entry.key == state.consensusItems.length - 1;
                        final card = GestureDetector(
                          onTap: () {
                            // Instant / quick chats (one round per cycle, or a
                            // single cycle) skip the cycle-history list and jump
                            // straight to the winning round's full proposition
                            // rankings — there's no multi-cycle history worth
                            // browsing.
                            if (_winnerTapShowsRoundResults) {
                              _openRoundResults(item.proposition.roundId, 1);
                              return;
                            }
                            _pushScreen(
                              MaterialPageRoute(
                                builder: (_) => CycleHistoryScreen(
                                  cycleId: item.cycleId,
                                  convergenceContent: item.displayContent,
                                  convergenceNumber: entry.key + 1,
                                  confirmationRoundsRequired:
                                      widget.chat.confirmationRoundsRequired,
                                  ratingMode: _effectiveRatingMode,
                                  chatId: widget.chat.id,
                                ),
                              ),
                            );
                          },
                          child: MessageCard(
                            label: widget.chat.confirmationRoundsRequired == 1
                                ? l10n.winnerNumber(entry.key + 1)
                                : l10n.convergenceNumber(entry.key + 1),
                            content: item.displayContent,
                            isPrimary: true,
                            isConsensus: !item.isHostOverride,
                            // Convergence videos removed from chat display: cold
                            // users don't expect them and the full-screen wall
                            // buried the propose action. See activation handoff.
                            mediaAbove: null,
                            // Speak-aloud (TTS) button under winners — shown
                            // EVERYWHERE (accessibility: read the winner aloud).
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

                      // C15 tree mode: the walkable stack, starting at
                      // position 1's options. While a ROOT round is still
                      // live (transitional: it predates the branching flip),
                      // its panel stays reachable below the stack so voting
                      // on it isn't hidden.
                      if (treeMode)
                        TreeStackSection(
                          key: ValueKey(
                              'tree_${widget.chat.id}_${state.consensusItems.length}'),
                          chatId: widget.chat.id,
                          myParticipantId: state.myParticipant!.id,
                          positions: state.consensusItems
                              .map((item) => TreePosition(
                                    roundId: item.proposition.roundId,
                                    winnerId: item.proposition.id,
                                  ))
                              .toList(),
                          liveRootPanel: (!treeRootLive &&
                                  state.currentRound != null &&
                                  state.currentRound!.completedAt == null)
                              ? _buildLeaderOrWinnerOrPlaceholder(state)
                              : null,
                          liveRootRoundId: treeRootLive
                              ? state.currentRound!.id
                              : null,
                          liveRootPhase: treeRootLive
                              ? state.currentRound!.phase.name
                              : null,
                        )
                      else
                        // Inline Current Leader (rating phase), Previous Winner, or placeholder
                        _buildLeaderOrWinnerOrPlaceholder(state),
                  ];

                  // Tree mode anchors the column to the BOTTOM: the inline
                  // composer/duel sits at the bottom of the screen on open
                  // (chat idiom — reverse:true already handles the overflow
                  // case; bottomCenter handles short content).
                  return Align(
                    alignment: treeMode
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
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

            // Bottom Action Area. Hidden for a fresh branching chat — the
            // tree section renders the root round's feed/composer/duel
            // inline, and the classic bottom panel would duplicate it.
            if (!((state.chat?.branchingEnabled ??
                        widget.chat.branchingEnabled) &&
                    state.consensusItems.isEmpty &&
                    state.myParticipant != null &&
                    state.currentRound != null))
              _buildBottomArea(state),
          ],
        ));
        },
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
    // Matches (survey) mode: the question IS the content, so drop the chat-era
    // "Initial Message" label — it reads as jargon on a one-shot survey.
    final isMatches = widget.chat.ratingMode == 'matches';
    final Widget card = MessageCard(
      label: isMatches ? null : l10n.initialMessageLabel,
      content: initialMessage,
      isPrimary: true,
      // Convergence videos removed from chat display. See activation handoff.
      mediaAbove: null,
      // Quick chats (maxCycles == 1) hide the speak-aloud button — it's chat-era
      // chrome that doesn't belong on a lean one-shot decision.
      trailing: widget.chat.maxCycles == 1
          ? null
          : TtsButton(
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
        title: Text(widget.chat.confirmationRoundsRequired == 1
            ? l10n.deleteWinnerTitle(number)
            : l10n.deleteConsensusTitle(number)),
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

  /// The top status region. Quick-create matches chats (host-controlled, no
  /// timer) are kept minimal — the round #, timer, and participation bar are
  /// noise there (single cycle, no countdown, and completion is already on the
  /// host's "Show results" button + the per-match counter). During PROPOSING we
  /// show a lean "Collecting ideas" label so the group knows ideas come before
  /// voting; RATING is self-evident from the voting panel, so nothing. Every
  /// other chat keeps the full bar framed by phase-colored accent strips.
  Widget _buildTopStatusRegion(ChatDetailState state) {
    final round = state.currentRound;
    final chat = state.chat ?? widget.chat;
    final isMinimal = chat.ratingMode == 'matches' &&
        round != null &&
        round.phaseEndsAt == null &&
        (round.phase == RoundPhase.proposing ||
            round.phase == RoundPhase.rating);
    if (isMinimal) {
      return round!.phase == RoundPhase.proposing
          ? _buildMinimalProposingLabel()
          : const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhaseAccentStrip(phase: round?.phase),
        _buildTopPhaseBar(state),
        PhaseAccentStrip(phase: round?.phase),
      ],
    );
  }

  /// Lean phase anchor for the quick-create group chat's proposing phase.
  Widget _buildMinimalProposingLabel() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Collecting ideas',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
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
    // Read directly from the server-computed denormalized column. This
    // is maintained by triggers in 20260502170000 — the rounds row is
    // the single source of truth, so all viewers converge to the same
    // value as the rounds realtime payload arrives. Replaces the prior
    // local computation which built the percent from N independently-
    // delivered realtime streams (propositions / round_skips /
    // rating_skips / affirmations / grid_rankings) and drifted across
    // viewers when any one stream lagged or dropped events.
    //
    // Falls back to local computation only if the server hasn't sent a
    // value yet (e.g. very old rounds pre-migration backfill, or a
    // client that received a rounds payload missing the new column).
    int? participationPercent = currentRound.participationPercent;
    // Matches rating is the exception to the denormalized column: that column
    // is grid-based (counts grid_rankings/skips) so it sits at 0 for pairwise
    // voting AND never moves as pairwise votes/completions arrive. Use the
    // per-rater matches progress instead — it's kept live by the
    // rating_completions realtime subscription (no reload needed).
    if (isRating && chat.ratingMode == 'matches') {
      participationPercent = state.ratingProgressPercent;
    }
    if (participationPercent == null) {
      if (isProposing) {
        final donePIds = <int>{
          ...state.propositions
              .where((p) => p.participantId != null && !p.isCarriedForward)
              .map((p) => p.participantId!),
          ...state.participantsWhoSkippedProposing,
          ...state.participantsWhoAffirmed,
        };
        participationPercent = state.participants.isNotEmpty
            ? (donePIds.length * 100 / state.participants.length).round()
            : 0;
      } else {
        participationPercent = state.ratingProgressPercent;
      }
    }
    // RT-RACE-DEBUG: log every change to the bar value, with phase + round.
    // Compares against previous logged value to skip rebuild noise.
    if (participationPercent != _rtRaceLastBarPercent ||
        currentRound.phase != _rtRaceLastBarPhase ||
        currentRound.id != _rtRaceLastBarRoundId) {
      _rtRaceLastBarPercent = participationPercent;
      _rtRaceLastBarPhase = currentRound.phase;
      _rtRaceLastBarRoundId = currentRound.id;
      PerfLogger.start(
        'rt_race.bar_render',
        chatId: chat.id,
        roundId: currentRound.id,
        payload: {
          'percent': participationPercent,
          'phase': currentRound.phase.name,
          'props': state.propositions.length,
          'participants': state.participants.length,
          'rating_skip_count': state.ratingSkipCount,
          'has_skipped_rating': state.hasSkippedRating,
        },
      );
    }
    // When the chat is host-paused mid-round, swap the timer for the
    // "Paused" indicator (matching the in-panel host-paused fallback).
    final isHostPaused = chat.hostPaused;
    // C15 tree mode: round numbers and root-round participation are
    // meaningless across parallel subrounds — keep phase tag + countdown.
    final isTree = chat.branchingEnabled;
    return RoundPhaseBar(
      roundNumber: currentRound.customId,
      showRoundNumber: !isTree,
      isProposing: isProposing,
      phaseEndsAt: isHostPaused ? null : currentRound.phaseEndsAt,
      onPhaseExpired: _onPhaseExpired,
      participationPercent: isTree ? null : participationPercent,
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
            ? () {
                // Instant ranking / quick chats: skip cycle history, go
                // straight to the full rankings of the just-completed round.
                if (_winnerTapShowsRoundResults) {
                  final state =
                      ref.read(chatDetailProvider(_params)).valueOrNull;
                  final completed = _completedRoundFromState(state);
                  if (completed != null) {
                    _openRoundResults(
                        completed.roundId, completed.roundNumber);
                    return;
                  }
                }
                _pushScreen(
                  MaterialPageRoute(
                    builder: (_) => CycleHistoryScreen(
                      cycleId: currentCycleId,
                      convergenceContent: '...',
                      convergenceNumber: convergenceNumber,
                      showOngoingPlaceholder: false,
                      confirmationRoundsRequired:
                          widget.chat.confirmationRoundsRequired,
                      ratingMode: _effectiveRatingMode,
                      chatId: widget.chat.id,
                    ),
                  ),
                );
              }
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
  /// Manual quick-chat host's "advance proposing -> rating" control. Quick
  /// chats (maxCycles==1) render a custom proposing UI that doesn't use
  /// ProposingStatePanel — where the classic advance button lives — so the
  /// host's advance button has to be wired here, or the host has no way to
  /// move a group-fork chat from proposing to voting. Uses a high-contrast
  /// FilledButton (not the near-invisible disabled tonal button) and enables
  /// once there are >=2 ideas (matches voting needs at least one pair).
  /// Renders nothing for non-quick chats, non-hosts, auto/timer chats, or
  /// outside the proposing phase.
  Widget _buildQuickChatHostAdvance(ChatDetailState state) {
    final chat = state.chat ?? widget.chat;
    if (chat.maxCycles != 1) return const SizedBox.shrink();
    final isHost = state.myParticipant?.isHost == true;
    final isManual = chat.startMode == StartMode.manual && !chat.isPreview;
    final inProposing = state.currentRound?.phase == RoundPhase.proposing;
    if (!isHost || !isManual || !inProposing) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ideaCount =
        state.propositions.where((p) => !p.isCarriedForward).length;
    final ready = ideaCount >= 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // TODO(i18n): move this hint into the arb files.
              child: Text(
                ideaCount == 0
                    ? 'Add an idea, or tap Invite so the group can — 2 needed to start voting'
                    : 'Tap Invite to get more ideas — $ideaCount so far, 2 needed to start voting',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('quick-chat-advance-to-rating-button'),
              onPressed: ready ? () => _advanceToRating() : null,
              icon: const Icon(Icons.how_to_vote),
              label: Text(l10n.endProposingStartRating),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderOrWinnerOrPlaceholder(ChatDetailState state) {
    // Ended instant-ranking chat: never show the "waiting for participants"
    // block (the chat is finished). Show the winner card when we still have it
    // in-session; otherwise nothing — the bottom ended panel carries the
    // "See full rankings" / "Invite others" actions.
    final isEnded = (state.chat?.endedAt ?? widget.chat.endedAt) != null;
    if (isEnded) {
      // Matches mode: the full ranked leaderboard is the payoff — render it
      // here in the body (scrolls with the page, full height for any option
      // count). #1 carries the trophy, so the separate winner card is dropped.
      if (widget.chat.ratingMode == 'matches') {
        return _buildEndedLeaderboard(state);
      }
      return state.previousRoundWinners.isNotEmpty
          ? _buildInlinePreviousWinner(state)
          : const SizedBox.shrink();
    }
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
      // Grid mode: replace the cards with the inline Start-Rating action.
      if (state.chat?.ratingMode != 'matches') {
        return _buildInlineRatingAction(state);
      }
      // Matches mode: the pairwise voting panel lives HERE in the chat scroll
      // (so it scrolls with the conversation, like the proposing input), and
      // the bottom panel goes empty. This also avoids the old contradiction
      // where the scroll showed "your proposition / Waiting for next phase"
      // while the user was actively voting.
      final myPid = state.myParticipant?.id;
      if (myPid != null && !state.hasSkippedRating) {
        return _buildMatchesRatingPanel(state, myPid);
      }
      // Skipped → shared skipped/waiting indicator. (hasRated stays false in
      // matches mode, so _buildInlineRatingAction lands on the skipped branch.)
      if (state.hasSkippedRating) {
        return _buildInlineRatingAction(state);
      }
      // No participant id (edge) — show context, not the grid action.
      if (state.previousRoundWinners.isNotEmpty) {
        return _buildInlinePreviousWinner(state);
      }
      return _buildTopCandidatePlaceholder();
    }
    // Quick-chat host during proposing: share-first base layer. The host's
    // job in this phase is recruiting, not typing — so the share block is
    // the persistent primary and their own input sits behind an "Add your
    // own idea" toggle. (H-CONVENER-UI: we used to show the convener the
    // contributor's screen; chat 465 bailed on exactly that.)
    {
      final qcChat = state.chat ?? widget.chat;
      final isQuickHostProposing = qcChat.maxCycles == 1 &&
          qcChat.startMode == StartMode.manual &&
          !qcChat.isPreview &&
          state.myParticipant?.isHost == true &&
          state.currentRound?.phase == RoundPhase.proposing;
      if (isQuickHostProposing) {
        return _buildQuickHostProposing(state);
      }
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

  /// Matches (pairwise) voting panel, rendered inline in the chat scroll so
  /// it scrolls with the conversation. Self-excludes the user's own
  /// propositions — unless that leaves fewer than 2 (conditional
  /// self-inclusion: a 2-prop round is votable by everyone, own idea
  /// included). On exhaustion marks the rater complete + refreshes so the
  /// round-status bar and early-advance see them as done.
  Widget _buildMatchesRatingPanel(ChatDetailState state, int myParticipantId) {
    final chat = state.chat ?? widget.chat;
    final nonOwn = state.propositions
        .where((p) => p.participantId != myParticipantId)
        .toList();
    final rateable = nonOwn.length >= 2 ? nonOwn : state.propositions;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MatchesRatingPanel(
        key: ValueKey('matches_${state.currentRound!.id}'),
        roundId: state.currentRound!.id,
        participantId: myParticipantId,
        rateable: rateable,
        objective: chat.matchObjective == 'full_rank'
            ? MatchObjective.fullRank
            : MatchObjective.winnerOnly,
        onSkip: state.canSkipRating ? _skipRating : null,
        onDone: () async {
          await ref.read(propositionServiceProvider).markRatingComplete(
                roundId: state.currentRound!.id,
                participantId: myParticipantId,
              );
          if (chat.maxCycles == 1) {
            ref.read(analyticsServiceProvider).logQuickChatVoteDone();
          }
          // Instant finalize: nudge process-timers so a solo (or last) rater sees
          // results immediately instead of waiting for the next 60s cron tick.
          await ref.read(chatServiceProvider).triggerProcessTimers();
          ref.read(chatDetailProvider(_params).notifier).refresh(silent: true);
        },
      ),
    );
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
    final chat = state.chat ?? widget.chat;
    final myProps = state.myPropositions
        .where((p) => !p.isCarriedForward)
        .toList();
    if (myProps.isEmpty) return const SizedBox.shrink();
    // The manual quick-chat host controls phase transitions themselves (the
    // advance button below is their cue), so "Waiting for next phase" is
    // misleading for them — nothing auto-advances. Only non-host participants
    // are genuinely waiting on the host.
    final isManualHost = chat.maxCycles == 1 &&
        state.myParticipant?.isHost == true &&
        chat.startMode == StartMode.manual &&
        !chat.isPreview;
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
        if (!isManualHost) ...[
          const SizedBox(height: 8),
          Text(
            l10n.waitingForNextPhase,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

  /// Quick-chat host proposing: persistent share block on top, then the
  /// host's own state below it (submitted cards / skipped indicator / the
  /// input behind an "Add your own idea" toggle).
  Widget _buildQuickHostProposing(ChatDetailState state) {
    final newSubs =
        state.myPropositions.where((p) => !p.isCarriedForward).length;
    Widget below;
    if (newSubs > 0) {
      below = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 64),
          child: _buildSubmittedPropCards(state),
        ),
      );
    } else if (state.hasSkipped) {
      below = _buildInlineSkippedIndicator();
    } else if (_inputInChatScroll(state)) {
      below = _hostInputExpanded
          ? _buildR1InlineInput(state)
          : Center(
              child: TextButton.icon(
                key: const Key('host-add-own-idea'),
                onPressed: () => setState(() => _hostInputExpanded = true),
                icon: const Icon(Icons.edit_note, size: 20),
                label: const Text('Add your own idea'),
              ),
            );
    } else {
      below = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          below,
        ],
      ),
    );
  }

  /// The persistent invite block — visible link (tap = copy) + native share.
  /// Mirrors InviteShareSheet's copy/share semantics + analytics, without the
  /// modal: share is the base state of the host's proposing screen, so there
  /// is nothing to interrupt.
  Widget _quickHostShareBlock(
    ChatDetailState state, {
    String title = 'Invite your group to add ideas',
  }) {
    final chat = state.chat ?? widget.chat;
    final code = widget.chat.inviteCode;
    if (code == null || chat.accessMethod != AccessMethod.code) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final url = '${EnvConfig.webAppUrl}/join/$code';
    final analytics = ref.read(analyticsServiceProvider);
    final chatName = state.chat?.displayName ?? widget.chat.displayName;

    return Container(
      key: const Key('quick-host-share-block'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'No account needed — they just open the link.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          // Tap-to-copy link.
          InkWell(
            key: const Key('quick-host-copy-link'),
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              analytics.logInviteShared(
                  chatId: widget.chat.id.toString(), shareMethod: 'copy');
              await Clipboard.setData(ClipboardData(text: url));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied')),
                );
              }
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy, size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('quick-host-share-button'),
              onPressed: () async {
                analytics.logInviteShared(
                    chatId: widget.chat.id.toString(),
                    shareMethod: 'share_sheet');
                try {
                  await Share.share(
                    'Rank these with me: $chatName\n$url',
                    subject: chatName,
                  );
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Share link'),
            ),
          ),
        ],
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
    final isHost = state.myParticipant?.isHost == true;
    // Manual mode = the host starts the chat by hand (no auto-start countdown).
    final isManual = chat.startMode == StartMode.manual;
    final autoStart = chat.autoStartParticipantCount ?? 3;
    final remaining = autoStart - state.participants.length;
    final waitingCount = remaining > 0 ? remaining : 0;
    final String waitingMessage = isManual
        ? (isHost
            ? "Invite your group, then start — everyone here can add ideas."
            : 'Waiting for the host to start.')
        : l10n.waitingForMoreParticipants(waitingCount);
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
              waitingMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            // Manual mode: the host starts on their own schedule. (Participant
            // count shown so they know who's in before starting.)
            if (isManual && isHost) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('host-start-chat-button'),
                  onPressed: _isStarting ? null : _startChat,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Start (${state.participants.length} here)'),
                ),
              ),
            ],
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
      hideTts: false, // TTS under winners shown everywhere (accessibility)
      roundNumber: (state.currentRound?.customId ?? 2) - 1,
      // Live chat shows "Current Leader" (status), not "Round N Winner" — the
      // round number is noise here; it's kept in the cycle-history view where
      // per-round progression is the point. "Your affirmation" still overrides
      // after the user affirms.
      labelOverride: affirmedThisRound
          ? l10nForLabel.yourAffirmation
          : l10nForLabel.currentLeader,
      onWinnerIndexChanged: (index) =>
          setState(() => _currentWinnerIndex = index),
      // Instant ranking / quick chats: tapping the card jumps straight to the
      // full rankings of the just-completed round (skips cycle history).
      onTap: _winnerTapShowsRoundResults
          ? () => _resolveAndOpenResults(state)
          : (state.currentCycle != null
              ? () {
                  _pushScreen(
                    MaterialPageRoute(
                      builder: (_) => CycleHistoryScreen(
                        cycleId: state.currentCycle!.id,
                        convergenceContent: state
                                .previousRoundWinners.first.displayContent ??
                            '',
                        convergenceNumber: state.consensusItems.length + 1,
                        confirmationRoundsRequired:
                            widget.chat.confirmationRoundsRequired,
                        ratingMode: _effectiveRatingMode,
                        chatId: widget.chat.id,
                      ),
                    ),
                  );
                }
              : null),
      // "See full rankings" button under the card — for instant-ranking AND
      // quick chats with a completed round to show.
      onSeeRankings: (_winnerTapShowsRoundResults &&
              state.previousRoundWinners.isNotEmpty)
          ? () => _resolveAndOpenResults(state)
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
            // Only Back here — the user already chose "Yes, I have a better
            // idea", so Skip would contradict that. Skip lives on the Yes/No
            // question instead.
            Center(
              child: OutlinedButton(
                key: const Key('inline-alternative-back-button'),
                onPressed: disabledByMutation
                    ? null
                    : () => setState(() => _alternativeMode = false),
                child: Text(l10n.gateBack),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                l10n.alternativeMicrocopyNoSkip,
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

    // Gate: winner card + "Can you think of something better?" Yes/No.
    // Yes -> propose an alternative (textfield). No -> affirm (back the
    // current leader). Skip (sit out the round) is de-emphasized below the
    // question — NOT in the alternative textfield, where it would contradict
    // having just said "yes, I have a better idea".
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          winnerCard,
          const SizedBox(height: 12),
          Center(
            child: Text(
              l10n.gateBetterQuestion,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
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
                  key: const Key('gate-yes-button'),
                  onPressed: disabledByMutation
                      ? null
                      : () => setState(() => _alternativeMode = true),
                  child: Text(l10n.yes),
                ),
                OutlinedButton(
                  key: const Key('gate-no-button'),
                  onPressed: canAffirmInline && !disabledByMutation
                      ? _affirmRound
                      : null,
                  child: Text(l10n.no),
                ),
              ],
            ),
          ),
          if (chat.allowSkipProposing) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                key: const Key('gate-skip-button'),
                onPressed: (state.canSkip && !disabledByMutation)
                    ? _skipProposing
                    : null,
                // Muted (not primary teal) so "Skip" reads as the secondary
                // escape under Yes/No — and consistent with the matches Skip.
                style: TextButton.styleFrom(
                  foregroundColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                child: Text(l10n.skip),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Ended-state bottom panel for quick-create instant-ranking chats.
  /// Grid mode: "This chat has ended" + a "See full rankings" action. Matches
  /// mode renders the ranked leaderboard in the chat BODY (the payoff, with
  /// room to scroll — see [_buildLeaderOrWinnerOrPlaceholder]), so the panel
  /// only carries the preview "Create a real chat to share" CTA; a real ended
  /// matches chat needs no bottom panel at all.
  Widget _buildEndedStatePanel(ChatDetailState state) {
    final theme = Theme.of(context);
    final isPreview = widget.chat.isPreview;
    final isMatches = widget.chat.ratingMode == 'matches';

    // Real (non-preview) matches chat: the ranked leaderboard is in the body.
    // Offer next steps so a finished decision isn't a dead end — start a new
    // chat (loops back into /create), and share the result for anyone who
    // wants to revisit the outcome.
    if (isMatches && !isPreview) {
      final hasCode = widget.chat.inviteCode != null;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('ended-create-new-chat'),
              onPressed: () {
                ref.read(analyticsServiceProvider).logQuickChatCreateAnother();
                // Clear the D37 sealed-loop guard FIRST — this is the one
                // deliberate forward exit out of the quick-chat loop, so /create
                // must not be bounced back to the finished chat.
                activeQuickChatId.value = null;
                context.go('/create');
              },
              icon: const Icon(Icons.add),
              label: const Text('Create a new chat'),
            ),
            if (hasCode) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('ended-share-result'),
                onPressed: () {
                  ref
                      .read(analyticsServiceProvider)
                      .logQuickChatShare(source: 'result');
                  _showQrCode();
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Share result'),
              ),
            ],
          ],
        ),
      );
    }

    // Group path (agented preview): invitees PROPOSE ideas first, then rank — so the
    // copy differs from the options path (where the same list is just re-ranked).
    final isGroup = widget.chat.enableAgents;
    // "Create a real chat to share" everywhere (matches the create-screen wording)
    // so it's unmistakable this starts a NEW, real chat — not people joining this
    // demo. The helper spells out "fresh chat" to kill the "same chat" confusion.
    const inviteLabel = 'Create a real chat to share';
    final inviteHelper = isGroup
        ? "Starts a fresh shared chat — your group adds their own ideas, then "
            "everyone ranks. You'll see the winner here."
        : "Starts a fresh chat with these same options — send the link and your "
            "group ranks them. You'll see the winner here when everyone's voted.";

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grid mode keeps the "ended + see full rankings" affordance in the
          // panel; matches mode shows the leaderboard in the body instead.
          if (!isMatches) ...[
            Text(
              'This chat has ended',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              // Resolver falls back to a DB lookup — an ended chat's bootstrap is
              // empty, so state alone has no completed round.
              onPressed: () => _resolveAndOpenResults(state),
              icon: const Icon(Icons.leaderboard),
              label: const Text('See full rankings'),
            ),
          ],
          if (isPreview) ...[
            if (!isMatches) const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _isCreatingRealChat
                  ? null
                  : () => _createRealChatFromPreview(state),
              icon: _isCreatingRealChat
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add),
              label: Text(_isCreatingRealChat ? 'Creating…' : inviteLabel),
            ),
            const SizedBox(height: 8),
            Text(
              inviteHelper,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Ended matches chat → the ranked leaderboard, rendered in the chat BODY so
  /// it scrolls with the page and has room for any number of options (no nested
  /// scroll, no height cap). The same payoff the /try demo ends on. Loads (and
  /// caches) the ranking lazily; spinner while resolving, leaderboard once ready.
  Widget _buildEndedLeaderboard(ChatDetailState state) {
    final theme = Theme.of(context);
    _endedRankingFuture ??= _loadEndedRanking(state);
    return FutureBuilder<List<Proposition>>(
      future: _endedRankingFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final ranked = snap.data ?? const <Proposition>[];
        if (ranked.isEmpty) {
          // Couldn't resolve the round from state or DB — fall back to the
          // full-screen results loader rather than showing nothing.
          return Center(
            child: FilledButton.icon(
              onPressed: () => _resolveAndOpenResults(state),
              icon: const Icon(Icons.leaderboard),
              label: const Text('See full rankings'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                'How the group ranked them',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            RankedLeaderboard(
              entries: [for (final p in ranked) p.displayContent],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCurrentPhasePanel(ChatDetailState state) {
    // Use fresh chat from state for dynamic fields (schedulePaused), fall back to widget.chat
    final chat = state.chat ?? widget.chat;
    final isHost = state.myParticipant?.isHost == true;

    // Ended state (quick-create instant ranking): once the single round
    // resolves and the chat ends, there's nothing left to rate or submit.
    // Replace the rating panel / text input with an ended banner that points
    // to the full rankings (and, for previews, an "invite others" CTA).
    if (chat.endedAt != null) {
      return _buildEndedStatePanel(state);
    }

    // Host pause replaces the entire bottom panel — there are no actions
    // available while paused, so we don't render the misleading
    // "waiting for participants" / disabled-textfield UI underneath.
    // The RoundPhaseBar already lives under the AppBar (since the May 2026
    // redesign in 3db3946) and shows "Paused" via isPaused=true, so we
    // just return the banner here — no duplicate bar above it.
    if (chat.hostPaused) {
      return HostPausedBanner(
        isHost: isHost,
        onResume: isHost
            ? () => ref
                .read(chatDetailProvider(_params).notifier)
                .resumeChat()
            : null,
      );
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
        // Quick-chat manual host: the advance control is bottom-anchored here
        // (consistent with the rating-phase HostEndVotingBar) instead of inline
        // in the scroll. The proposing INPUT stays in the scroll; the classic
        // ProposingStatePanel is gateMode (renders nothing) for quick chats.
        if (chat.maxCycles == 1 &&
            isHost &&
            chat.startMode == StartMode.manual &&
            !chat.isPreview) {
          return _buildQuickChatHostAdvance(state);
        }
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
          // Manual mode only: the host drives proposing→rating (no timer, no
          // auto-advance). Null for auto/timer chats so the button stays hidden
          // there, as before.
          onAdvancePhase: (chat.startMode == StartMode.manual && !chat.isPreview)
              ? () => _advanceToRating()
              : null,
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
        // Matches (pairwise) mode renders its voting panel in the chat scroll
        // (see _buildLeaderOrWinnerOrPlaceholder) so it scrolls with the
        // conversation, like the proposing input. The bottom panel stays
        // empty so we don't duplicate the panel in a fixed footer.
        if (chat.ratingMode == 'matches') {
          // Real quick-create chats have no timer and don't auto-seal — the host
          // ends voting here. Preview chats (solo/agents) auto-finalize, so no bar.
          final isRealQuickCreate =
              chat.maxCycles != null && !chat.isPreview;
          if (isHost && isRealQuickCreate) {
            // Whether the host let the group propose or seeded the options
            // themselves, voting only matters once others arrive — so keep the
            // invite block in front of them here, above the end-voting bar.
            // (The seed-options path never passes through the proposing screen
            // where the share block otherwise lives.)
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _quickHostShareBlock(
                  state,
                  title: 'Invite your group to vote',
                ),
                const SizedBox(height: 12),
                HostEndVotingBar(
                  done: state.matchesDoneRaters,
                  eligible: state.matchesEligibleRaters,
                  isEnding: _isEndingVoting,
                  onEndVoting: () => _endVoting(state),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        }
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
  /// Lets the user rename themselves from the participants leaderboard.
  /// Mirrors the home-screen pencil (WelcomeHeader): updates the auth
  /// display_name, which a DB trigger propagates to all the user's
  /// participant rows; then refreshes the chat so the leaderboard updates.
  void _showEditNameDialog(String currentName) {
    final controller = TextEditingController(text: currentName);
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editName),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: l10n.enterYourName),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) {
              _saveDisplayName(name);
              Navigator.pop(dialogContext);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _saveDisplayName(name);
                Navigator.pop(dialogContext);
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDisplayName(String name) async {
    await ref.read(authServiceProvider).setDisplayName(name);
    ref.invalidate(authDisplayNameProvider);
    // Reload the chat so the leaderboard reflects the DB-synced name.
    await ref.read(chatDetailProvider(_params).notifier).refresh(silent: true);
  }

  void _showParticipantsSheet() {
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
                    // intentionally removed: naming individual stragglers
                    // creates social pressure that works against letting
                    // each voice contribute at its own pace.
                    // RECONSIDERED 2026-06 for the host's "when do I end
                    // voting?" decision and kept OUT on purpose: the host
                    // needs the COUNT ("3 of 5 voted", shown on the
                    // end-voting bar), not WHO — which two people are
                    // outstanding only matters for nudging, which is the
                    // pressure we avoid. Do not add a who's-done roster.
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
                          final isMe =
                              p.id == currentState?.myParticipant?.id;
                          // "Done" tag: who has acted this phase — rated or
                          // skipped during rating, proposed or skipped or
                          // affirmed during proposing. Restored per request
                          // (helps see who still needs to act, esp. during
                          // voting). Must stay in sync with the proposing
                          // participation-percent sets above. Reads the
                          // watched currentState (not a sheet-open snapshot)
                          // so chips update live while the sheet is open.
                          final phase = currentState?.currentRound?.phase;
                          final bool isDone = currentState != null &&
                              (phase == RoundPhase.rating
                                  ? (currentState.participantsWhoRated
                                          .contains(p.id) ||
                                      currentState.participantsWhoSkippedRating
                                          .contains(p.id))
                                  : phase == RoundPhase.proposing
                                      ? (currentState.participantsWhoProposed
                                              .contains(p.id) ||
                                          currentState
                                              .participantsWhoSkippedProposing
                                              .contains(p.id) ||
                                          currentState.participantsWhoAffirmed
                                              .contains(p.id))
                                      : false);
                          return ListTile(
                            leading: CircleAvatar(child: Text(rankText)),
                            title: isMe
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(p.displayName,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 16),
                                        tooltip: l10n.editName,
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                        onPressed: () =>
                                            _showEditNameDialog(p.displayName),
                                      ),
                                    ],
                                  )
                                : Text(p.displayName),
                            // Explicit two-state status: filled "Done" vs a
                            // quiet hollow "Pending" in the same slot, so
                            // not-done is visible information rather than an
                            // absent tag (and rows don't shift on completion).
                            // No chip at all outside an active phase —
                            // "Pending" is meaningless in waiting/ended.
                            trailing: isDone
                                ? Chip(
                                    avatar: Icon(Icons.check_circle,
                                        size: 16,
                                        color: theme.colorScheme.primary),
                                    label: Text(l10n.done),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    labelStyle: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.12),
                                    side: BorderSide.none,
                                  )
                                : (phase == RoundPhase.proposing ||
                                        phase == RoundPhase.rating)
                                    ? Chip(
                                        avatar: Icon(
                                            Icons.radio_button_unchecked,
                                            size: 16,
                                            color: theme.colorScheme.outline),
                                        label: Text(l10n.pendingTag),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        labelStyle: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.outline,
                                        ),
                                        backgroundColor: Colors.transparent,
                                        side: BorderSide(
                                            color: theme
                                                .colorScheme.outlineVariant),
                                      )
                                    : null,
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

  void _showQrCode({bool auto = false}) {
    if (widget.chat.inviteCode == null) return;
    final chatName = ref.read(chatDetailProvider(_params)).valueOrNull?.chat?.displayName ?? widget.chat.displayName;

    // Quick-create chats (maxCycles == 1) get the conversion-focused link-first
    // sheet; other chats keep the QR dialog (useful for in-person demos).
    if (widget.chat.maxCycles == 1) {
      InviteShareSheet.show(
        context,
        chatName: chatName,
        inviteCode: widget.chat.inviteCode!,
        chatId: widget.chat.id.toString(),
        auto: auto,
      );
      return;
    }

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
