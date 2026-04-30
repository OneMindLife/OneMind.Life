import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Outcome of a join attempt. Callers that care about *what happened* can
/// dispatch on this; callers that don't can use ParticipantService.joinChat,
/// which discards the outcome and returns a Participant.
sealed class JoinResult {
  const JoinResult();
  Participant get participant;
}

/// First-time join — a fresh row was inserted.
class JoinedFresh extends JoinResult {
  @override
  final Participant participant;
  const JoinedFresh(this.participant);
}

/// User had previously left and is now back; status flipped left → active.
class Reactivated extends JoinResult {
  @override
  final Participant participant;
  const Reactivated(this.participant);
}

/// User was already an active participant; no DB change.
class AlreadyIn extends JoinResult {
  @override
  final Participant participant;
  const AlreadyIn(this.participant);
}

/// User has a pending join request awaiting host approval.
class PendingApproval extends JoinResult {
  @override
  final Participant participant;
  const PendingApproval(this.participant);
}

/// Reasons a join was refused. Callers can render the right error message.
enum CannotJoinReason {
  kicked,
  chatNotFound,
  chatNotActive,
  chatRequiresApproval,
  authRequired,
}

/// Join was refused. participant is null because no row exists / matches.
class CannotJoin extends JoinResult {
  final CannotJoinReason reason;
  const CannotJoin(this.reason);

  @override
  Participant get participant =>
      throw StateError('CannotJoin has no participant ($reason)');
}

/// Repository abstraction over participant storage. Two impls:
///   - [SupabaseParticipantRepository]  : production, talks to Supabase
///   - [InMemoryParticipantRepository]  : tests, in-memory state
///
/// All "join" operations route through a single point so that branching
/// (fresh insert vs reactivation vs already-in vs kicked) can never drift
/// between client and server.
abstract class ParticipantRepository {
  /// Regular user joining a chat. The chat must exist, be active, and have
  /// access_method 'public' or 'code'. If the user previously left, their
  /// row is flipped back to active. Kicked users are NOT auto-reactivated;
  /// they must go through [requestToJoin] + host approval.
  Future<JoinResult> joinChat({
    required int chatId,
    required String displayName,
  });

  /// Add the chat creator as the host participant. Bypasses normal access
  /// checks because the creator is creating the chat in the same transaction.
  /// Distinct from joinChat to keep "user-initiated join" auth surface separate
  /// from "host registration."
  Future<Participant> addHost({
    required int chatId,
    required String displayName,
  });

  /// Submit a join request for a require_approval chat. Returns once the
  /// request row is created; host approval is asynchronous.
  Future<void> requestToJoin({
    required int chatId,
    required String displayName,
  });

  /// Soft-delete leave (status='left'). Preserves the participant's input
  /// (propositions, ratings, skips, leaderboard rankings, billing). Rejoin
  /// flips the same row back to active via [joinChat].
  Future<void> leaveChat(int participantId);

  /// Host-only: kick a participant (status='kicked'). Kicked users do NOT
  /// auto-rejoin — they must go through requestToJoin + approval.
  Future<void> kickParticipant(int participantId);

  /// Approve a pending join request (host action via SECURITY DEFINER RPC).
  Future<void> approveRequest(int requestId);

  /// Deny a pending join request (host action).
  Future<void> denyRequest(int requestId);

  /// Cancel a pending request as the requester.
  Future<void> cancelJoinRequest(int requestId);

  /// All active participants in a chat, ordered by display_name.
  Future<List<Participant>> getParticipants(int chatId);

  /// The current user's participant row in a chat (any status), or null.
  Future<Participant?> getMyParticipant(int chatId);

  /// Pending requests filed by the current user across all chats.
  Future<List<JoinRequest>> getMyPendingRequests();

  /// Pending requests waiting for the host of [chatId].
  Future<List<Map<String, dynamic>>> getPendingRequests(int chatId);

  /// Update the per-chat viewing language for the current user.
  Future<void> updateViewingLanguage(int chatId, String languageCode);

  /// Subscribe to realtime participant changes for [chatId]. Returns the
  /// underlying channel so callers can manage its lifecycle.
  RealtimeChannel subscribeToParticipants(
    int chatId,
    void Function(List<Participant>) onUpdate,
  );
}
