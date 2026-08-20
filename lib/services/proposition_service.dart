import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'matches/match_pair_selector.dart' show PriorVote;
import 'remote_log_service.dart';
import '../utils/perf_logger.dart';

/// Exception thrown when attempting to submit a duplicate proposition.
///
/// The Edge Function detects duplicates by comparing normalized English
/// translations of propositions in the same round. Normalization uses
/// `toLowerCase().trim()` to handle case and whitespace variations.
class DuplicatePropositionException implements Exception {
  /// The ID of the existing proposition that matches the submitted content.
  final int duplicatePropositionId;

  /// Human-readable error message.
  final String message;

  DuplicatePropositionException({
    required this.duplicatePropositionId,
    this.message = 'A proposition with the same content already exists in this round',
  });

  @override
  String toString() => 'DuplicatePropositionException: $message (duplicate_id: $duplicatePropositionId)';
}

/// Service for proposition and rating operations
class PropositionService {
  final SupabaseClient _client;

  PropositionService(this._client);

  /// Get propositions for a round
  /// If [languageCode] is provided, returns translated content.
  Future<List<Proposition>> getPropositions(
    int roundId, {
    String? languageCode,
  }) async {
    // Use translated version if language code is provided
    if (languageCode != null) {
      final response = await _client.rpc(
        'get_propositions_with_translations',
        params: {
          'p_round_id': roundId,
          'p_language_code': languageCode,
        },
      );

      return (response as List).map((json) => Proposition.fromJson(json)).toList();
    }

    // Default: no translations
    final response = await _client
        .from('propositions')
        .select('''
          *,
          proposition_movda_ratings(rating)
        ''')
        .eq('round_id', roundId)
        .order('created_at');

    return (response as List).map((json) => Proposition.fromJson(json)).toList();
  }

  /// Get propositions with final MOVDA ratings (for results view)
  /// Returns propositions sorted by rating descending (highest score first)
  /// If [languageCode] is provided, returns translated content.
  Future<List<Proposition>> getPropositionsWithRatings(
    int roundId, {
    String? languageCode,
  }) async {
    // Use translated version if language code is provided
    if (languageCode != null) {
      final response = await _client.rpc(
        'get_propositions_with_translations',
        params: {
          'p_round_id': roundId,
          'p_language_code': languageCode,
        },
      );

      final propositions =
          (response as List).map((json) => Proposition.fromJson(json)).toList();

      // Sort by MOVDA rating descending
      propositions.sort((a, b) {
        final aRating = a.finalRating ?? 0;
        final bRating = b.finalRating ?? 0;
        return bRating.compareTo(aRating);
      });

      return propositions;
    }

    // Default: no translations
    final response = await _client
        .from('propositions')
        .select('*, proposition_global_scores(global_score)')
        .eq('round_id', roundId);

    final propositions =
        (response as List).map((json) => Proposition.fromJson(json)).toList();

    // Sort by MOVDA rating descending (PostgREST foreign table ordering is limited)
    propositions.sort((a, b) {
      final aRating = a.finalRating ?? 0;
      final bRating = b.finalRating ?? 0;
      return bRating.compareTo(aRating);
    });

    return propositions;
  }

  /// Count of distinct participants who rated in [roundId].
  ///
  /// Counts across BOTH rating surfaces: grid_rankings (0-100 grid mode) and
  /// rating_completions (matches/pairwise mode). A matches round has no grid_rankings,
  /// so a grid-only count would wrongly report 0 raters.
  Future<int> getRaterCount(int roundId) async {
    final raters = <int>{};
    final results = await Future.wait([
      _client.from('grid_rankings').select('participant_id').eq('round_id', roundId),
      _client.from('rating_completions').select('participant_id').eq('round_id', roundId),
    ]);
    for (final response in results) {
      for (final row in (response as List)) {
        final id = row['participant_id'];
        if (id is int) raters.add(id);
      }
    }
    return raters.length;
  }

  /// Translate a proposition using AI translation (fire-and-forget)
  /// This invokes the translate edge function to generate translations.
  ///
  /// NOTE: Translations are now automatically triggered by database triggers
  /// on INSERT. This method is kept for manual re-translation if needed.
  ///
  /// Fire-and-forget: errors are logged but not thrown.
  Future<void> translateProposition({
    required int propositionId,
    required String content,
  }) async {
    try {
      await _client.functions.invoke(
        'translate',
        body: {
          'proposition_id': propositionId,
          'text': content,
          'entity_type': 'proposition',
          'field_name': 'content',
        },
      );
    } catch (_) {
      // Fire-and-forget: silently ignore errors
    }
  }

