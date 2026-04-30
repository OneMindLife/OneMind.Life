import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/app_exception.dart';
import '../models/models.dart';
import 'participant_repository.dart';

/// Production [ParticipantRepository] implementation backed by Supabase.
///
/// All [joinChat] calls route through the
/// `join_chat_returning_participant` RPC, which is the single source of
/// truth for join branching (fresh / left→active / kicked stays kicked /
/// already-in / etc.). The previous architecture had this logic split
/// across two Dart methods plus the RPC, which silently drifted when the
/// soft-delete migration shipped.
class SupabaseParticipantRepository implements ParticipantRepository {
  final SupabaseClient _client;

  SupabaseParticipantRepository(this._client);

  @override
  Future<JoinResult> joinChat({
    required int chatId,
    required String displayName,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const CannotJoin(CannotJoinReason.authRequired);

    // Snapshot of pre-call state so we can determine outcome category.
    final before = await _client
        .from('participants')
        .select('id, status')
        .eq('chat_id', chatId)
        .eq('user_id', userId)
        .maybeSingle();

    if (before != null && before['status'] == 'kicked') {
      // Kicked stays kicked — caller must use requestToJoin + approval.
      return const CannotJoin(CannotJoinReason.kicked);
    }
    if (before != null && before['status'] == 'pending') {
      // Awaiting host approval — fetch full record to return
      final pendingRow = await _client
          .from('participants')
          .select()
          .eq('id', before['id'] as int)
          .single();
      return PendingApproval(Participant.fromJson(pendingRow));
    }

    // Either no row, or row exists with status='active' or 'left'. The RPC
    // upserts: insert if absent, flip 'left' → 'active' if present, no-op
    // for 'active'. Returns the post-state row.
    final List<dynamic> rows;
    try {
      rows = await _client.rpc(
        'join_chat_returning_participant',
        params: {
          'p_chat_id': chatId,
          'p_display_name': displayName,
        },
      ) as List<dynamic>;
    } on PostgrestException catch (e) {
      // The RPC raises on inactive / non-public chats. Map to typed reasons
      // so callers don't have to grep messages.
      final msg = e.message;
      if (msg.contains('does not allow direct joining')) {
        return const CannotJoin(CannotJoinReason.chatRequiresApproval);
      }
      if (msg.contains('Not authenticated')) {
        return const CannotJoin(CannotJoinReason.authRequired);
      }
      rethrow;
    }

    if (rows.isEmpty) {
      return const CannotJoin(CannotJoinReason.chatNotFound);
    }
    // The RPC returns a partial projection; refetch the full row so models
    // line up with the Participant.fromJson contract.
    final row = await _client
        .from('participants')
        .select()
        .eq('id', (rows.first as Map)['id'] as int)
        .single();
    final participant = Participant.fromJson(row);

    if (before == null) return JoinedFresh(participant);
    if (before['status'] == 'left') return Reactivated(participant);
    return AlreadyIn(participant);
  }

  @override
  Future<Participant> addHost({
    required int chatId,
    required String displayName,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw AppException.authRequired(
        message: 'User must be signed in to create a chat',
      );
    }
    final response = await _client.from('participants').insert({
      'chat_id': chatId,
      'display_name': displayName,
      'user_id': userId,
      'is_host': true,
      'is_authenticated': true,
      'status': 'active',
    }).select().single();
    return Participant.fromJson(response);
  }

  @override
  Future<void> requestToJoin({
    required int chatId,
    required String displayName,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw AppException.authRequired(
        message: 'User must be signed in to request to join',
      );
    }
    await _client.from('join_requests').insert({
      'chat_id': chatId,
      'display_name': displayName,
      'user_id': userId,
      'is_authenticated': true,
      'status': 'pending',
    });
  }

  @override
  Future<void> leaveChat(int participantId) async {
    await _client
        .from('participants')
        .update({'status': 'left'})
        .eq('id', participantId);
  }

  @override
  Future<void> kickParticipant(int participantId) async {
    await _client
        .from('participants')
        .update({'status': 'kicked'})
        .eq('id', participantId);
  }

  @override
  Future<void> approveRequest(int requestId) async {
    await _client.rpc('approve_join_request', params: {'p_request_id': requestId});
  }

  @override
  Future<void> denyRequest(int requestId) async {
    await _client
        .from('join_requests')
        .update({
          'status': 'denied',
          'resolved_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId);
  }

  @override
  Future<void> cancelJoinRequest(int requestId) async {
    await _client.rpc('cancel_join_request', params: {'p_request_id': requestId});
  }

  @override
  Future<List<Participant>> getParticipants(int chatId) async {
    final response = await _client
        .from('participants')
        .select()
        .eq('chat_id', chatId)
        .eq('status', 'active')
        .order('display_name');
    return (response as List).map((json) => Participant.fromJson(json)).toList();
  }

  @override
  Future<Participant?> getMyParticipant(int chatId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final response = await _client
        .from('participants')
        .select()
        .eq('chat_id', chatId)
        .eq('user_id', userId)
        .maybeSingle();
    return response != null ? Participant.fromJson(response) : null;
  }

  @override
  Future<List<JoinRequest>> getMyPendingRequests() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final response = await _client
        .from('join_requests')
        .select('''
          *,
          chats(name, initial_message)
        ''')
        .eq('user_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (response as List).map((json) => JoinRequest.fromJson(json)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingRequests(int chatId) async {
    final response = await _client
        .from('join_requests')
        .select()
        .eq('chat_id', chatId)
        .eq('status', 'pending')
        .order('created_at');
    return List<Map<String, dynamic>>.from(response as List);
  }

  @override
  Future<void> updateViewingLanguage(int chatId, String languageCode) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('participants')
        .update({'viewing_language_code': languageCode})
        .eq('chat_id', chatId)
        .eq('user_id', userId);
  }

  @override
  RealtimeChannel subscribeToParticipants(
    int chatId,
    void Function(List<Participant>) onUpdate,
  ) {
    return _client
        .channel('participants:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) async {
            final participants = await getParticipants(chatId);
            onUpdate(participants);
          },
        )
        .subscribe();
  }
}
