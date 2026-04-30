import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'participant_repository.dart';

/// In-memory [ParticipantRepository] for unit tests. Simulates the contract
/// of [SupabaseParticipantRepository] (and the underlying RPC) without
/// touching Supabase.
///
/// Construct with a chat configuration map; call [setCurrentUserId] to
/// simulate `auth.uid()`. The repository enforces the same invariants as
/// the production stack: kicked stays kicked, left flips to active on
/// rejoin, fresh joins INSERT, duplicates collapse to AlreadyIn.
class InMemoryParticipantRepository implements ParticipantRepository {
  final Map<int, ChatStub> _chats;
  final List<Participant> _participants = [];
  final List<JoinRequest> _joinRequests = [];
  int _nextParticipantId = 1;
  int _nextRequestId = 1;
  String? _currentUserId;

  InMemoryParticipantRepository({Map<int, ChatStub>? chats})
      : _chats = chats ?? {};

  void setCurrentUserId(String? userId) => _currentUserId = userId;

  void addChat(ChatStub chat) => _chats[chat.id] = chat;

  /// Test helpers — direct state inspection / setup.
  List<Participant> get allParticipants => List.unmodifiable(_participants);

  Participant? participantFor({required int chatId, required String userId}) {
    for (final p in _participants) {
      if (p.chatId == chatId && p.userId == userId) return p;
    }
    return null;
  }

  /// Seed a participant directly (e.g. to set up a 'left' or 'kicked' state).
  void seedParticipant({
    required int chatId,
    required String userId,
    required String displayName,
    ParticipantStatus status = ParticipantStatus.active,
    bool isHost = false,
  }) {
    _participants.add(Participant(
      id: _nextParticipantId++,
      chatId: chatId,
      userId: userId,
      displayName: displayName,
      isHost: isHost,
      isAuthenticated: true,
      status: status,
      createdAt: DateTime.now(),
    ));
  }

  // ===========================================================================
  // ParticipantRepository implementation
  // ===========================================================================

  @override
  Future<JoinResult> joinChat({
    required int chatId,
    required String displayName,
  }) async {
    final userId = _currentUserId;
    if (userId == null) return const CannotJoin(CannotJoinReason.authRequired);

    final chat = _chats[chatId];
    if (chat == null) return const CannotJoin(CannotJoinReason.chatNotFound);
    if (!chat.isActive) return const CannotJoin(CannotJoinReason.chatNotActive);
    if (chat.accessMethod != 'public' && chat.accessMethod != 'code') {
      return const CannotJoin(CannotJoinReason.chatRequiresApproval);
    }

    final existing = participantFor(chatId: chatId, userId: userId);

    if (existing == null) {
      final fresh = Participant(
        id: _nextParticipantId++,
        chatId: chatId,
        userId: userId,
        displayName: displayName,
        isHost: false,
        isAuthenticated: true,
        status: ParticipantStatus.active,
        createdAt: DateTime.now(),
      );
      _participants.add(fresh);
      return JoinedFresh(fresh);
    }

    switch (existing.status) {
      case ParticipantStatus.active:
        return AlreadyIn(existing);
      case ParticipantStatus.kicked:
        return const CannotJoin(CannotJoinReason.kicked);
      case ParticipantStatus.pending:
        return PendingApproval(existing);
      case ParticipantStatus.left:
        // Reactivate: same id, status flips to active, display_name refreshes
        final reactivated = Participant(
          id: existing.id,
          chatId: existing.chatId,
          userId: existing.userId,
          sessionToken: existing.sessionToken,
          displayName: displayName,
          isHost: existing.isHost,
          isAuthenticated: existing.isAuthenticated,
          status: ParticipantStatus.active,
          createdAt: existing.createdAt,
        );
        _replace(reactivated);
        return Reactivated(reactivated);
    }
  }

  @override
  Future<Participant> addHost({
    required int chatId,
    required String displayName,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw StateError('addHost called with no current user');
    }
    final host = Participant(
      id: _nextParticipantId++,
      chatId: chatId,
      userId: userId,
      displayName: displayName,
      isHost: true,
      isAuthenticated: true,
      status: ParticipantStatus.active,
      createdAt: DateTime.now(),
    );
    _participants.add(host);
    return host;
  }

