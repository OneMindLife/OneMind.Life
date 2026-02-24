import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../chat/chat_screen.dart';
import '../join/join_dialog.dart';
import '../create/create_chat_wizard.dart';
import '../legal/legal_documents_dialog.dart';
import '../tutorial/tutorial_data.dart';
import '../../widgets/language_selector.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.returnToChatId});

  /// If set, auto-navigate to this chat on mount (e.g. after Stripe checkout redirect)
  final int? returnToChatId;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<Chat>? _approvedChatSubscription;
  final _searchController = TextEditingController();
  bool _isSearching = false;

  /// Regex to detect a 6 alphanumeric character invite code
  static final _inviteCodeRegex = RegExp(r'^[A-Za-z0-9]{6}$');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
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
        final filtered = myChatsState.chats
            .where((c) => c.displayName.toLowerCase().contains(query))
            .toList();

        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      color: Colors.grey.shade400,
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
                (chat) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChatCard(
                    chat: chat,
                    onTap: () => _navigateToChat(context, ref, chat),
                  ),
                ),
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
            padding: const EdgeInsets.all(16),
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
                  final chats = myChatsState.chats;
                  if (chats.isEmpty &&
                      myChatsState.pendingRequests.isEmpty) {
                    return _buildEmptyState(context, ref);
                  }
                  if (chats.isEmpty) {
                    return _buildNoChatsYet(context);
                  }
                  return Column(
                    children: chats
                        .map(
                          (chat) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ChatCard(
                              chat: chat,
                              onTap: () =>
                                  _navigateToChat(context, ref, chat),
                            ),
                          ),
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
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
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
              color: Colors.grey.shade400,
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
                    color: Colors.grey.shade600,
                  ),
              textAlign: TextAlign.center,
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
              color: Colors.grey.shade400,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.noActiveChatsYet,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatCard extends StatelessWidget {
  final Chat chat;
  final bool isOfficial;
  final VoidCallback onTap;

  const _ChatCard({
    required this.chat,
    this.isOfficial = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    debugPrint('[_ChatCard] id=${chat.id} name="${chat.name}" displayName="${chat.displayName}" nameTranslated="${chat.nameTranslated}"');
    final semanticLabel = isOfficial
        ? '${l10n.official} chat: ${chat.displayName}. ${chat.displayInitialMessage}'
        : 'Chat: ${chat.displayName}. ${chat.displayInitialMessage}';

    return Semantics(
      key: Key('chat-card-${chat.id}'),
      button: true,
      label: semanticLabel,
      hint: 'Double tap to open',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon - decorative, excluded from semantics
                ExcludeSemantics(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isOfficial
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isOfficial ? Icons.public : Icons.chat_bubble_outline,
                      color: isOfficial
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              chat.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chat.displayInitialMessage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Chevron - decorative
                const ExcludeSemantics(
                  child: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Pending icon
              ExcludeSemantics(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.hourglass_empty,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Content
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
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.tertiary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.pending,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onTertiary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (request.chatInitialMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        request.chatInitialMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
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
    );
  }
}
