import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reasons the [AffirmationService.affirm] RPC can refuse. The
/// migration's `affirm_round` function maps each rejection path to a
/// distinct sqlstate (P0001–P0007); see
/// supabase/migrations/20260430180000_add_affirmations.sql.
enum AffirmationFailure {
  notAuthenticated,
  notActiveParticipant,
  wrongPhase,
  notAllowed,
  noPreviousWinner,
  alreadySubmitted,
  alreadySkipped,
  alreadyAffirmed,
  unknown,
}

/// Thrown by [AffirmationService.affirm] when the server rejects the call.
/// Callers should map [reason] to localized user-facing copy and decide
/// whether to revert any optimistic state update.
class AffirmationException implements Exception {
  final AffirmationFailure reason;
  final String message;

  AffirmationException(this.reason, this.message);

  @override
  String toString() => 'AffirmationException(${reason.name}): $message';
}

/// Service for the affirmation feature — the user explicitly endorses
/// the carried-forward winner instead of submitting a new proposition.
/// When all active participants affirm (zero new submissions), the round
/// auto-resolves with the carried winner re-winning. See
/// docs/planning/AFFIRMATION_FEATURE.md.
class AffirmationService {
  final SupabaseClient _client;

  AffirmationService(this._client);

  /// Records the caller's affirmation for [roundId]. Returns the new
  /// `affirmations.id` on success. Throws [AffirmationException] with a
  /// specific [AffirmationFailure] reason for any rejection path. The
  /// reason maps from the server's sqlstate codes; an unrecognized error
  /// becomes [AffirmationFailure.unknown] with the underlying message
  /// preserved for logging.
  Future<int> affirm(int roundId) async {
    try {
      final response = await _client.rpc(
        'affirm_round',
        params: {'p_round_id': roundId},
      );
      // The RPC returns a BIGINT; supabase_flutter decodes that as int.
      return (response as num).toInt();
    } on PostgrestException catch (e) {
      throw AffirmationException(failureFromCode(e.code), e.message);
    }
  }

  /// Number of affirmations for the given round (regardless of who).
  /// Drives the participation % bar so other users' affirmations are
  /// reflected client-side.
  Future<int> getAffirmationCount(int roundId) async {
    final response = await _client
        .from('affirmations')
        .count(CountOption.exact)
        .eq('round_id', roundId);
    return response;
  }

  /// True if [participantId] already has an affirmation row for [roundId].
  /// Used to gate the Affirm button after a hot restart.
  Future<bool> hasAffirmed({
    required int roundId,
    required int participantId,
  }) async {
    final response = await _client
        .from('affirmations')
        .select('id')
        .eq('round_id', roundId)
        .eq('participant_id', participantId)
        .limit(1);
    return (response as List).isNotEmpty;
  }

  /// Set of participant ids that have affirmed the given round.
  /// Used by the chat screen's participation % calculation.
  Future<Set<int>> getParticipantsWhoAffirmed(int roundId) async {
    final response = await _client
        .from('affirmations')
        .select('participant_id')
        .eq('round_id', roundId);
    return (response as List)
        .map((row) => row['participant_id'] as int)
        .toSet();
  }

  /// Realtime subscription to affirmation events for [roundId]. Mirrors
  /// the round-skips subscription pattern. Caller cancels via the
  /// returned channel's `unsubscribe()`.
  RealtimeChannel subscribeToAffirmations(
    int roundId,
    void Function() onUpdate,
  ) {
    return _client
        .channel('affirmations:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'affirmations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'round_id',
            value: roundId,
          ),
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  /// Maps the sqlstate codes raised by the `affirm_round` RPC to a typed
  /// reason. Exposed for unit testing — the migration assigns codes
  /// P0001–P0007 (see the migration's RPC definition).
  @visibleForTesting
  static AffirmationFailure failureFromCode(String? code) {
    switch (code) {
      case '42501':
        return AffirmationFailure.notAuthenticated;
      case 'P0001':
        return AffirmationFailure.notActiveParticipant;
      case 'P0002':
        return AffirmationFailure.wrongPhase;
      case 'P0003':
        return AffirmationFailure.notAllowed;
      case 'P0004':
        return AffirmationFailure.noPreviousWinner;
      case 'P0005':
        return AffirmationFailure.alreadySubmitted;
      case 'P0006':
        return AffirmationFailure.alreadySkipped;
      case 'P0007':
        return AffirmationFailure.alreadyAffirmed;
      default:
        return AffirmationFailure.unknown;
    }
  }
}