  @override
  Future<void> requestToJoin({
    required int chatId,
    required String displayName,
  }) async {
    final userId = _currentUserId;
    if (userId == null) return;
    _joinRequests.add(JoinRequest(
      id: _nextRequestId++,
      chatId: chatId,
      userId: userId,
      displayName: displayName,
      isAuthenticated: true,
      status: JoinRequestStatus.pending,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> leaveChat(int participantId) async {
    final i = _participants.indexWhere((p) => p.id == participantId);
    if (i == -1) return;
    final p = _participants[i];
    _participants[i] = Participant(
      id: p.id,
      chatId: p.chatId,
      userId: p.userId,
      sessionToken: p.sessionToken,
      displayName: p.displayName,
      isHost: p.isHost,
      isAuthenticated: p.isAuthenticated,
      status: ParticipantStatus.left,
      createdAt: p.createdAt,
    );
  }

  @override
  Future<void> kickParticipant(int participantId) async {
    final i = _participants.indexWhere((p) => p.id == participantId);
    if (i == -1) return;
    final p = _participants[i];
    _participants[i] = Participant(
      id: p.id,
      chatId: p.chatId,
      userId: p.userId,
      sessionToken: p.sessionToken,
      displayName: p.displayName,
      isHost: p.isHost,
      isAuthenticated: p.isAuthenticated,
      status: ParticipantStatus.kicked,
      createdAt: p.createdAt,
    );
  }

  @override
  Future<void> approveRequest(int requestId) async {
    final i = _joinRequests.indexWhere((r) => r.id == requestId);
    if (i == -1) return;
    final r = _joinRequests[i];
    _participants.add(Participant(
      id: _nextParticipantId++,
      chatId: r.chatId,
      userId: r.userId,
      displayName: r.displayName,
      isHost: false,
      isAuthenticated: r.isAuthenticated,
      status: ParticipantStatus.active,
      createdAt: DateTime.now(),
    ));
    _joinRequests.removeAt(i);
  }

  @override
  Future<void> denyRequest(int requestId) async {
    _joinRequests.removeWhere((r) => r.id == requestId);
  }

  @override
  Future<void> cancelJoinRequest(int requestId) async {
    _joinRequests.removeWhere((r) => r.id == requestId);
  }

  @override
  Future<List<Participant>> getParticipants(int chatId) async {
    final list = _participants
        .where((p) => p.chatId == chatId && p.status == ParticipantStatus.active)
        .toList();
    list.sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  @override
  Future<Participant?> getMyParticipant(int chatId) async {
    final userId = _currentUserId;
    if (userId == null) return null;
    return participantFor(chatId: chatId, userId: userId);
  }

  @override
  Future<List<JoinRequest>> getMyPendingRequests() async {
    final userId = _currentUserId;
    if (userId == null) return [];
    return _joinRequests
        .where((r) => r.userId == userId && r.status == JoinRequestStatus.pending)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingRequests(int chatId) async {
    return _joinRequests
        .where((r) => r.chatId == chatId && r.status == JoinRequestStatus.pending)
        .map((r) => {
              'id': r.id,
              'chat_id': r.chatId,
              'user_id': r.userId,
              'display_name': r.displayName,
              'status': r.status.name,
            })
        .toList();
  }

  @override
  Future<void> updateViewingLanguage(int chatId, String languageCode) async {
    // No-op: model doesn't expose viewing_language_code; tests can ignore.
  }

  @override
  RealtimeChannel subscribeToParticipants(
    int chatId,
    void Function(List<Participant>) onUpdate,
  ) {
    throw UnsupportedError(
      'InMemoryParticipantRepository does not implement realtime subscriptions',
    );
  }

  void _replace(Participant updated) {
    final i = _participants.indexWhere((p) => p.id == updated.id);
    if (i != -1) _participants[i] = updated;
  }
}

/// Minimal stub of a chat row for the in-memory repo to make access
/// decisions. Only the fields actually consulted are modeled.
class ChatStub {
  final int id;
  final bool isActive;
  final String accessMethod; // 'public', 'code', 'invite_only'

  const ChatStub({
    required this.id,
    this.isActive = true,
    this.accessMethod = 'public',
  });
}
