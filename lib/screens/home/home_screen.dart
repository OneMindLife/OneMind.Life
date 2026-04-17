import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/error_view.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../../utils/dashboard_sort.dart';
import '../chat/chat_screen.dart';
import '../create/create_chat_wizard.dart';
import '../legal/legal_documents_dialog.dart';
import '../../widgets/chat_dashboard_card.dart';
import '../../widgets/language_selector.dart';
import '../action_picker/action_picker_screen.dart';
import '../../widgets/pwa_install_banner.dart';
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
  final _searchController = TextEditingController();
  bool _isSearching = false;
  bool _hasPlayedEntrance = false;
  Timer? _tickTimer;

  // Invite code state removed — joining now handled via action picker

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
      ref.read(pushNotificationServiceProvider).initialize();
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

  void _openActionPicker(BuildContext context, WidgetRef ref) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActionPickerScreen()),
    );
    // Refresh chat list in case they created/joined a chat
    if (mounted) {
      ref.read(myChatsProvider.notifier).refresh();
    }
  }

  void _openCreateChat(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<Chat>(
      context,
      MaterialPageRoute(builder: (ctx) => const CreateChatWizard()),
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
            onPressed: () => launchUrl(
              Uri.parse(_donateUrl),
              mode: LaunchMode.externalApplication,
            ),
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
          // PWA install prompt (mobile only, once per session)
          const PwaInstallBanner(),
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
        onPressed: () => _openActionPicker(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Build the search results view (when user is typing in search bar)
  Widget _buildSearchResults(
    AsyncValue<MyChatsState> myChatsStateAsync,
    AppLocalizations l10n,
  ) {
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
            // Filtered own chats
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
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

              // Pending Join Requests Section (below chats)
              if (myChatsState.pendingRequests.isNotEmpty) ...[
                const SizedBox(height: 24),
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
              ],
            ],
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
              color: Theme.of(context).colorScheme.outline,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.noActiveChatsYet,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
