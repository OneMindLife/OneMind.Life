import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/app_exception.dart';
import '../models/models.dart';
import 'participant_repository.dart';
import 'supabase_participant_repository.dart';

/// Backward-compatible facade over [ParticipantRepository]. New code should
/// depend on the repository directly so it can dispatch on [JoinResult] (and
/// be tested against [InMemoryParticipantRepository]). This service exists
/// to keep existing callers working without a flag-day rewrite — it
/// translates JoinResult outcomes back into the historical
/// `Participant` / `throw AppException` API.
class ParticipantService {
  final ParticipantRepository _repository;

  /// Convenience constructor for production: wires the Supabase-backed repo.
  ParticipantService(SupabaseClient client)
      : _repository = SupabaseParticipantRepository(client);

  /// Constructor used by tests / DI to inject a custom repository
  /// (e.g. [InMemoryParticipantRepository]).
  ParticipantService.withRepository(this._repository);

  /// The underlying repository — exposed so newer call sites can dispatch
  /// on [JoinResult] without going through this back-compat translation.
  ParticipantRepository get repository => _repository;

  /// Get participants for a chat
  Future<List<Participant>> getParticipants(int chatId) =>
      _repository.getParticipants(chatId);

  /// Get my participant record for a chat
  Future<Participant?> getMyParticipant(int chatId) =>
      _repository.getMyParticipant(chatId);

  /// Join a chat. Translates [JoinResult] back to the legacy API:
  ///   - Joined / Reactivated / AlreadyIn / PendingApproval → returns Participant
  ///   - CannotJoin → throws AppException with a category-appropriate message
  ///
  /// [isHost] is honored only on first-time join (chat creation flow). For
  /// every other case the underlying repository handles it: kicked users
  /// can't silently re-host, etc.
  Future<Participant> joinChat({
    required int chatId,
    required String displayName,
    required bool isHost,
  }) async {
    if (isHost) {
      return _repository.addHost(chatId: chatId, displayName: displayName);
    }
    final result = await _repository.joinChat(
      chatId: chatId,
      displayName: displayName,
    );
    return _unwrap(result);
  }

  /// Join a public chat using auth-metadata display name fallback.
  /// Same single-source-of-truth path as [joinChat] under the hood.
  Future<Participant> joinPublicChat({
    required int chatId,
    String? displayName,
  }) async {
    final name = displayName ?? _resolveAuthDisplayName();
    final result = await _repository.joinChat(
      chatId: chatId,
      displayName: name,
    );
    return _unwrap(result);
  }

  /// Read display name from Supabase auth metadata as a last-resort fallback
  /// (matches old joinPublicChat behavior).
  String _resolveAuthDisplayName() {
    final repo = _repository;
    if (repo is SupabaseParticipantRepository) {
      final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
      return (metadata?['display_name'] as String?) ?? 'Anonymous';
    }
    return 'Anonymous';
  }

  /// Translate [JoinResult] to legacy contract.
  Participant _unwrap(JoinResult result) {
    switch (result) {
      case JoinedFresh(:final participant):
      case Reactivated(:final participant):
      case AlreadyIn(:final participant):
      case PendingApproval(:final participant):
        return participant;
      case CannotJoin(:final reason):
        throw _exceptionFor(reason);
    }
  }

  AppException _exceptionFor(CannotJoinReason reason) {
    switch (reason) {
      case CannotJoinReason.authRequired:
        return AppException.authRequired(
          message: 'User must be signed in to join a chat',
        );
      case CannotJoinReason.kicked:
        return AppException.forbidden(
          message: 'You were removed from this chat. Request to rejoin.',
        );
      case CannotJoinReason.chatNotFound:
        return AppException.chatNotFound();
      case CannotJoinReason.chatNotActive:
        return AppException.forbidden(message: 'Chat is not active');
      case CannotJoinReason.chatRequiresApproval:
        return AppException.forbidden(
          message: 'Chat requires approval to join',
        );
    }
  }

  /// Request to join a chat (for require_approval chats)
  Future<void> requestToJoin({
    required int chatId,
    required String displayName,
  }) =>
      _repository.requestToJoin(chatId: chatId, displayName: displayName);

  /// Get pending join requests (for hosts)
  Future<List<Map<String, dynamic>>> getPendingRequests(int chatId) =>
      _repository.getPendingRequests(chatId);

  /// Approve a join request (host only)
  Future<void> approveRequest(int requestId) =>
      _repository.approveRequest(requestId);

  /// Deny a join request (host only)
  Future<void> denyRequest(int requestId) =>
      _repository.denyRequest(requestId);

  /// Kick a participant (host only)
  Future<void> kickParticipant(int participantId) =>
      _repository.kickParticipant(participantId);

  /// Leave a chat (soft-delete: status='left'). Preserves all the user's
  /// input for clean rejoin via [joinChat].
  Future<void> leaveChat(int participantId) =>
      _repository.leaveChat(participantId);

  /// Subscribe to participant changes
  RealtimeChannel subscribeToParticipants(
    int chatId,
    void Function(List<Participant>) onUpdate,
  ) =>
      _repository.subscribeToParticipants(chatId, onUpdate);

  /// Get my pending join requests (for requester's chat list)
  Future<List<JoinRequest>> getMyPendingRequests() =>
      _repository.getMyPendingRequests();

  /// Update the per-chat viewing language for the current user
  Future<void> updateViewingLanguage(int chatId, String languageCode) =>
      _repository.updateViewingLanguage(chatId, languageCode);

  /// Cancel a pending join request (requester only)
  Future<void> cancelJoinRequest(int requestId) =>
      _repository.cancelJoinRequest(requestId);
}
