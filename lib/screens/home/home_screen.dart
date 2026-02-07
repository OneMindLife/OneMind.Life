import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/language_selector.dart';
import '../chat/chat_screen.dart';
// import '../discover/discover_screen.dart'; // Hidden for MVP
import '../join/join_dialog.dart';
import '../create/create_chat_wizard.dart';
import '../legal/legal_documents_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<Chat>? _approvedChatSubscription;

  @override
  void initState() {
    super.initState();
    // Listen for approved join requests to auto-open the chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupApprovedChatListener();
    });
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

  @override
  void dispose() {
    _approvedChatSubscription?.cancel();
    super.dispose();
  }

  void _openJoinDialog(BuildContext context, WidgetRef ref) {
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

  // Hidden for MVP
  // void _openDiscover(BuildContext context, WidgetRef ref) async {
  //   await Navigator.push(
  //     context,
  //     MaterialPageRoute(builder: (context) => const DiscoverScreen()),
  //   );
  //   // Refresh chat list when returning (user may have joined a chat)
  //   ref.read(myChatsProvider.notifier).refresh();
  // }

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

  @override
  Widget build(BuildContext context) {
    final myChatsStateAsync = ref.watch(myChatsProvider);
    final officialChatAsync = ref.watch(officialChatProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(l10n.appTitle),
        ),
        actions: [
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
      body: myChatsStateAsync.when(
        data: (myChatsState) => RefreshIndicator(
          onRefresh: () async {
            ref.read(myChatsProvider.notifier).refresh();
            ref.invalidate(officialChatProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Official OneMind Chat
              officialChatAsync.when(
                data: (officialChat) {
                  if (officialChat != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(context, l10n.officialOneMind),
                        const SizedBox(height: 8),
                        _ChatCard(
                          chat: officialChat,
                          isOfficial: true,
                          onTap: () => _navigateToChat(context, ref, officialChat),
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

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

              // My Chats (exclude official chat - it's shown above)
              _buildSectionHeader(context, l10n.yourChats),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final nonOfficialChats = myChatsState.chats
                      .where((chat) => !chat.isOfficial)
                      .toList();
                  if (nonOfficialChats.isEmpty &&
                      myChatsState.pendingRequests.isEmpty) {
                    return _buildEmptyState(context, ref);
                  }
                  if (nonOfficialChats.isEmpty) {
                    return _buildNoChatsYet(context);
                  }
                  return Column(
                    children: nonOfficialChats.map(
                      (chat) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ChatCard(
                          chat: chat,
                          onTap: () => _navigateToChat(context, ref, chat),
                        ),
                      ),
                    ).toList(),
                  );
                },
              ),
            ],
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
      ),
      floatingActionButton: SpeedDial(
        key: const Key('chat-speed-dial'),
        icon: Icons.add,
        activeIcon: Icons.close,
        spacing: 12,
        childPadding: const EdgeInsets.all(5),
        spaceBetweenChildren: 8,
        children: [
          SpeedDialChild(
            key: const Key('create-chat-fab'),
            child: const Icon(Icons.create),
            label: l10n.createChat,
            onTap: () => _openCreateChat(context, ref),
          ),
          SpeedDialChild(
            key: const Key('join-chat-fab'),
            child: const Icon(Icons.abc),
            label: l10n.joinWithCode,
            onTap: () => _openJoinDialog(context, ref),
          ),
        ],
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
                          if (isOfficial)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                l10n.official,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.onPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
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
