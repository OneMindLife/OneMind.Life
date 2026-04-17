import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/language_service.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../utils/language_utils.dart';
import '../../widgets/error_view.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/chat_dashboard_card.dart';
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
  Timer? _tickTimer;
  late Set<String> _selectedLanguages;

  @override
  void initState() {
    super.initState();
    final currentLang = ref.read(localeProvider).languageCode;
    _selectedLanguages = {currentLang};
    _scrollController.addListener(_onScroll);
    // 1-second tick for countdown timer refresh
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tickTimer?.cancel();
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
          context.showErrorMessage(l10n.chatNotFound);
        }
        return;
      }

      // Use stored display name (always available via ensureDisplayName at startup)
      final displayName = authService.displayName!;

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
        context.showErrorMessage(l10n.failedToJoinChat(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final publicChatsAsync = ref.watch(publicChatsProvider);
    final myChatsAsync = ref.watch(myChatsProvider);
    final joinedChatIds = myChatsAsync.whenData(
      (state) => {for (final c in state.chats) c.id},
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

          // Language filter chips
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: LanguageService.supportedLanguageCodes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final code = LanguageService.supportedLanguageCodes[index];
                final selected = _selectedLanguages.contains(code);
                return FilterChip(
                  label: Text(LanguageUtils.displayName(code)),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _selectedLanguages.add(code);
                      } else if (_selectedLanguages.length > 1) {
                        _selectedLanguages.remove(code);
                      }
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 4),

          // Content
          Expanded(
            child: publicChatsAsync.when(
              data: (publicChatsState) => _buildChatList(
                publicChatsState,
                joinedChatIds.valueOrNull ?? {},
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
  ) {
    final l10n = AppLocalizations.of(context);
    final chats = publicChatsState.chats
        .where((c) => c.translationLanguages.any(_selectedLanguages.contains))
        .where((c) => !joinedChatIds.contains(c.id))
        .toList();

    if (chats.isEmpty) {
      // Determine why the list is empty
      final hasSearch = _searchController.text.isNotEmpty;
      final hasUnfilteredChats = publicChatsState.chats.isNotEmpty;
      final isFiltered = hasUnfilteredChats && !hasSearch;

      final String title;
      final String subtitle;
      final IconData icon;

      if (hasSearch) {
        title = l10n.noChatsFoundFor(_searchController.text);
        subtitle = l10n.tryDifferentSearch;
        icon = Icons.search_off;
      } else if (isFiltered) {
        title = l10n.noChatsMatchFilters;
        subtitle = l10n.tryAdjustingFilters;
        icon = Icons.filter_list_off;
      } else {
        title = l10n.noPublicChatsAvailable;
        subtitle = l10n.beFirstToCreate;
        icon = Icons.public_off;
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
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

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChatDashboardCard(
              key: Key('public-chat-card-${chat.id}'),
              name: chat.displayName,
              initialMessage: chat.displayInitialMessage,
              onTap: () => _joinChat(chat),
              participantCount: chat.participantCount,
              phase: chat.currentPhase,
              isPaused: chat.isPaused,
              timeRemaining: chat.timeRemaining,
              translationLanguages: chat.translationLanguages,
            ),
          );
        },
      ),
    );
  }

  Widget _buildError(String error) {
    final l10n = AppLocalizations.of(context);
    return ErrorView(
      message: l10n.failedToLoadPublicChats(error),
      onRetry: () => ref.read(publicChatsProvider.notifier).refresh(),
    );
  }
}
