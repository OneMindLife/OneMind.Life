import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import 'providers.dart';
import 'notifiers/my_chats_notifier.dart';
import 'notifiers/public_chats_notifier.dart';
import 'notifiers/chat_detail_notifier.dart';

export 'notifiers/my_chats_notifier.dart';
export 'notifiers/public_chats_notifier.dart';
export 'notifiers/grid_ranking_notifier.dart';
export 'notifiers/chat_detail_notifier.dart';

/// Provider for the user's chat list (HomeScreen)
/// Now includes pending join requests with realtime updates
final myChatsProvider =
    StateNotifierProvider<MyChatsNotifier, AsyncValue<MyChatsState>>(
  (ref) => MyChatsNotifier(ref),
);

/// Provider for the official OneMind chat
final officialChatProvider = FutureProvider<Chat?>((ref) async {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getOfficialChat();
});

/// Provider for public chats discovery (DiscoverScreen)
/// Now with Realtime updates for automatic refresh when public chats change
final publicChatsProvider =
    StateNotifierProvider<PublicChatsNotifier, AsyncValue<List<PublicChatSummary>>>(
  (ref) => PublicChatsNotifier(ref),
);

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