  /// Submit a proposition with duplicate detection.
  ///
  /// Uses the `submit-proposition` Edge Function which:
  /// 1. Translates content to English using Claude Haiku
  /// 2. Normalizes: `toLowerCase().trim()`
  /// 3. Checks for duplicates in current round
  /// 4. If unique: inserts proposition and translations
  ///
  /// Throws [DuplicatePropositionException] if a proposition with the same
  /// normalized English translation already exists in the round.
  Future<Proposition> submitProposition({
    required int roundId,
    required int participantId,
    required String content,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'submit-proposition',
        body: {
          'round_id': roundId,
          'participant_id': participantId,
          'content': content,
        },
      );

      // Parse successful response
      final data = response.data as Map<String, dynamic>;
      final propositionData = data['proposition'] as Map<String, dynamic>;

      return Proposition.fromJson(propositionData);
    } on FunctionException catch (e) {
      // Handle duplicate detection (HTTP 409 Conflict)
      if (e.status == 409) {
        final details = e.details as Map<String, dynamic>?;
        if (details != null && details['code'] == 'DUPLICATE_PROPOSITION') {
          throw DuplicatePropositionException(
            duplicatePropositionId: details['duplicate_proposition_id'] as int,
            message: details['error'] as String? ??
                'A proposition with the same content already exists in this round',
          );
        }
      }

      // Capture non-duplicate edge-function failures so we can debug remotely.
      RemoteLog.log(
        'submit_proposition_fn_error',
        'FunctionException status=${e.status}',
        {
          'status': e.status,
          'details': e.details?.toString(),
          'reason_phrase': e.reasonPhrase,
          'round_id': roundId,
          'participant_id': participantId,
          'content_length': content.length,
        },
      );

      // Re-throw other FunctionExceptions
      rethrow;
    }
  }

  /// Delete a proposition (host only, during proposing phase only)
  /// Throws if the user is not the host or the round is not in proposing phase
  Future<void> deleteProposition(int propositionId) async {
    await _client.from('propositions').delete().eq('id', propositionId);
  }

  /// Get my proposition for a round (returns first one for backwards compatibility)
  Future<Proposition?> getMyProposition(
    int roundId,
    int participantId,
  ) async {
    final response = await _client
        .from('propositions')
        .select()
        .eq('round_id', roundId)
        .eq('participant_id', participantId)
        .maybeSingle();

    return response != null ? Proposition.fromJson(response) : null;
  }

  /// Get all my propositions for a round (supports multiple propositions per user)
  Future<List<Proposition>> getMyPropositions(
    int roundId,
    int participantId,
  ) async {
    final response = await _client
        .from('propositions')
        .select()
        .eq('round_id', roundId)
        .eq('participant_id', participantId)
        .order('created_at');

    return (response as List)
        .map((json) => Proposition.fromJson(json))
        .toList();
  }

  /// Submit ratings for propositions
  Future<void> submitRatings({
    required List<int> propositionIds,
    required List<int> ratings,
    required int participantId,
  }) async {
    final List<Map<String, dynamic>> data = [];
    for (var i = 0; i < propositionIds.length; i++) {
      data.add({
        'proposition_id': propositionIds[i],
        'participant_id': participantId,
        'rating': ratings[i],
      });
    }

    await _client.from('ratings').upsert(
          data,
          onConflict: 'proposition_id,participant_id',
        );
  }

  /// Check if user has completed rating this round (rated ALL propositions excluding their own)
  Future<bool> hasRated(int roundId, int participantId) async {
    final progress = await getRatingProgress(roundId, participantId);
    return progress['completed'] == true;
  }

  /// Get rating progress for a user in a round
  /// Returns: { 'rated': int, 'total': int, 'completed': bool, 'started': bool }
  Future<Map<String, dynamic>> getRatingProgress(int roundId, int participantId) async {
    // Count propositions user needs to rate: all non-own props — plus their
    // own when excluding those would leave fewer than 2 (conditional
    // self-inclusion, mirrors get_least_rated_propositions). Fetching all and
    // filtering in Dart also keeps AI (null-author) props, which `.neq` drops.
    final allProps = await _client
        .from('propositions')
        .select('id, participant_id')
        .eq('round_id', roundId);
    final all = allProps as List;
    final nonOwnCount =
        all.where((p) => p['participant_id'] != participantId).length;
    final totalToRate = nonOwnCount >= 2 ? nonOwnCount : all.length;

    // Count how many they've actually rated
    final gridRankings = await _client
        .from('grid_rankings')
        .select('id')
        .eq('round_id', roundId)
        .eq('participant_id', participantId);
    final ratedCount = (gridRankings as List).length;

    return {
      'rated': ratedCount,
      'total': totalToRate,
      'completed': ratedCount >= totalToRate && totalToRate > 0,
      'started': ratedCount > 0,
    };
  }

  /// Get my ratings for a round
  Future<Map<int, int>> getMyRatings(
    int roundId,
    int participantId,
  ) async {
    final propositions = await _client
        .from('propositions')
        .select('id')
        .eq('round_id', roundId);

    final propositionIds =
        (propositions as List).map((p) => p['id'] as int).toList();

    final ratings = await _client
        .from('ratings')
        .select('proposition_id, rating')
        .eq('participant_id', participantId)
        .inFilter('proposition_id', propositionIds);

    return Map.fromEntries(
      (ratings as List).map(
        (r) => MapEntry(r['proposition_id'] as int, r['rating'] as int),
      ),
    );
  }

  /// Subscribe to proposition changes (insert/update/delete) for a round.
  ///
  /// The callback receives the Postgres event type plus the new and old
  /// record maps so the consumer can decide whether to merge the payload
  /// directly into local state or fall back to a refetch. Calling
  /// `onUpdate(event, null, null)` is a legal pass-through if the
  /// payload is unusable (Realtime sometimes sends empty maps under
  /// row-level security); the caller should treat that as a hint to
  /// schedule a full refresh.
  RealtimeChannel subscribeToPropositions(
    int roundId,
    void Function(
      PostgresChangeEvent event,
      Map<String, dynamic>? newRecord,
      Map<String, dynamic>? oldRecord,
    ) onUpdate,
  ) {
    return _client
        .channel('propositions:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'propositions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'round_id',
            value: roundId,
          ),
          callback: (payload) => onUpdate(
            payload.eventType,
            payload.newRecord.isEmpty ? null : payload.newRecord,
            payload.oldRecord.isEmpty ? null : payload.oldRecord,
          ),
        )
        // DEBUG (perflog): log the channel's subscribe lifecycle so we can see
        // whether the host's propositions channel actually reaches SUBSCRIBED
        // (vs CHANNEL_ERROR / TIMED_OUT / CLOSED) — the live-count bug.
        .subscribe((status, [error]) {
      PerfLogger.start('rt_sub.props:$roundId', roundId: roundId, payload: {
        'status': status.name,
        if (error != null) 'error': error.toString(),
      });
    });
  }

  /// Delete a participant's grid_ranking for a single proposition.
  /// Used by the undo flow so that "Skip Rating" can re-enable once the user
  /// has undone all their placements (the rating_skips RLS policy refuses to
  /// insert if any grid_rankings rows exist for the participant in the round).
  Future<void> deleteGridRanking({
    required int roundId,
    required int propositionId,
    required int participantId,
  }) async {
    await _client
        .from('grid_rankings')
        .delete()
        .eq('round_id', roundId)
        .eq('proposition_id', propositionId)
        .eq('participant_id', participantId);
  }

  /// Count grid_rankings rows for a participant in a round. Used to gate the
  /// "Skip Rating" UI: skip is only available when this count is zero.
  Future<int> getMyRatingCount({
    required int roundId,
    required int participantId,
  }) async {
    final response = await _client
        .from('grid_rankings')
        .select('id')
        .eq('round_id', roundId)
        .eq('participant_id', participantId)
        .count(CountOption.exact);
    return response.count;
  }

  /// Submit grid rankings for propositions
  /// Grid rankings use a 0-100 scale for positioning
  Future<void> submitGridRankings({
    required int roundId,
    required Map<String, double> rankings,
    required int participantId,
  }) async {
    final List<Map<String, dynamic>> data = [];

    for (final entry in rankings.entries) {
      final propositionId = int.parse(entry.key);
      final gridPosition = entry.value;

      data.add({
        'round_id': roundId,
        'proposition_id': propositionId,
        'participant_id': participantId,
        'grid_position': gridPosition,
      });
    }

    await _client.from('grid_rankings').upsert(
      data,
      onConflict: 'round_id,proposition_id,participant_id',
    );
  }

  // ============================================================
  // Matches (pairwise) rating mode
  // ============================================================

  /// Record one pairwise match: the rater preferred [winnerPropositionId] over
  /// [loserPropositionId] (or judged them equal via [isTie]). Feeds MOVDA
  /// alongside grid_rankings. The pair-selector never re-offers a faced pair,
  /// so this is a plain insert; the UI must debounce taps to avoid a duplicate
  /// (the unique unordered-pair index would otherwise raise).
  Future<void> submitPairwiseComparison({
    required int roundId,
    required int participantId,
    required int winnerPropositionId,
    required int loserPropositionId,
    bool isTie = false,
  }) async {
    await _client.from('pairwise_comparisons').insert({
      'round_id': roundId,
      'participant_id': participantId,
      'winner_proposition_id': winnerPropositionId,
      'loser_proposition_id': loserPropositionId,
      'is_tie': isTie,
      'is_skip': false,
    });
  }

  /// Record that the rater passed on a pair (per-match skip). Inserts a
  /// pairwise_comparisons row with [propAId]/[propBId] as the (arbitrarily
  /// ordered) pair, is_tie=false, is_skip=true. The pair-selector treats this
  /// as a faced pair that counts toward both props' exposure but crowns no
  /// winner, so it is never re-offered. Idempotent — a duplicate unordered-pair
  /// insert (e.g. a debounced double-tap) raises 23505 and is ignored, mirroring
  /// [markRatingComplete].
  Future<void> submitPairwiseSkip({
    required int roundId,
    required int participantId,
    required int propAId,
    required int propBId,
  }) async {
    try {
      await _client.from('pairwise_comparisons').insert({
        'round_id': roundId,
        'participant_id': participantId,
        'winner_proposition_id': propAId,
        'loser_proposition_id': propBId,
        'is_tie': false,
        'is_skip': true,
      });
    } on PostgrestException catch (e) {
      // 23505 = unique_violation: this pair is already recorded, fine.
      if (e.code != '23505') rethrow;
    }
  }

  /// Mark that a participant finished rating this round (matches mode, written
  /// when the pair-selector is exhausted). Idempotent — a duplicate (e.g. from
  /// a panel re-mount) is ignored. Feeds matches-mode progress% + early-advance.
  Future<void> markRatingComplete({
    required int roundId,
    required int participantId,
  }) async {
    try {
      await _client.from('rating_completions').insert({
        'round_id': roundId,
        'participant_id': participantId,
      });
    } on PostgrestException catch (e) {
      // 23505 = unique_violation: already marked done, fine.
      if (e.code != '23505') rethrow;
    }
  }

  /// The matches a participant has already cast this round, as [PriorVote]s for
  /// the pair-selector (drives exposure counts + faced-pair tracking).
  Future<List<PriorVote>> getPriorPairwiseVotes({
    required int roundId,
    required int participantId,
  }) async {
    final rows = await _client
        .from('pairwise_comparisons')
        .select('winner_proposition_id, loser_proposition_id, is_tie, is_skip')
        .eq('round_id', roundId)
        .eq('participant_id', participantId);

    return rows
        .map((r) => PriorVote(
              winnerId: r['winner_proposition_id'] as int,
              loserId: r['loser_proposition_id'] as int,
              isTie: (r['is_tie'] as bool?) ?? false,
              isSkip: (r['is_skip'] as bool?) ?? false,
            ))
        .toList();
  }

  /// ALL pairwise comparisons in a round — every rater, not just one
  /// participant. Powers the live standings list shown above the duel during
  /// matches voting. RLS restricts reads to the chat's participants.
  Future<List<PriorVote>> getRoundPairwiseVotes(int roundId) async {
    final rows = await _client
        .from('pairwise_comparisons')
        .select('winner_proposition_id, loser_proposition_id, is_tie, is_skip')
        .eq('round_id', roundId);

    return rows
        .map((r) => PriorVote(
              winnerId: r['winner_proposition_id'] as int,
              loserId: r['loser_proposition_id'] as int,
              isTie: (r['is_tie'] as bool?) ?? false,
              isSkip: (r['is_skip'] as bool?) ?? false,
            ))
        .toList();
  }

  /// Get existing grid rankings for a participant in a round
  /// Returns propositions with their saved positions, or empty if none saved
  /// If [languageCode] is provided, returns translated content.
  Future<List<Map<String, dynamic>>> getExistingGridRankings({
    required int roundId,
    required int participantId,
    String? languageCode,
  }) async {
    final response = await _client
        .from('grid_rankings')
        .select('proposition_id, grid_position, propositions!inner(id, content)')
        .eq('round_id', roundId)
        .eq('participant_id', participantId);

    // If no language code or English, return original content
    if (languageCode == null || languageCode == 'en') {
      return (response as List).map((row) {
        final prop = row['propositions'] as Map<String, dynamic>;
        return {
          'id': prop['id'],
          'content': prop['content'],
          'position': (row['grid_position'] as num).toDouble(),
        };
      }).toList();
    }

    // Fetch translations for each proposition
    final propositionIds = (response as List)
        .map((row) => (row['propositions'] as Map<String, dynamic>)['id'] as int)
        .toList();

    final translations = await _client
        .from('translations')
        .select('proposition_id, translated_text')
        .inFilter('proposition_id', propositionIds)
        .eq('field_name', 'content')
        .eq('language_code', languageCode);

    final translationMap = <int, String>{};
    for (final t in translations as List) {
      translationMap[t['proposition_id'] as int] = t['translated_text'] as String;
    }

    return (response).map((row) {
      final prop = row['propositions'] as Map<String, dynamic>;
      final propId = prop['id'] as int;
      return {
        'id': propId,
        'content': translationMap[propId] ?? prop['content'],
        'position': (row['grid_position'] as num).toDouble(),
      };
    }).toList();
  }

  /// Get propositions for grid ranking (excludes user's own propositions)
  Future<List<Proposition>> getPropositionsForGridRanking(
    int roundId,
    int participantId,
  ) async {
    final response = await _client
        .from('propositions')
        .select()
        .eq('round_id', roundId)
        .neq('participant_id', participantId)
        .order('created_at');

    return (response as List).map((json) => Proposition.fromJson(json)).toList();
  }

  /// Check if user has submitted grid rankings for this round
  Future<bool> hasGridRanked(int roundId, int participantId) async {
    final response = await _client
        .from('grid_rankings')
        .select('id')
        .eq('round_id', roundId)
        .eq('participant_id', participantId)
        .limit(1);

    return (response as List).isNotEmpty;
  }

  /// Maximum ratings per user before they're flagged "done."
  ///
  /// Sized for: working memory (Miller 7±2 — ranking quality drops sharply
  /// past ~7 items as users can no longer hold the relative ordering in
  /// head); the grid UI (~6–7 cards visible without forced compression on
  /// phone); and statistical signal (7 ratings/prop yields a stable score
  /// in MOVDA aggregation). Must match the DB trigger constant `v_cap`
  /// in check_early_advance_on_rating(_skip).
  static const int kMaxRatingsPerUser = 7;

  /// Get all participant IDs who have completed rating for a round.
  ///
  /// A participant is "done" when they have rated
  /// `min(kMaxRatingsPerUser, non-self props)` propositions (matching the
  /// DB early advance trigger logic).
  Future<Set<int>> getParticipantsWhoRated(int roundId) async {
    // Get all propositions for this round with their participant_id (author)
    final propositions = await _client
        .from('propositions')
        .select('id, participant_id')
        .eq('round_id', roundId);
    final propList = propositions as List;
    final totalProps = propList.length;

    // Build map: participant_id -> count of propositions they authored
    final authoredCount = <int, int>{};
    for (final p in propList) {
      final pid = p['participant_id'];
      if (pid != null) {
        authoredCount[pid as int] = (authoredCount[pid as int] ?? 0) + 1;
      }
    }

    // Get all grid rankings for this round
    final rankings = await _client
        .from('grid_rankings')
        .select('participant_id')
        .eq('round_id', roundId)
        .not('participant_id', 'is', null);

    // Count grid_rankings per participant
    final ratedCount = <int, int>{};
    for (final r in rankings as List) {
      final pid = r['participant_id'] as int;
      ratedCount[pid] = (ratedCount[pid] ?? 0) + 1;
    }

    // A participant is done when rated count >= min(cap, votable props).
    // Votable = non-self props, or ALL props when non-self < 2 (conditional
    // self-inclusion — mirrors get_least_rated_propositions).
    final done = <int>{};
    for (final entry in ratedCount.entries) {
      final pid = entry.key;
      final rated = entry.value;
      final ownProps = authoredCount[pid] ?? 0;
      final nonSelfProps = totalProps - ownProps;
      final votable = nonSelfProps >= 2 ? nonSelfProps : totalProps;
      final required = votable < kMaxRatingsPerUser ? votable : kMaxRatingsPerUser;
      if (required > 0 && rated >= required) {
        done.add(pid);
      }
    }
    return done;
  }

  /// Get the minimum rating count across all propositions in a round.
  /// Used for the per-proposition progress bar: min_ratings / threshold × 100.
  Future<int> getMinRatingsPerProposition(int roundId) async {
    // Get all propositions for this round
    final propositions = await _client
        .from('propositions')
        .select('id')
        .eq('round_id', roundId);
    final propIds = (propositions as List).map((p) => p['id'] as int).toList();

    if (propIds.isEmpty) return 0;

    // Get all grid rankings for this round
    final rankings = await _client
        .from('grid_rankings')
        .select('proposition_id')
        .eq('round_id', roundId);

    // Count per proposition
    final counts = <int, int>{};
    for (final id in propIds) {
      counts[id] = 0;
    }
    for (final r in rankings as List) {
      final pid = r['proposition_id'] as int;
      if (counts.containsKey(pid)) {
        counts[pid] = counts[pid]! + 1;
      }
    }

    return counts.values.reduce((a, b) => a < b ? a : b);
  }

  /// Get all participant IDs who have skipped proposing for a round.
  Future<Set<int>> getParticipantsWhoSkippedProposing(int roundId) async {
    final response = await _client
        .from('round_skips')
        .select('participant_id')
        .eq('round_id', roundId);

    return (response as List)
        .map((r) => r['participant_id'] as int)
        .toSet();
  }

  /// Get all participant IDs who have skipped rating for a round.
  Future<Set<int>> getParticipantsWhoSkippedRating(int roundId) async {
    final response = await _client
        .from('rating_skips')
        .select('participant_id')
        .eq('round_id', roundId);

    return (response as List)
        .map((r) => r['participant_id'] as int)
        .toSet();
  }

  /// Get user's existing grid rankings for resuming a session
  /// Returns a map of proposition_id -> grid_position
  Future<Map<int, double>> getMyGridRankings(
    int roundId,
    int participantId,
  ) async {
    final response = await _client
        .from('grid_rankings')
        .select('proposition_id, grid_position')
        .eq('round_id', roundId)
        .eq('participant_id', participantId);

    return Map.fromEntries(
      (response as List).map(
        (r) => MapEntry(
          r['proposition_id'] as int,
          (r['grid_position'] as num).toDouble(),
        ),
      ),
    );
  }

  /// Get propositions with their global MOVDA scores for results display
  Future<List<Map<String, dynamic>>> getPropositionsWithGlobalScores(
    int roundId,
  ) async {
    final response = await _client
        .from('propositions')
        .select('''
          *,
          proposition_global_scores!inner(global_score, last_updated)
        ''')
        .eq('round_id', roundId)
        .order('proposition_global_scores(global_score)', ascending: false);

    return (response as List).cast<Map<String, dynamic>>();
  }

  /// Subscribe to MOVDA score updates (real-time leaderboard)
  RealtimeChannel subscribeToGlobalScores(
    int roundId,
    void Function() onUpdate,
  ) {
    return _client
        .channel('global_scores:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'proposition_global_scores',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'round_id',
            value: roundId,
          ),
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  /// Get propositions with MOVDA scores using SQL function
  /// Returns propositions ordered by score (best first)
  Future<List<Map<String, dynamic>>> getPropositionsWithScores(
    int roundId,
  ) async {
    final response = await _client.rpc(
      'get_propositions_with_scores',
      params: {'p_round_id': roundId},
    );

    return (response as List).cast<Map<String, dynamic>>();
  }

  /// Get unranked propositions for a user
  /// Returns propositions the user hasn't ranked yet (excludes their own)
  Future<List<Map<String, dynamic>>> getUnrankedPropositions({
    required int roundId,
    int? participantId,
    String? sessionToken,
  }) async {
    final response = await _client.rpc(
      'get_unranked_propositions',
      params: {
        'p_round_id': roundId,
        if (participantId != null) 'p_participant_id': participantId,
        if (sessionToken != null) 'p_session_token': sessionToken,
      },
    );

    return (response as List).cast<Map<String, dynamic>>();
  }

  /// Manually trigger MOVDA score calculation for a round
  /// This is usually called automatically by the trigger, but can be
  /// called manually for testing or recalculation
  Future<void> calculateMovdaScores(int roundId, {double? seed}) async {
    await _client.rpc(
      'calculate_movda_scores_for_round',
      params: {
        'p_round_id': roundId,
        if (seed != null) 'p_seed': seed,
      },
    );
  }

  /// Get initial 2 least-rated propositions for grid ranking (lazy loading).
  /// Selects propositions with the fewest ratings first to ensure even coverage.
  /// Excludes user's own propositions and any already fetched.
  /// If [languageCode] is provided, returns translated content.
  Future<List<Proposition>> getInitialPropositionsForGridRanking({
    required int roundId,
    required int participantId,
    List<int> excludeIds = const [],
    String? languageCode,
  }) async {
    final response = await _client.rpc(
      'get_least_rated_propositions',
      params: {
        'p_round_id': roundId,
        'p_participant_id': participantId,
        'p_count': 2,
        'p_exclude_ids': excludeIds,
      },
    );

    var propositions = (response as List)
        .map((json) => Proposition.fromJson(json))
        .toList();

    // If translations needed, fetch them separately
    if (languageCode != null && propositions.isNotEmpty) {
      propositions = await _applyTranslations(propositions, roundId, languageCode);
    }

    return propositions;
  }

  /// Get next least-rated proposition for grid ranking (lazy loading).
  /// Picks the proposition with the fewest ratings that the user hasn't
  /// rated yet. Returns null if no more propositions to rank.
  /// If [languageCode] is provided, returns translated content.
  Future<Proposition?> getNextPropositionForGridRanking({
    required int roundId,
    required int participantId,
    required List<int> excludeIds,
    String? languageCode,
  }) async {
    final response = await _client.rpc(
      'get_least_rated_proposition',
      params: {
        'p_round_id': roundId,
        'p_participant_id': participantId,
        'p_exclude_ids': excludeIds,
      },
    );

    final results = response as List;
    if (results.isEmpty) {
      return null;
    }

    var proposition = Proposition.fromJson(results.first);

    if (languageCode != null) {
      final translated = await _applyTranslations([proposition], roundId, languageCode);
      proposition = translated.first;
    }

    return proposition;
  }

  /// Apply translations to a list of propositions using the translations RPC.
  Future<List<Proposition>> _applyTranslations(
    List<Proposition> propositions,
    int roundId,
    String languageCode,
  ) async {
    final translationResponse = await _client.rpc(
      'get_propositions_with_translations',
      params: {
        'p_round_id': roundId,
        'p_language_code': languageCode,
      },
    );

    final translationMap = <int, Map<String, dynamic>>{};
    for (final t in translationResponse as List) {
      translationMap[t['id'] as int] = t;
    }

    return propositions.map((p) {
      final t = translationMap[p.id];
      if (t != null) {
        return Proposition.fromJson(t);
      }
      return p;
    }).toList();
  }

  /// Get count of remaining propositions to rank
  Future<int> getRemainingPropositionCount({
    required int roundId,
    required int participantId,
    required List<int> excludeIds,
  }) async {
    // Count votable propositions not yet fetched. Votable = all props except
    // the user's own — unless that leaves fewer than 2, in which case own
    // props are votable too (conditional self-inclusion, mirrors
    // get_least_rated_propositions). Dart-side filter also keeps AI
    // (null-author) props, which `.neq` drops.
    final response = await _client
        .from('propositions')
        .select('id, participant_id')
        .eq('round_id', roundId);

    final all = response as List;
    final nonOwn =
        all.where((p) => p['participant_id'] != participantId).toList();
    final votable = nonOwn.length >= 2 ? nonOwn : all;

    final allIds = votable.map((r) => r['id'] as int).toSet();
    final excludeSet = excludeIds.toSet();
    final remaining = allIds.difference(excludeSet);

    return remaining.length;
  }

  /// Get user round ranks for leaderboard display.
  /// Returns all users sorted by rank descending (highest first).
  Future<List<UserRoundRank>> getUserRoundRanks({
    required int roundId,
    required int myParticipantId,
  }) async {
    final response = await _client
        .from('user_round_ranks')
        .select('*, participants!inner(display_name)')
        .eq('round_id', roundId);

    final allRanks = (response as List)
        .map((json) => UserRoundRank.fromJson(json))
        .toList();

    if (allRanks.isEmpty) {
      return [];
    }

    // Sort by rank descending (highest first)
    allRanks.sort((a, b) => b.rank.compareTo(a.rank));

    return allRanks;
  }

  // ==========================================================================
  // Skip Proposing Methods
  // ==========================================================================

  /// Skip proposing for the current round.
  /// User must not have already submitted a proposition.
  /// Skip quota must not be exceeded.
  Future<RoundSkip> skipProposing({
    required int roundId,
    required int participantId,
  }) async {
    final response = await _client.from('round_skips').insert({
      'round_id': roundId,
      'participant_id': participantId,
    }).select().single();

    return RoundSkip.fromJson(response);
  }

  /// Get all skips for a round
  Future<List<RoundSkip>> getSkipsForRound(int roundId) async {
    final response = await _client
        .from('round_skips')
        .select()
        .eq('round_id', roundId);

    return (response as List).map((json) => RoundSkip.fromJson(json)).toList();
  }

  /// Get skip count for a round
  Future<int> getSkipCount(int roundId) async {
    final response = await _client
        .from('round_skips')
        .select('id')
        .eq('round_id', roundId);

    return (response as List).length;
  }

  /// Check if a participant has skipped this round
  Future<bool> hasSkipped(int roundId, int participantId) async {
    final response = await _client
        .from('round_skips')
        .select('id')
        .eq('round_id', roundId)
        .eq('participant_id', participantId)
        .maybeSingle();

    return response != null;
  }

  /// Subscribe to round_skips changes for a round. Same payload-passing
  /// contract as [subscribeToPropositions] — see that method for details.
  RealtimeChannel subscribeToSkips(
    int roundId,
    void Function(
      PostgresChangeEvent event,
      Map<String, dynamic>? newRecord,
      Map<String, dynamic>? oldRecord,
    ) onUpdate,
  ) {
    return _client
        .channel('round_skips:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'round_skips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'round_id',
            value: roundId,
          ),
          callback: (payload) => onUpdate(
            payload.eventType,
            payload.newRecord.isEmpty ? null : payload.newRecord,
            payload.oldRecord.isEmpty ? null : payload.oldRecord,
          ),
        )
        .subscribe();
  }

  // ==========================================================================
  // Rating Skip Methods
  // ==========================================================================

  /// Skip rating for the current round.
  /// User must not have already rated.
  /// Skip quota must not be exceeded.
  Future<RatingSkip> skipRating({
    required int roundId,
    required int participantId,
  }) async {
    final response = await _client.from('rating_skips').insert({
      'round_id': roundId,
      'participant_id': participantId,
    }).select().single();

    return RatingSkip.fromJson(response);
  }

  /// Skip rating with cleanup — deletes any intermediate grid_rankings first.
  /// Used when skipping from inside the rating screen.
  ///
  /// Optional [correlationId] threads the caller's perf-log correlation
  /// into the DB function so its start/end log_perf rows share the ID
  /// with Flutter-side rows.
  Future<void> skipRatingWithCleanup({
    required int roundId,
    required int participantId,
    String? correlationId,
  }) async {
    await _client.rpc('skip_rating_with_cleanup', params: {
      'p_round_id': roundId,
      'p_participant_id': participantId,
      if (correlationId != null) 'p_correlation_id': correlationId,
    });
  }

  /// Get rating skip count for a round
  Future<int> getRatingSkipCount(int roundId) async {
    final response = await _client
        .from('rating_skips')
        .select('id')
        .eq('round_id', roundId);

    return (response as List).length;
  }

  /// Check if a participant has skipped rating this round
  Future<bool> hasSkippedRating(int roundId, int participantId) async {
    final response = await _client
        .from('rating_skips')
        .select('id')
        .eq('round_id', roundId)
        .eq('participant_id', participantId)
        .maybeSingle();

    return response != null;
  }

  /// Subscribe to rating_skips changes for a round. Same payload-passing
  /// contract as [subscribeToPropositions] — see that method for details.
  RealtimeChannel subscribeToRatingSkips(
    int roundId,
    void Function(
      PostgresChangeEvent event,
      Map<String, dynamic>? newRecord,
      Map<String, dynamic>? oldRecord,
    ) onUpdate,
  ) {
    return _client
        .channel('rating_skips:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rating_skips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'round_id',
            value: roundId,
          ),
          callback: (payload) => onUpdate(
            payload.eventType,
            payload.newRecord.isEmpty ? null : payload.newRecord,
            payload.oldRecord.isEmpty ? null : payload.oldRecord,
          ),
        )
        .subscribe();
  }

  /// Subscribe to grid ranking changes for a round (rating participation updates).
  RealtimeChannel subscribeToGridRankings(
    int roundId,
    void Function() onUpdate,
  ) {
    return _client
        .channel('grid_rankings:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'grid_rankings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'round_id',
            value: roundId,
          ),
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  /// Subscribe to rating_completions for a round. Fires once per rater when
  /// they finish rating (grid batch submit or matches pair-exhaustion), so
  /// the Done tags and matches progress bar tick live for other viewers.
  /// Same payload-passing contract as [subscribeToRatingSkips].
  RealtimeChannel subscribeToRatingCompletions(
    int roundId,
    void Function(
      PostgresChangeEvent event,
      Map<String, dynamic>? newRecord,
      Map<String, dynamic>? oldRecord,
    ) onUpdate,
  ) {
    return _client
        .channel('rating_completions:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rating_completions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'round_id',
            value: roundId,
          ),
          callback: (payload) => onUpdate(
            payload.eventType,
            payload.newRecord.isEmpty ? null : payload.newRecord,
            payload.oldRecord.isEmpty ? null : payload.oldRecord,
          ),
        )
        .subscribe();
  }
}
