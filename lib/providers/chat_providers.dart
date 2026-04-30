import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/locale_provider.dart';
import '../models/models.dart';
import 'providers.dart';
import 'notifiers/my_chats_notifier.dart';
import 'notifiers/public_chats_notifier.dart';
import 'notifiers/chat_detail_notifier.dart';

export 'notifiers/my_chats_notifier.dart';
export 'notifiers/public_chats_notifier.dart';
export 'notifiers/rating_notifier.dart';
export 'notifiers/chat_detail_notifier.dart';

/// Provider for the user's chat list (HomeScreen)
/// Now includes pending join requests with realtime updates
final myChatsProvider =
    StateNotifierProvider<MyChatsNotifier, AsyncValue<MyChatsState>>(
  (ref) => MyChatsNotifier(ref),
);

/// Provider for the official OneMind chat.
/// Watches localeProvider to refetch with translations on language change.
final officialChatProvider = FutureProvider<Chat?>((ref) async {
  final chatService = ref.watch(chatServiceProvider);
  final locale = ref.watch(localeProvider);
  return chatService.getOfficialChat(languageCode: locale.languageCode);
});

/// Provider for public chats discovery (DiscoverScreen)
/// Supports pagination, Realtime updates, and alphabetical ordering
final publicChatsProvider =
    StateNotifierProvider<PublicChatsNotifier, AsyncValue<PublicChatsState>>(
  (ref) => PublicChatsNotifier(ref),
);

/// Top 3 public-chat suggestions for the Home "Looking for more" card.
/// Excludes joined chats and paused chats (host- or schedule-paused).
/// Ranked in two tiers, most participants first within each:
///   1. Active — round in proposing/rating (real-time energy).
///   2. Waiting to start — no active round yet, or stuck in the waiting
///      phase because participant/proposing minimums aren't met. Surfaced
///      only after the active tier is exhausted so the user's join helps
///      kick these off.
final topPublicChatSuggestionsProvider =
    Provider<List<PublicChatSummary>>((ref) {
  final publicAsync = ref.watch(publicChatsProvider);
  final myChatsAsync = ref.watch(myChatsProvider);

  final publicChats = publicAsync.valueOrNull?.chats ?? const [];
  final joinedIds = myChatsAsync.valueOrNull?.dashboardChats
          .map((d) => d.chat.id)
          .toSet() ??
      const <int>{};

  int tier(PublicChatSummary p) {
    final phase = p.currentPhase;
    if (phase == RoundPhase.proposing || phase == RoundPhase.rating) return 0;
    return 1; // null or waiting
  }

  final candidates = publicChats.where((p) {
    if (joinedIds.contains(p.id)) return false;
    if (p.schedulePaused || p.hostPaused) return false;
    return true;
  }).toList()
    ..sort((a, b) {
      final byTier = tier(a).compareTo(tier(b));
      if (byTier != 0) return byTier;
      return b.participantCount.compareTo(a.participantCount);
    });
  return candidates.take(3).toList();
});

/// Provider for chat detail state (ChatScreen) - family provider keyed by params
/// Uses auth.uid() for RLS - Realtime subscriptions now work correctly
final chatDetailProvider = StateNotifierProvider.autoDispose
    .family<ChatDetailNotifier, AsyncValue<ChatDetailState>, ChatDetailParams>(
  (ref, params) {
    return ChatDetailNotifier(
      ref: ref,
      chatId: params.chatId,
      showPreviousResults: params.showPreviousResults,
    );
  },
);
