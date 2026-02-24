import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../../utils/dashboard_sort.dart';
import '../chat/chat_screen.dart';
import '../join/join_dialog.dart';
import '../create/create_chat_wizard.dart';
import '../legal/legal_documents_dialog.dart';
import '../tutorial/tutorial_data.dart';
import '../../widgets/chat_dashboard_card.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/welcome_header.dart';

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
  final _searchController = TextEditingController();
  bool _isSearching = false;
  bool _hasPlayedEntrance = false;
  Timer? _tickTimer;

  /// Regex to detect a 6 alphanumeric character invite code
  static final _inviteCodeRegex = RegExp(r'^[A-Za-z0-9]{6}$');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // 1-second tick for countdown refresh + re-sort
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Listen for approved join requests to auto-open the chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupApprovedChatListener();
      _handleReturnToChat();
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() => _isSearching = query.isNotEmpty);
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

  /// Auto-navigate to a chat after returning from Stripe checkout
  void _handleReturnToChat() async {
    final chatId = widget.returnToChatId;
    if (chatId == null) return;

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
  void dispose() {
    _approvedChatSubscription?.cancel();
    _searchController.dispose();
    _tickTimer?.cancel();
    super.dispose();
  }

  void _openJoinDialog(BuildContext context, WidgetRef ref, {String? prefillCode}) {
    showDialog(
      context: context,
      builder: (ctx) => JoinDialog(
        onJoined: (chat) {
          ref.read(myChatsProvider.notifier).refresh();
          _navigateToChat(context, ref, chat);
        },
      ),
    );
  }

  void _openCreateChat(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<Chat>(
      context,
      MaterialPageRoute(builder: (ctx) => const CreateChatWizard()),
    );
    if (result != null) {
      ref.read(myChatsProvider.notifier).refresh();
      if (context.mounted) {
        _navigateToChat(context, ref, result);
      }
    }
  }

  void _navigateToChat(BuildContext context, WidgetRef ref, Chat chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ChatScreen(chat: chat),
      ),
    );
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

  /// Check if the current search text looks like a 6-char invite code
  String? get _detectedInviteCode {
    final text = _searchController.text.trim();
    if (_inviteCodeRegex.hasMatch(text)) return text.toUpperCase();
    return null;
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
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Restart Home Tour (debug)',
              onPressed: () async {
                await ref.read(tutorialServiceProvider).resetHomeTour();
                ref.invalidate(hasCompletedHomeTourProvider);
                if (context.mounted) context.go('/home-tour');
              },
            ),
          IconButton(
            key: const Key('explore-button'),
            icon: const Icon(Icons.explore),
            tooltip: l10n.discoverChats,
            onPressed: () => context.push('/discover'),
          ),
          const LanguageSelector(compact: true),
          IconButton(
            key: const Key('tutorial-button'),
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.howItWorks,
            onPressed: () => context.push('/tutorial'),
          ),
          IconButton(
            key: const Key('legal-button'),
            icon: const Icon(Icons.description_outlined),
            tooltip: l10n.legalDocuments,
            onPressed: () => showLegalDocumentsDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Welcome header with editable display name
          const WelcomeHeader(),
          // Persistent search bar (outside RefreshIndicator)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchYourChatsOrJoinWithCode,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Main content area
          Expanded(
            child: _isSearching
                ? _buildSearchResults(myChatsStateAsync, l10n)
                : _buildIdleContent(myChatsStateAsync, l10n),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('create-chat-fab'),
        onPressed: () => _openCreateChat(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Build the search results view (when user is typing in search bar)
  Widget _buildSearchResults(
    AsyncValue<MyChatsState> myChatsStateAsync,
    AppLocalizations l10n,
  ) {
    final inviteCode = _detectedInviteCode;
    final query = _searchController.text.trim().toLowerCase();

    return myChatsStateAsync.when(
      data: (myChatsState) {
        final filtered = myChatsState.dashboardChats
            .where((d) => d.chat.displayName.toLowerCase().contains(query))
            .toList();

        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          children: [
            // Invite code banner
            if (inviteCode != null) ...[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    if (inviteCode == TutorialData.demoInviteCode) {
                      context.go('/tutorial');
                      return;
                    }
                    _openJoinDialog(context, ref, prefillCode: inviteCode);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.vpn_key,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.inviteCodeDetected(inviteCode),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Filtered own chats
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noMatchingChats,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...filtered.map(
                (dashInfo) {
                  final chat = dashInfo.chat;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ChatDashboardCard(
                      name: chat.displayName,
                      initialMessage: chat.displayInitialMessage,
                      onTap: () => _navigateToChat(context, ref, chat),
                      participantCount: dashInfo.participantCount,
                      phase: dashInfo.currentRoundPhase,
                      isPaused: dashInfo.isPaused,
                      timeRemaining: dashInfo.timeRemaining,
                      translationLanguages: chat.translationLanguages,
                      viewingLanguageCode: dashInfo.viewingLanguageCode,
                      phaseBarColorOverride: chat.isOfficial
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  );
                },
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(l10n.failedToLoadChats),
      ),
    );
  }

  /// Build the idle content (when search bar is empty)
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
            ref.read(myChatsProvider.notifier).refresh();
          },
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              // Pending Join Requests Section
              if (myChatsState.pendingRequests.isNotEmpty) ...[
                _buildSectionHeader(context, l10n.pendingRequests),
                const SizedBox(height: 8),
                ...myChatsState.pendingRequests.map(
                  (request) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PendingRequestCard(
                      request: request,
                      onCancel: () => _cancelRequest(context, ref, request),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // My Chats
              _buildSectionHeader(context, l10n.yourChats),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final sorted = sortByUrgency(myChatsState.dashboardChats);
                  if (sorted.isEmpty &&
                      myChatsState.pendingRequests.isEmpty) {
                    return _buildEmptyState(context, ref);
                  }
                  if (sorted.isEmpty) {
                    return _buildNoChatsYet(context);
                  }
                  // Mark entrance animation as played
                  final shouldAnimate = !_hasPlayedEntrance;
                  if (shouldAnimate) {
                    _hasPlayedEntrance = true;
                  }
                  return Column(
                    children: sorted
                        .asMap()
                        .entries
                        .map(
                          (entry) {
                            final index = entry.key;
                            final dashInfo = entry.value;
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
                                onTap: () =>
                                    _navigateToChat(context, ref, chat),
                                participantCount: dashInfo.participantCount,
                                phase: dashInfo.currentRoundPhase,
                                isPaused: dashInfo.isPaused,
                                timeRemaining: dashInfo.timeRemaining,
                                translationLanguages: chat.translationLanguages,
                                viewingLanguageCode: dashInfo.viewingLanguageCode,
                                phaseBarColorOverride: chat.isOfficial
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                semanticLabel: semanticLabel,
                              ),
                            );
                            if (!shouldAnimate) return child;
                            return _StaggeredFadeIn(
                              index: index,
                              child: child,
                            );
                          },
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      loading: () => Semantics(
        label: l10n.loadingChats,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.failedToLoadChats,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.read(myChatsProvider.notifier).refresh(),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noChatsYet,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.discoverPublicChatsJoinOrCreate,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openCreateChat(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.createChat),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoChatsYet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.noActiveChatsYet,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
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
                  decoration: const BoxDecoration(
                    color: AppColors.consensus,
                    borderRadius: BorderRadius.only(
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
                                      color: AppColors.textSecondary,
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
