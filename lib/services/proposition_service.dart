import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

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
    // Count propositions user needs to rate (excluding their own)
    final propositionsToRate = await _client
        .from('propositions')
        .select('id')
        .eq('round_id', roundId)
        .neq('participant_id', participantId);
    final totalToRate = (propositionsToRate as List).length;

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

  /// Subscribe to proposition changes (insert and delete)
  RealtimeChannel subscribeToPropositions(
    int roundId,
    void Function() onUpdate,
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
          callback: (_) => onUpdate(),
        )
        .subscribe();
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

  /// Get initial 2 random propositions for grid ranking (lazy loading)
  /// Excludes user's own propositions and any already fetched
  /// If [languageCode] is provided, returns translated content.
  Future<List<Proposition>> getInitialPropositionsForGridRanking({
    required int roundId,
    required int participantId,
    List<int> excludeIds = const [],
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

      var propositions = (response as List)
          .map((json) => Proposition.fromJson(json))
          .where((p) => p.participantId != participantId)
          .where((p) => !excludeIds.contains(p.id))
          .toList();

      // Shuffle and return first 2
      propositions.shuffle();
      return propositions.take(2).toList();
    }

    // Default: no translations
    var query = _client
        .from('propositions')
        .select()
        .eq('round_id', roundId)
        .neq('participant_id', participantId);

    if (excludeIds.isNotEmpty) {
      // Exclude already fetched propositions
      for (final id in excludeIds) {
        query = query.neq('id', id);
      }
    }

    // Get all matching, then shuffle and take 2
    final response = await query;
    final propositions = (response as List)
        .map((json) => Proposition.fromJson(json))
        .toList();

    // Shuffle and return first 2
    propositions.shuffle();
    return propositions.take(2).toList();
  }

  /// Get next random proposition for grid ranking (lazy loading)
  /// Excludes user's own propositions and any already fetched
  /// Returns null if no more propositions to rank
  /// If [languageCode] is provided, returns translated content.
  Future<Proposition?> getNextPropositionForGridRanking({
    required int roundId,
    required int participantId,
    required List<int> excludeIds,
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

      final propositions = (response as List)
          .map((json) => Proposition.fromJson(json))
          .where((p) => p.participantId != participantId)
          .where((p) => !excludeIds.contains(p.id))
          .toList();

      if (propositions.isEmpty) {
        return null; // No more propositions to rank
      }

      // Shuffle and return first one
      propositions.shuffle();
      return propositions.first;
    }

    // Default: no translations
    var query = _client
        .from('propositions')
        .select()
        .eq('round_id', roundId)
        .neq('participant_id', participantId);

    // Exclude already fetched propositions
    for (final id in excludeIds) {
      query = query.neq('id', id);
    }

    final response = await query.limit(10); // Fetch a few for randomness
    final propositions = (response as List)
        .map((json) => Proposition.fromJson(json))
        .toList();

    if (propositions.isEmpty) {
      return null; // No more propositions to rank
    }

    // Shuffle and return first one
    propositions.shuffle();
    return propositions.first;
  }

  /// Get count of remaining propositions to rank
  Future<int> getRemainingPropositionCount({
    required int roundId,
    required int participantId,
    required List<int> excludeIds,
  }) async {
    // Count propositions excluding user's own and already fetched
    final response = await _client
        .from('propositions')
        .select('id')
        .eq('round_id', roundId)
        .neq('participant_id', participantId);

    final allIds = (response as List).map((r) => r['id'] as int).toSet();
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

  /// Subscribe to skip changes for a round
  RealtimeChannel subscribeToSkips(
    int roundId,
    void Function() onUpdate,
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
          callback: (_) => onUpdate(),
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
  Future<void> skipRatingWithCleanup({
    required int roundId,
    required int participantId,
  }) async {
    await _client.rpc('skip_rating_with_cleanup', params: {
      'p_round_id': roundId,
      'p_participant_id': participantId,
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

  /// Subscribe to rating skip changes for a round
  RealtimeChannel subscribeToRatingSkips(
    int roundId,
    void Function() onUpdate,
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
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }
}
