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
