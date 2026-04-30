import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/chat_providers.dart';
import '../../providers/providers.dart';
import '../../services/active_audio.dart';
import '../../utils/dashboard_sort.dart';
import '../../widgets/chat_dashboard_card.dart';
import '../../widgets/error_view.dart';
import '../chat/chat_screen.dart';

/// True "everything I'm in" view — all three buckets in one place:
/// Next up (you have something to do), Wrapping up (you've done your part,
/// waiting for the round), and Inactive (paused / between rounds). Home
/// shows the focused queue; this is the escape hatch when you want to
/// see/find a specific chat regardless of state.
///
/// Owns the search bar — filters across all three sections by chat name
/// or initial-message keyword.
class AllChatsScreen extends ConsumerStatefulWidget {
  const AllChatsScreen({super.key});

  @override
  ConsumerState<AllChatsScreen> createState() => _AllChatsScreenState();
}

class _AllChatsScreenState extends ConsumerState<AllChatsScreen> {
  Timer? _tickTimer;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _navigateToChat(Chat chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
    );
    // Belt-and-suspenders cleanup — ChatScreen.dispose isn't reliable on
    // web, so silence chat-scoped audio when returning here.
    ActiveAudio.stopForeground();
    ref.read(backgroundAudioServiceProvider).leaveChat();
    if (mounted) {
      ref.read(myChatsProvider.notifier).refresh();
    }
  }

  bool _matches(ChatDashboardInfo info) {
    if (_query.isEmpty) return true;
    final chat = info.chat;
    return chat.displayName.toLowerCase().contains(_query) ||
        chat.displayInitialMessage.toLowerCase().contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final myChatsStateAsync = ref.watch(myChatsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.allChats)),
      body: Column(
        children: [
          // Search bar — filters both wrapping-up and inactive sections
          // by chat name or initial-message keyword.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const Key('all-chats-search'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchYourChatsOrJoinWithCode,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
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
          Expanded(
            child: myChatsStateAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorView(
                message: l10n.failedToLoadChats,
                details: error.toString(),
                onRetry: () => ref.read(myChatsProvider.notifier).refresh(),
              ),
              data: (state) {
                final sorted = sortByUrgency(state.dashboardChats);
                final partition = partitionByAttention(sorted);
                final nextUp = partition.nextUp.where(_matches).toList();
                final wrappingUp =
                    partition.wrappingUp.where(_matches).toList();
                final inactive =
                    partition.inactive.where(_matches).toList();

                final emptyAfterFilter = nextUp.isEmpty &&
                    wrappingUp.isEmpty &&
                    inactive.isEmpty;
                final emptyOverall = state.dashboardChats.isEmpty;

                if (emptyAfterFilter) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            emptyOverall ? Icons.inbox_outlined : Icons.search_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            emptyOverall
                                ? l10n.noChatsHere
                                : l10n.noMatchingChats,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.read(myChatsProvider.notifier).refresh();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (nextUp.isNotEmpty) ...[
                        _sectionHeader(
                            context, l10n.nextUpWithCount(nextUp.length)),
                        const SizedBox(height: 8),
                        ...nextUp.map((info) => _chatCard(context, l10n, info)),
                      ],
                      if (wrappingUp.isNotEmpty) ...[
                        if (nextUp.isNotEmpty) const SizedBox(height: 16),
                        _sectionHeader(context,
                            l10n.wrappingUpWithCount(wrappingUp.length)),
                        const SizedBox(height: 8),
                        ...wrappingUp
                            .map((info) => _chatCard(context, l10n, info)),
                      ],
                      if (inactive.isNotEmpty) ...[
                        if (nextUp.isNotEmpty || wrappingUp.isNotEmpty)
                          const SizedBox(height: 16),
                        _sectionHeader(context,
                            l10n.inactiveWithCount(inactive.length)),
                        const SizedBox(height: 8),
                        ...inactive
                            .map((info) => _chatCard(context, l10n, info)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }

  Widget _chatCard(
    BuildContext context,
    AppLocalizations l10n,
    ChatDashboardInfo dashInfo,
  ) {
    final chat = dashInfo.chat;
    final semanticLabel = chat.isOfficial
        ? '${l10n.official} chat: ${chat.displayName}. ${chat.displayInitialMessage}'
        : 'Chat: ${chat.displayName}. ${chat.displayInitialMessage}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChatDashboardCard(
        key: Key('all-chats-card-${chat.id}'),
        name: chat.displayName,
        initialMessage: chat.displayInitialMessage,
        onTap: () => _navigateToChat(chat),
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
  }
}
