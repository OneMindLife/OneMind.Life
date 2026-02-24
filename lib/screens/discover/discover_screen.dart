import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/chat_providers.dart';
import '../chat/chat_screen.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(publicChatsProvider.notifier).loadMore();
    }
  }

  Future<void> _joinChat(PublicChatSummary chatSummary) async {
    final l10n = AppLocalizations.of(context);
    try {
      final chatService = ref.read(chatServiceProvider);
      final participantService = ref.read(participantServiceProvider);
      final authService = ref.read(authServiceProvider);

      // Get the full chat details
      final chat = await chatService.getChatById(chatSummary.id);
      if (chat == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.chatNotFound)),
          );
        }
        return;
      }

      // Get display name - prompt if needed (except for official OneMind chat)
      String displayName;
      final storedName = authService.displayName;

      if (storedName != null && storedName.isNotEmpty) {
        // Use stored name from auth metadata
        displayName = storedName;
      } else if (chat.isOfficial) {
        // Official OneMind chat allows Anonymous
        displayName = l10n.anonymous;
      } else {
        // Prompt for name before joining non-official public chats
        if (!mounted) return;
        final enteredName = await _promptForName();
        if (enteredName == null || enteredName.isEmpty) {
          return; // User cancelled
        }
        displayName = enteredName;
        await authService.setDisplayName(displayName);
      }

      // Join the chat (auth.uid() is used automatically)
      await participantService.joinChat(
        chatId: chat.id,
        displayName: displayName,
        isHost: false,
      );

      // Navigate to the chat
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chat: chat),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToJoinChat(e.toString()))),
        );
      }
    }
  }

  Future<String?> _promptForName() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.enterYourNameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: l10n.yourDisplayName,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: Text(l10n.join),
          ),
        ],
      ),
    );
  }

  /// Navigate to a chat the user has already joined.
  void _openChat(Chat chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(chat: chat),
      ),
    );
    ref.read(myChatsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final publicChatsAsync = ref.watch(publicChatsProvider);
    final myChatsAsync = ref.watch(myChatsProvider);
    final joinedChatIds = myChatsAsync.whenData(
      (state) => {for (final c in state.chats) c.id},
    );
    // Build a map of chat id → Chat for quick lookup
    final joinedChatsMap = myChatsAsync.whenData(
      (state) => {for (final c in state.chats) c.id: c},
    );
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.discoverChats),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
              listenable: _searchController,
              builder: (context, _) => TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.searchPublicChats,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(publicChatsProvider.notifier).search('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  if (value.trim().isEmpty) {
                    ref.read(publicChatsProvider.notifier).search('');
                    return;
                  }
                  _searchDebounce =
                      Timer(const Duration(milliseconds: 300), () {
                    ref
                        .read(publicChatsProvider.notifier)
                        .search(value.trim());
                  });
                },
                onSubmitted: (query) {
                  _searchDebounce?.cancel();
                  if (query.trim().isEmpty) {
                    ref.read(publicChatsProvider.notifier).search('');
                  } else {
                    ref
                        .read(publicChatsProvider.notifier)
                        .search(query.trim());
                  }
                },
              ),
            ),
          ),

          // Content
          Expanded(
            child: publicChatsAsync.when(
              data: (publicChatsState) => _buildChatList(
                publicChatsState,
                joinedChatIds.valueOrNull ?? {},
                joinedChatsMap.valueOrNull ?? {},
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _buildError(error.toString()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(
    PublicChatsState publicChatsState,
    Set<int> joinedChatIds,
    Map<int, Chat> joinedChatsMap,
  ) {
    final l10n = AppLocalizations.of(context);
    final chats = publicChatsState.chats;

    if (chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.public_off,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? l10n.noChatsFoundFor(_searchController.text)
                  : l10n.noPublicChatsAvailable,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.beFirstToCreate,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
      );
    }

    // Item count: chats + optional loading indicator at bottom
    final itemCount = chats.length + (publicChatsState.hasMore ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(publicChatsProvider.notifier).refresh();
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          // Loading indicator at the bottom
          if (index >= chats.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final chat = chats[index];
          final isJoined = joinedChatIds.contains(chat.id);
          return _PublicChatCard(
            chat: chat,
            isJoined: isJoined,
            onTap: isJoined
                ? () => _openChat(joinedChatsMap[chat.id]!)
                : () => _joinChat(chat),
          );
        },
      ),
    );
  }

  Widget _buildError(String error) {
    final l10n = AppLocalizations.of(context);
    return Center(
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
            l10n.failedToLoadPublicChats(error),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.read(publicChatsProvider.notifier).refresh(),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}

class _PublicChatCard extends StatelessWidget {
  final PublicChatSummary chat;
  final bool isJoined;
  final VoidCallback onTap;

  const _PublicChatCard({
    required this.chat,
    this.isJoined = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final participantText = chat.participantCount == 1
        ? l10n.participantCount(chat.participantCount)
        : l10n.participantsCount(chat.participantCount);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isJoined
                          ? colorScheme.surfaceContainerHighest
                          : colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.public,
                      color: isJoined
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title and participants
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat.displayName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isJoined
                                    ? colorScheme.onSurfaceVariant
                                    : null,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              participantText,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Join button or Joined chip
                  if (isJoined)
                    Chip(
                      label: Text(l10n.joined),
                      avatar: const Icon(Icons.check, size: 16),
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    FilledButton(
                      onPressed: onTap,
                      child: Text(l10n.join),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                chat.displayInitialMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
