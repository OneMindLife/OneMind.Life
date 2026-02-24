import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/app_exception.dart';
import '../models/models.dart';

/// Service for participant-related database operations
class ParticipantService {
  final SupabaseClient _client;

  ParticipantService(this._client);

  /// Get participants for a chat
  Future<List<Participant>> getParticipants(int chatId) async {
    final response = await _client
        .from('participants')
        .select()
        .eq('chat_id', chatId)
        .eq('status', 'active')
        .order('created_at');

    return (response as List).map((json) => Participant.fromJson(json)).toList();
  }

  /// Get my participant record for a chat
  /// Uses auth.uid() via RLS to identify the current user
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

  /// Join a chat
  /// If user was previously kicked, reactivates their existing record
  /// Uses auth.uid() for user identification
  Future<Participant> joinChat({
    required int chatId,
    required String displayName,
    required bool isHost,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw AppException.authRequired(
        message: 'User must be signed in to join a chat',
      );
    }

    // Check if user has an existing kicked record
    final existing = await _client
        .from('participants')
        .select()
        .eq('chat_id', chatId)
        .eq('user_id', userId)
        .eq('status', 'kicked')
        .maybeSingle();

    if (existing != null) {
      // Reactivate the kicked participant
      final response = await _client
          .from('participants')
          .update({
            'status': 'active',
            'display_name': displayName,
          })
          .eq('id', existing['id'])
          .select()
          .single();
      return Participant.fromJson(response);
    }

    // No existing record, insert new participant
    final response = await _client.from('participants').insert({
      'chat_id': chatId,
      'display_name': displayName,
      'user_id': userId,
      'is_host': isHost,
      'is_authenticated': true,
      'status': 'active',
    }).select().single();

    return Participant.fromJson(response);
  }

  /// Request to join a chat (for require_approval chats)
  /// Uses auth.uid() for user identification
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

  /// Get pending join requests (for hosts)
  Future<List<Map<String, dynamic>>> getPendingRequests(int chatId) async {
    final response = await _client
        .from('join_requests')
        .select()
        .eq('chat_id', chatId)
        .eq('status', 'pending')
        .order('created_at');

    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Approve a join request (host only)
  /// Uses RPC to bypass RLS (host creates participant for requester)
  Future<void> approveRequest(int requestId) async {
    await _client.rpc('approve_join_request', params: {'p_request_id': requestId});
  }

  /// Deny a join request (host only)
  Future<void> denyRequest(int requestId) async {
    await _client
        .from('join_requests')
        .update({'status': 'denied', 'resolved_at': DateTime.now().toIso8601String()})
        .eq('id', requestId);
  }

  /// Kick a participant (host only)
  Future<void> kickParticipant(int participantId) async {
    await _client
        .from('participants')
        .update({'status': 'kicked'})
        .eq('id', participantId);
  }

  /// Leave a chat (participant removes themselves)
  /// Deletes the participant record entirely so they can rejoin cleanly
  Future<void> leaveChat(int participantId) async {
    await _client
        .from('participants')
        .delete()
        .eq('id', participantId);
  }

  /// Subscribe to participant changes
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
            // Refetch all participants on any change
            final participants = await getParticipants(chatId);
            onUpdate(participants);
          },
        )
        .subscribe();
  }

  /// Get my pending join requests (for requester's chat list)
  /// Uses auth.uid() for user identification
  Future<List<JoinRequest>> getMyPendingRequests() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('join_requests')
        .select('''
          *,
          chats!inner(name, initial_message)
        ''')
        .eq('user_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => JoinRequest.fromJson(json))
        .toList();
  }

  /// Update the per-chat viewing language for the current user's participant row
  Future<void> updateViewingLanguage(int chatId, String languageCode) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('participants')
        .update({'viewing_language_code': languageCode})
        .eq('chat_id', chatId)
        .eq('user_id', userId);
  }

  /// Cancel a pending join request (requester only)
  Future<void> cancelJoinRequest(int requestId) async {
    await _client.rpc('cancel_join_request', params: {'p_request_id': requestId});
  }

  /// Join a public chat using the display name from auth metadata.
  /// For official/public chats where users can join without approval.
  Future<Participant> joinPublicChat({
    required int chatId,
    String? displayName,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw AppException.authRequired(
        message: 'User must be signed in to join a chat',
      );
    }

    // Check if already a participant (any status)
    final existing = await _client
        .from('participants')
        .select()
        .eq('chat_id', chatId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      // Already joined - return existing record
      return Participant.fromJson(existing);
    }

    // Use provided name or fall back to auth metadata display name
    final name = displayName ??
        _client.auth.currentUser?.userMetadata?['display_name'] as String? ??
        'Anonymous';

    // Join with display name (column is NOT NULL)
    final response = await _client.from('participants').insert({
      'chat_id': chatId,
      'user_id': userId,
      'display_name': name,
      'is_host': false,
      'is_authenticated': true,
      'status': 'active',
    }).select().single();

    return Participant.fromJson(response);
  }
}
