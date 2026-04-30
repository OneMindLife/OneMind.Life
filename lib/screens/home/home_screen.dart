import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/error_view.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../config/router.dart';
import '../../providers/providers.dart';
import '../../services/active_audio.dart';
import '../../utils/dashboard_sort.dart';
import '../chat/chat_screen.dart';
import '../create/create_chat_wizard.dart';
import 'all_chats_screen.dart';
import '../legal/legal_documents_dialog.dart';
import '../../widgets/chat_dashboard_card.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/home_banner_carousel.dart';
import '../../widgets/welcome_header.dart';

const String _donateUrl = 'https://buy.stripe.com/aFa6oHbXedYZg1xap4b3q01';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.returnToChatId});

  /// If set, auto-navigate to this chat on mount (e.g. after Stripe checkout redirect)
  final int? returnToChatId;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<Chat>? _approvedChatSubscription;
  bool _hasPlayedEntrance = false;
  bool _olderChatsExpanded = false;
  Timer? _tickTimer;

  /// True while the first-time auto-join into the official OneMind chat is
  /// in flight. Used to suppress the "Looking for more chats" discovery
  /// empty state so new users don't see it flash for a beat before their
  /// auto-joined OneMind chat appears.
  bool _isAutoJoiningOfficial = false;

  // Invite code state removed — joining now handled via action picker

  @override
  void initState() {
    super.initState();
    // 1-second tick for countdown refresh + re-sort
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Listen for approved join requests to auto-open the chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupApprovedChatListener();
      _handleReturnToChat();
      _ensureJoinedOfficialChat();
      ref.read(pushNotificationServiceProvider).initialize(
        onTapChatId: (chatId) {
          // A push notification was tapped for a specific chat. Use
          // go_router to reset the stack to Home with ?chat_id=X —
          // HomeScreen picks that up in initState and auto-opens the
          // chat, popping any chat that was on top.
          if (!mounted) return;
          ref.read(routerProvider).go('/?chat_id=$chatId');
        },
      );
    });
  }

  /// First-time-only auto-join into the official OneMind chat.
  /// Gated by a SharedPreferences flag so users who later leave the
  /// chat are not forcibly re-added on subsequent home visits.
  Future<void> _ensureJoinedOfficialChat() async {
    final tutorialService = ref.read(tutorialServiceProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final isFirstVisit = !tutorialService.hasAutoJoinedOfficial;
    analytics.logHomeScreenViewed(isFirstVisit: isFirstVisit);
    if (!isFirstVisit) return;
    // Suppress the discover-more-chats empty state while the join is in
    // flight — otherwise a fresh user sees it flash for ~1s before the
    // OneMind chat card replaces it.
    if (mounted) setState(() => _isAutoJoiningOfficial = true);
    Chat? officialChat;
    var joinSucceeded = false;
    try {
      final chatService = ref.read(chatServiceProvider);
      officialChat = await chatService.getOfficialChat();
      if (officialChat != null) {
        await ref
            .read(participantServiceProvider)
            .joinPublicChat(chatId: officialChat.id);
        joinSucceeded = true;
      }
      await tutorialService.markOfficialAutoJoined();
      // Refresh the chat list so the official chat appears immediately.
      // Awaited so _isAutoJoiningOfficial stays true until the refreshed
      // list is on screen — otherwise the user briefly sees the empty
      // "Looking for more chats" state between join and list update.
      if (mounted) {
        await ref.read(myChatsProvider.notifier).refresh();
      }
      // First-time visitors land directly inside the official chat instead
      // of staring at a single-card list. Skip when the user already has
      // another joined chat — they arrived here from a /join/CODE flow and
      // auto-redirecting to the official chat would hijack them away from
      // the one they actually wanted to join.
      if (mounted && officialChat != null && widget.returnToChatId == null) {
        final chatsState = ref.read(myChatsProvider).valueOrNull;
        final hasOtherChats = chatsState?.chats
                .any((c) => c.id != officialChat!.id) ??
            false;
        if (!hasOtherChats) {
          analytics.logOfficialChatAutoOpened(chatId: officialChat.id.toString());
          _navigateToChat(context, ref, officialChat);
        }
      }
    } catch (_) {
      // Best-effort: the user can still join the official chat manually.
    } finally {
      analytics.logOfficialChatAutoJoined(
        succeeded: joinSucceeded,
        chatId: officialChat?.id.toString(),
      );
      if (mounted) setState(() => _isAutoJoiningOfficial = false);
    }
  }

  void _setupApprovedChatListener() {
    _approvedChatSubscription?.cancel();
    _approvedChatSubscription =
        ref.read(myChatsProvider.notifier).approvedChatStream.listen((chat) {
      if (mounted) {
        _navigateToChat(context, ref, chat);
      }
    });
  }

  /// Auto-navigate to a chat after returning from Stripe checkout OR
  /// after a push-notification tap routed the user to /?chat_id=N.
  ///
  /// Pops any existing pushed routes first (so a notification tap while
  /// chat A is open replaces chat A with chat B rather than stacking
  /// chat B on top).
  void _handleReturnToChat() async {
    final chatId = widget.returnToChatId;
    if (chatId == null) return;

    // Clear any imperatively-pushed ChatScreen on top so the new chat
    // replaces (not stacks on top of) whatever was previously open.
    final navigator = Navigator.of(context);
    while (navigator.canPop()) {
      navigator.pop();
    }

    // Wait for chat list to load, then navigate
    final chatService = ref.read(chatServiceProvider);
    try {
      final chat = await chatService.getChatById(chatId);
      if (mounted && chat != null) {
        _navigateToChat(context, ref, chat);
      }
    } catch (_) {
      // Chat not found or error — stay on home
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Push-notification taps update the URL to /?chat_id=N which
    // rebuilds HomeScreen with a new returnToChatId. initState only
    // ever runs once, so we re-run the handler from didUpdateWidget
    // when the id changes.
    if (widget.returnToChatId != null &&
        widget.returnToChatId != oldWidget.returnToChatId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleReturnToChat();
      });
    }
  }

  @override
  void dispose() {
    _approvedChatSubscription?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  void _openActionPicker(BuildContext context, WidgetRef ref) async {
    // Use go_router so context.go() from a nested screen (e.g. Discover
    // after joining a chat) clears the action picker from the stack.
    // Navigator.push would leave it stranded on the root navigator above
    // go_router's reach, dropping the user back on "What would you like
    // to do?" instead of the joined chat.
    await context.push('/actions');
    // Refresh chat list in case they created/joined a chat
    if (mounted) {
      ref.read(myChatsProvider.notifier).refresh();
    }
  }

  /// Direct path into the Create flow — used by the "Nothing to join" state
  /// of the Looking-for-more card, where the one-tap CTA is to start your
  /// own chat rather than browse Discover (which would be empty).
  Future<void> _openCreateChat(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<Chat>(
      context,
      MaterialPageRoute(builder: (_) => const CreateChatWizard()),
    );
    if (result != null) {
      ref.read(myChatsProvider.notifier).refresh();
      if (context.mounted) {
        _navigateToChat(context, ref, result, showShareDialog: true);
      }
    }
  }

  void _navigateToChat(BuildContext context, WidgetRef ref, Chat chat, {bool showShareDialog = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ChatScreen(chat: chat, showShareDialog: showShareDialog),
      ),
    );
    // ChatScreen.dispose doesn't reliably fire on web (browser back changes
    // the URL without popping the inner Navigator), so explicitly silence
    // any chat-scoped audio here when the push returns.
    ActiveAudio.stopForeground();
    ref.read(backgroundAudioServiceProvider).leaveChat();
    // Refresh chat list when returning from chat screen
    ref.read(myChatsProvider.notifier).refresh();
  }

  void _cancelRequest(BuildContext context, WidgetRef ref, JoinRequest request) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.cancelRequest),
        content: Text(
          l10n.cancelRequestQuestion(request.chatName ?? 'this chat'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.no),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(myChatsProvider.notifier).cancelRequest(request.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.requestCancelled)),
              );
            },
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final myChatsStateAsync = ref.watch(myChatsProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(l10n.appTitle),
        ),
        actions: [
          IconButton(
            key: const Key('donate-button'),
            icon: const Icon(Icons.favorite_outline),
            tooltip: l10n.donate,
            onPressed: () {
              ref
                  .read(analyticsServiceProvider)
                  .logDonateClicked(source: 'home_app_bar');
              launchUrl(
                Uri.parse(
                  '$_donateUrl?utm_source=app&utm_medium=donate_button&utm_campaign=home',
                ),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          IconButton(
            key: const Key('tutorial-button'),
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.howItWorks,
            onPressed: () => context.push('/tutorial?skipIntro=true'),
          ),
          PopupMenuButton<String>(
            key: const Key('overflow-menu'),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'language':
                  showEnhancedLanguageDialog(context, ref);
                case 'contact':
                  launchUrl(Uri.parse('mailto:joel@onemind.life'));
                case 'source':
                  launchUrl(
                    Uri.parse('https://github.com/OneMindLife/OneMind.Life'),
                    mode: LaunchMode.externalApplication,
                  );
                case 'legal':
                  showLegalDocumentsDialog(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'language',
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(l10n.language),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'contact',
                child: ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(l10n.contact),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'source',
                child: ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(l10n.sourceCode),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'legal',
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(l10n.legalDocuments),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Welcome header with editable display name
          const WelcomeHeader(),
          // Rotating banner: "Install OneMind" and/or "Enable notifications".
          // Self-hides when nothing relevant to show.
          const HomeBannerCarousel(),
          // Main content area — single focused queue (no top search bar;
          // search lives on AllChatsScreen where there's actually content
          // to filter, not on a screen that may have zero chats).
          Expanded(
            child: _buildIdleContent(myChatsStateAsync, l10n),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('create-chat-fab'),
        onPressed: () => _openActionPicker(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Build the home content — single focused queue.
  Widget _buildIdleContent(
    AsyncValue<MyChatsState> myChatsStateAsync,
    AppLocalizations l10n,
  ) {
    return myChatsStateAsync.when(
      data: (myChatsState) => AnimatedOpacity(
        opacity: myChatsState.isTranslating ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: RefreshIndicator(
          onRefresh: () async {
            // Refresh both sources Home reads from: the user's own chats
            // and the public-chat discovery list that feeds "Looking for
            // more" suggestions. Otherwise a deleted / newly-created
            // public chat can linger in suggestions indefinitely when the
            // realtime channel has missed its event.
            await Future.wait([
              ref.read(myChatsProvider.notifier).refresh(),
              ref.read(publicChatsProvider.notifier).refresh(),
            ]);
          },
          child: Builder(
            builder: (context) {
              final sorted = sortByUrgency(myChatsState.dashboardChats);
              final partition = partitionByAttention(sorted);
              final nextUp = partition.nextUp;
              // "Coming up" — chats where you've already done your part
              // for the active round and are just waiting for it to
              // advance. The next time you'll need to act, this chat is
              // where it'll happen. Forward-leaning — earns the slot.
              //
              // Inactive chats (paused, between rounds) are intentionally
              // dropped from home entirely — they can sit indefinitely so
              // surfacing them on the focused queue is misleading. They
              // remain reachable via "View all my chats" → AllChatsScreen.
              final comingUp = partition.wrappingUp;

              final shouldAnimate = !_hasPlayedEntrance;
              if (shouldAnimate) _hasPlayedEntrance = true;

              // Empty state: no actionable chats. Show a focused
              // "queue is clear" panel with featured public chats so the
              // user has something to do. Suppress while the official-chat
              // auto-join is in flight to avoid a flash.
              if (nextUp.isEmpty) {
                if (_isAutoJoiningOfficial) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 32, 16, 80),
                    children: const [
                      Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  );
                }
                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  children: [
                    _buildEmptyStatePanel(context, l10n),
                    // The user's queue is clear, but they may still have
                    // older chats hanging around (paused / completed /
                    // wrapping up). Surface them inline below the empty
                    // state so they're discoverable without forcing the
                    // user to navigate elsewhere.
                    if (comingUp.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildComingUpSection(context, l10n, comingUp),
                    ],
                    if (myChatsState.pendingRequests.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader(context, l10n.pendingRequests),
                      const SizedBox(height: 8),
                      ...myChatsState.pendingRequests.map(
                        (request) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _PendingRequestCard(
                            request: request,
                            onCancel: () =>
                                _cancelRequest(context, ref, request),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              }

              // Has chats: hero (first) + compact rows (rest) +
              // collapsible older + pending.
              final hero = nextUp.first;
              final alsoActive = nextUp.skip(1).toList();

              return ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  // ── Hero "Next up" ──────────────────────────────
                  _buildSectionHeader(context, l10n.nextUp),
                  const SizedBox(height: 8),
                  _HeroChatCard(
                    dashInfo: hero,
                    onTap: () =>
                        _navigateToChat(context, ref, hero.chat),
                  ),

                  // ── Also active ─────────────────────────────────
                  if (alsoActive.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      context,
                      'Also active (${alsoActive.length})',
                    ),
                    const SizedBox(height: 8),
                    ...alsoActive.asMap().entries.map((entry) {
                      return _buildChatCardEntry(
                        context: context,
                        l10n: l10n,
                        index: entry.key,
                        dashInfo: entry.value,
                        shouldAnimate: shouldAnimate,
                      );
                    }),
                  ],

                  // ── Older chats (collapsible inline) ────────────
                  if (comingUp.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildComingUpSection(context, l10n, comingUp),
                  ],

                  // ── Pending Join Requests ──────────────────────
                  if (myChatsState.pendingRequests.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader(context, l10n.pendingRequests),
                    const SizedBox(height: 8),
                    ...myChatsState.pendingRequests.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PendingRequestCard(
                          request: request,
                          onCancel: () =>
                              _cancelRequest(context, ref, request),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
      loading: () => Semantics(
        label: l10n.loadingChats,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ErrorView(
        message: l10n.failedToLoadChats,
        details: error.toString(),
        onRetry: () => ref.read(myChatsProvider.notifier).refresh(),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }

  Widget _buildChatCardEntry({
    required BuildContext context,
    required AppLocalizations l10n,
    required int index,
    required ChatDashboardInfo dashInfo,
    required bool shouldAnimate,
  }) {
    final chat = dashInfo.chat;
    final semanticLabel = chat.isOfficial
        ? '${l10n.official} chat: ${chat.displayName}. ${chat.displayInitialMessage}'
        : 'Chat: ${chat.displayName}. ${chat.displayInitialMessage}';
    final child = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChatDashboardCard(
        key: Key('chat-card-${chat.id}'),
        name: chat.displayName,
        initialMessage: chat.displayInitialMessage,
        onTap: () => _navigateToChat(context, ref, chat),
        participantCount: dashInfo.participantCount,
        phase: dashInfo.currentRoundPhase,
        isPaused: dashInfo.isPaused,
        timeRemaining: dashInfo.timeRemaining,
        translationLanguages: chat.translationLanguages,
        viewingLanguageCode: dashInfo.viewingLanguageCode,
        phaseBarColorOverride:
            chat.isOfficial ? Theme.of(context).colorScheme.primary : null,
        semanticLabel: semanticLabel,
      ),
    );
    if (!shouldAnimate) return child;
    return _StaggeredFadeIn(index: index, child: child);
  }

  /// Empty state — shown when the user has zero actionable chats. Frames
  /// the moment as accomplishment ("Your queue is clear") rather than as
  /// a void, then surfaces concrete next actions: featured public chats
  /// they can join right now, or starting their own.
  ///
  /// Two shapes (same outer frame, different center):
  /// - Suggestions available → 3 featured public chats + "Browse all" link
  /// - No suggestions → just the create-your-own CTA
  Widget _buildEmptyStatePanel(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final suggestions = ref.watch(topPublicChatSuggestionsProvider);
    final hasSuggestions = suggestions.isNotEmpty;

    return Column(
      key: const Key('empty-state-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero "queue clear" header.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasSuggestions ? Icons.explore_outlined : Icons.bolt,
                  size: 32,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasSuggestions
                    ? 'Your queue is clear'
                    : l10n.nothingToJoinTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                hasSuggestions
                    ? 'Jump into a live conversation:'
                    : l10n.nothingToJoinDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        // Featured public chats — same ChatDashboardCard the user's own
        // chats use so timer/phase/participant info reads identically.
        ...suggestions.map((summary) {
          final phaseEndsAt = summary.phaseEndsAt;
          final timeRemaining = phaseEndsAt != null
              ? () {
                  final remaining = phaseEndsAt.difference(DateTime.now());
                  return remaining.isNegative ? Duration.zero : remaining;
                }()
              : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChatDashboardCard(
              key: Key('suggested-chat-card-${summary.id}'),
              name: summary.displayName,
              initialMessage: summary.displayInitialMessage,
              onTap: () => _joinSuggestedChat(summary),
              participantCount: summary.participantCount,
              phase: summary.currentPhase,
              isPaused: summary.schedulePaused || summary.hostPaused,
              timeRemaining: timeRemaining,
              translationLanguages: summary.translationLanguages,
              viewingLanguageCode: summary.translationLanguage,
            ),
          );
        }),
        if (hasSuggestions) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              key: const Key('empty-state-browse-all'),
              onPressed: () => context.push('/discover'),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(l10n.seeAllPublicChats),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(color: theme.dividerColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: Divider(color: theme.dividerColor)),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Center(
          child: FilledButton.icon(
            key: const Key('empty-state-create-chat'),
            onPressed: () => _openCreateChat(context, ref),
            icon: const Icon(Icons.add),
            label: Text(l10n.createChat),
          ),
        ),
      ],
    );
  }

  /// Inline expandable "Coming up" section. Shows chats where you've
  /// already done your part for the active round and are waiting for it
  /// to advance — the next round will land you back in nextUp here, so
  /// "Coming up" reads accurately as "you'll be back here soon."
  ///
  /// Inactive chats (paused / no active round) are intentionally NOT
  /// shown here — they could sit indefinitely, and surfacing them on
  /// the focused queue would misrepresent them as actionable. They
  /// remain reachable via "View all my chats" → AllChatsScreen.
  ///
  /// Click the header to expand (up to 5 cards inline). "View all my
  /// chats" link always shows when expanded — drills into the full
  /// searchable AllChatsScreen which lists everything (including next-up
  /// and inactive).
  Widget _buildComingUpSection(
    BuildContext context,
    AppLocalizations l10n,
    List<ChatDashboardInfo> comingUp,
  ) {
    final theme = Theme.of(context);
    final preview = comingUp.take(5).toList();

    return Column(
      key: const Key('coming-up-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tappable header — toggles expansion.
        InkWell(
          onTap: () => setState(() => _olderChatsExpanded = !_olderChatsExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  _olderChatsExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Coming up (${comingUp.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_olderChatsExpanded) ...[
          const SizedBox(height: 8),
          ...preview.map((dashInfo) {
            final chat = dashInfo.chat;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChatDashboardCard(
                key: Key('coming-up-chat-card-${chat.id}'),
                name: chat.displayName,
                initialMessage: chat.displayInitialMessage,
                onTap: () => _navigateToChat(context, ref, chat),
                participantCount: dashInfo.participantCount,
                phase: dashInfo.currentRoundPhase,
                isPaused: dashInfo.isPaused,
                timeRemaining: dashInfo.timeRemaining,
                translationLanguages: chat.translationLanguages,
                viewingLanguageCode: dashInfo.viewingLanguageCode,
                phaseBarColorOverride:
                    chat.isOfficial ? theme.colorScheme.primary : null,
              ),
            );
          }),
          // Always show "View all my chats" — drills into AllChatsScreen
          // which lists everything (next-up + coming-up + inactive) with
          // full search.
          Center(
            child: TextButton.icon(
              key: const Key('coming-up-view-all'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AllChatsScreen(),
                ),
              ),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('View all my chats'),
            ),
          ),
        ],
      ],
    );
  }

  /// Join a suggested public chat and open it — mirrors DiscoverScreen's
  /// tap handler so the UX is identical whether the chat was picked here
  /// or on the discover page.
  Future<void> _joinSuggestedChat(PublicChatSummary summary) async {
    final l10n = AppLocalizations.of(context);
    try {
      final chatService = ref.read(chatServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final authService = ref.read(authServiceProvider);

      final chat = await chatService.getChatById(summary.id);
      if (chat == null) {
        if (mounted) context.showErrorMessage(l10n.chatNotFound);
        return;
      }

      final displayName = authService.displayName!;
      await participantService.joinChat(
        chatId: chat.id,
        displayName: displayName,
        isHost: false,
      );

      if (mounted) {
        _navigateToChat(context, ref, chat);
      }
    } catch (e) {
      if (mounted) context.showErrorMessage(l10n.failedToJoinChat(e.toString()));
    }
  }

}

class _PendingRequestCard extends StatelessWidget {
  final JoinRequest request;
  final VoidCallback onCancel;

  const _PendingRequestCard({
    required this.request,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chatName = request.chatName ?? 'Chat #${request.chatId}';
    final semanticLabel =
        '${l10n.pending} request for $chatName. ${l10n.waitingForHostApproval}';

    return Semantics(
      label: semanticLabel,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Warm amber left border — needs attention
              ExcludeSemantics(
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    chatName,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            if (request.chatInitialMessage != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                request.chatInitialMessage!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              l10n.waitingForHostApproval,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Cancel button
                      Semantics(
                        button: true,
                        label: l10n.cancelRequest,
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: l10n.cancelRequest,
                          onPressed: onCancel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero chat card — visually elevated wrapper around ChatDashboardCard
/// for the single most-urgent chat in the user's queue. Provides the
/// game-like "next thing to do" focal point on Home.
///
/// The card itself is the existing ChatDashboardCard so phase/timer/
/// participant rendering stays identical to "Also active" rows below.
/// What's added: a subtle phase-tinted glow + slightly stronger shadow,
/// so the eye lands here first.
class _HeroChatCard extends StatelessWidget {
  final ChatDashboardInfo dashInfo;
  final VoidCallback onTap;

  const _HeroChatCard({required this.dashInfo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chat = dashInfo.chat;
    final isOfficial = chat.isOfficial;

    // Pick a glow color tied to the active phase so the focal point reads
    // as "this round needs your attention now" — not a generic highlight.
    final Color glow;
    if (isOfficial) {
      glow = theme.colorScheme.primary;
    } else {
      switch (dashInfo.currentRoundPhase) {
        case RoundPhase.proposing:
          glow = AppColors.proposing;
          break;
        case RoundPhase.rating:
          glow = AppColors.rating;
          break;
        case RoundPhase.waiting:
        case null:
          glow = theme.colorScheme.primary;
          break;
      }
    }

    return Container(
      key: Key('hero-chat-card-${chat.id}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ChatDashboardCard(
        key: Key('chat-card-${chat.id}'),
        name: chat.displayName,
        initialMessage: chat.displayInitialMessage,
        onTap: onTap,
        participantCount: dashInfo.participantCount,
        phase: dashInfo.currentRoundPhase,
        isPaused: dashInfo.isPaused,
        timeRemaining: dashInfo.timeRemaining,
        translationLanguages: chat.translationLanguages,
        viewingLanguageCode: dashInfo.viewingLanguageCode,
        phaseBarColorOverride: isOfficial ? theme.colorScheme.primary : null,
        semanticLabel: isOfficial
            ? 'Official chat: ${chat.displayName}. ${chat.displayInitialMessage}'
            : 'Chat: ${chat.displayName}. ${chat.displayInitialMessage}',
      ),
    );
  }
}

/// Staggered fade-in + slide-up animation for list items on initial load.
class _StaggeredFadeIn extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggeredFadeIn({required this.index, required this.child});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Stagger: delay based on index
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}

