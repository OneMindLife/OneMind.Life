import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/app_exception.dart';
import '../models/models.dart';

/// Service for chat-related database operations
class ChatService {
  final SupabaseClient _client;

  ChatService(this._client);

  /// Calculate phase end time rounded up to next :00 seconds.
  /// Aligns timer expiration with cron job schedule (every minute at :00).
  /// Example: now=1:00:42, duration=60s → 1:02:00 (not 1:01:42)
  static DateTime calculateRoundMinuteEnd(DateTime now, int durationSeconds) {
    // Truncate milliseconds to avoid extra rounding
    final nowTruncated = DateTime(
      now.year, now.month, now.day, now.hour, now.minute, now.second,
    );
    final minEnd = nowTruncated.add(Duration(seconds: durationSeconds));
    // If already at :00, use that; otherwise round up to next minute
    if (minEnd.second == 0) {
      return minEnd;
    }
    return DateTime(
      minEnd.year,
      minEnd.month,
      minEnd.day,
      minEnd.hour,
      minEnd.minute + 1,
    );
  }

  /// Get all active chats the user is participating in.
  /// Uses auth.uid() for user identification.
  /// If [languageCode] is provided, returns translated fields.
  Future<List<Chat>> getMyChats({String? languageCode}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }

    // Use translated version if language code is provided
    if (languageCode != null) {
      final response = await _client.rpc(
        'get_my_chats_translated',
        params: {
          'p_user_id': userId,
          'p_language_code': languageCode,
        },
      );

      return (response as List).map((json) => Chat.fromJson(json)).toList();
    }

    // Default: no translations
    final response = await _client
        .from('chats')
        .select('*, participants!inner(user_id, status)')
        .eq('participants.user_id', userId)
        .eq('participants.status', 'active')
        .eq('is_active', true)
        .order('last_activity_at', ascending: false);

    return (response as List).map((json) => Chat.fromJson(json)).toList();
  }

  /// Get the official OneMind chat
  Future<Chat?> getOfficialChat() async {
    final response = await _client
        .from('chats')
        .select()
        .eq('is_official', true)
        .eq('is_active', true)
        .maybeSingle();

    if (response != null) {
      return Chat.fromJson(response);
    }
    return null;
  }

  /// Get public chats for browsing/discovery
  /// Uses auth.uid() to exclude chats the user has already joined
  /// If [languageCode] is provided, returns translated fields.
  Future<List<PublicChatSummary>> getPublicChats({
    int limit = 20,
    int offset = 0,
    String? languageCode,
  }) async {
    final userId = _client.auth.currentUser?.id;

    // Use translated version if language code is provided
    if (languageCode != null) {
      final response = await _client.rpc(
        'get_public_chats_translated',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_user_id': userId,
          'p_language_code': languageCode,
        },
      );

      return (response as List)
          .map((json) => PublicChatSummary.fromJson(json))
          .toList();
    }

    // Default: no translations
    final response = await _client.rpc(
      'get_public_chats',
      params: {
        'p_limit': limit,
        'p_offset': offset,
        'p_user_id': userId,
      },
    );

    return (response as List)
        .map((json) => PublicChatSummary.fromJson(json))
        .toList();
  }

  /// Search public chats by name, description, or initial message
  /// Uses auth.uid() to exclude chats the user has already joined
  /// If [languageCode] is provided, searches both original and translated text.
  Future<List<PublicChatSummary>> searchPublicChats(
    String query, {
    int limit = 20,
    String? languageCode,
  }) async {
    final userId = _client.auth.currentUser?.id;

    // Use translated version if language code is provided
    if (languageCode != null) {
      final response = await _client.rpc(
        'search_public_chats_translated',
        params: {
          'p_query': query,
          'p_limit': limit,
          'p_user_id': userId,
          'p_language_code': languageCode,
        },
      );

      return (response as List)
          .map((json) => PublicChatSummary.fromJson(json))
          .toList();
    }

    // Default: no translations
    final response = await _client.rpc(
      'search_public_chats',
      params: {
        'p_query': query,
        'p_limit': limit,
        'p_user_id': userId,
      },
    );

    return (response as List)
        .map((json) => PublicChatSummary.fromJson(json))
        .toList();
  }

  /// Translate a chat's name, initial message, and optionally description.
  /// This invokes the translate edge function to generate translations.
  ///
  /// NOTE: Translations are now automatically triggered by database triggers
  /// on INSERT. This method is kept for manual re-translation if needed.
  ///
  /// Fire-and-forget: errors are logged but not thrown.
  Future<void> translateChat({
    required int chatId,
    required String name,
    required String initialMessage,
    String? description,
  }) async {
    try {
      // Build the texts array for batch translation
      final texts = <Map<String, String>>[
        {'text': name, 'field_name': 'name'},
        {'text': initialMessage, 'field_name': 'initial_message'},
      ];

      if (description != null && description.isNotEmpty) {
        texts.add({'text': description, 'field_name': 'description'});
      }

      await _client.functions.invoke(
        'translate',
        body: {
          'chat_id': chatId,
          'texts': texts,
        },
      );
    } catch (_) {
      // Fire-and-forget: silently ignore errors
    }
  }

  /// Get chat by invite code
  /// If [languageCode] is provided, returns translated fields.
  Future<Chat?> getChatByCode(String code, {String? languageCode}) async {
    // Use translated version if language code is provided
    if (languageCode != null) {
      final response = await _client.rpc(
        'get_chat_by_code_translated',
        params: {
          'p_invite_code': code.toUpperCase(),
          'p_language_code': languageCode,
        },
      );

      final list = response as List;
      if (list.isEmpty) return null;
      return Chat.fromJson(list.first);
    }

    // Default: use RPC to bypass restrictive SELECT policy on non-public chats
    final response = await _client.rpc(
      'get_chat_by_code',
      params: {'p_invite_code': code.toUpperCase()},
    );

    final list = response as List;
    if (list.isEmpty) return null;
    return Chat.fromJson(list.first);
  }

  /// Get chat by ID
  /// If [languageCode] is provided, returns translated fields.
  Future<Chat?> getChatById(int id, {String? languageCode}) async {
    // Use translated version if language code is provided
    if (languageCode != null) {
      final response = await _client.rpc(
        'get_chat_translated',
        params: {
          'p_chat_id': id,
          'p_language_code': languageCode,
        },
      );

      final list = response as List;
      if (list.isEmpty) return null;
      return Chat.fromJson(list.first);
    }

    // Default: no translations
    final response =
        await _client.from('chats').select().eq('id', id).maybeSingle();

    return response != null ? Chat.fromJson(response) : null;
  }

  /// Delete a chat (host only - CASCADE deletes all related data)
  Future<void> deleteChat(int chatId) async {
    await _client.from('chats').delete().eq('id', chatId);
  }

  /// Create a new chat
  /// Uses auth.uid() for creator identification
  Future<Chat> createChat({
    required String name,
    String? initialMessage,
    required AccessMethod accessMethod,
    required bool requireAuth,
    required bool requireApproval,
    required StartMode startMode,
    required String hostDisplayName,
    StartMode ratingStartMode = StartMode.auto,
    int? autoStartParticipantCount,
    required int proposingDurationSeconds,
    required int ratingDurationSeconds,
    required int proposingMinimum,
    required int ratingMinimum,
    int? proposingThresholdPercent,
    int? proposingThresholdCount,
    int? ratingThresholdPercent,
    int? ratingThresholdCount,
    required bool enableAiParticipant,
    int? aiPropositionsCount,
    required int confirmationRoundsRequired,
    required bool showPreviousResults,
    required int propositionsPerUser,
    // Adaptive duration settings (uses early advance thresholds)
    bool adaptiveDurationEnabled = false,
    int adaptiveAdjustmentPercent = 10,
    int minPhaseDurationSeconds = 60,
    int maxPhaseDurationSeconds = 86400,
    // Schedule settings (independent of startMode - controls when chat room is open)
    ScheduleType? scheduleType,
    String? scheduleTimezone,
    DateTime? scheduledStartAt,
    List<ScheduleWindow>? scheduleWindows,
    bool visibleOutsideSchedule = true,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw AppException.authRequired(
        message: 'User must be signed in to create a chat',
      );
    }
    String startModeString;
    switch (startMode) {
      case StartMode.auto:
        startModeString = 'auto';
        break;
      case StartMode.manual:
        startModeString = 'manual';
        break;
    }

    String accessMethodString;
    switch (accessMethod) {
      case AccessMethod.public:
        accessMethodString = 'public';
        break;
      case AccessMethod.inviteOnly:
        accessMethodString = 'invite_only';
        break;
      case AccessMethod.code:
        accessMethodString = 'code';
        break;
    }

    final insertData = <String, dynamic>{
      'name': name,
      'access_method': accessMethodString,
      'require_auth': requireAuth,
      'require_approval': requireApproval,
      'creator_id': userId,
      'host_display_name': hostDisplayName,
      'start_mode': startModeString,
      'rating_start_mode': ratingStartMode == StartMode.auto ? 'auto' : 'manual',
      'auto_start_participant_count': autoStartParticipantCount,
      'proposing_duration_seconds': proposingDurationSeconds,
      'rating_duration_seconds': ratingDurationSeconds,
      'proposing_minimum': proposingMinimum,
      'rating_minimum': ratingMinimum,
      'proposing_threshold_percent': proposingThresholdPercent,
      'proposing_threshold_count': proposingThresholdCount,
      'rating_threshold_percent': ratingThresholdPercent,
      'rating_threshold_count': ratingThresholdCount,
      'enable_ai_participant': enableAiParticipant,
      'ai_propositions_count': aiPropositionsCount,
      'confirmation_rounds_required': confirmationRoundsRequired,
      'show_previous_results': showPreviousResults,
      'propositions_per_user': propositionsPerUser,
      'adaptive_duration_enabled': adaptiveDurationEnabled,
      'adaptive_adjustment_percent': adaptiveAdjustmentPercent,
      'min_phase_duration_seconds': minPhaseDurationSeconds,
      'max_phase_duration_seconds': maxPhaseDurationSeconds,
    };

    // Add optional initial message if provided
    if (initialMessage != null && initialMessage.isNotEmpty) {
      insertData['initial_message'] = initialMessage;
    }

    // Add schedule fields when schedule is configured (independent of startMode)
    if (scheduleType != null) {
      insertData['schedule_type'] = scheduleType.name;
      insertData['schedule_timezone'] = scheduleTimezone ?? 'UTC';
      insertData['visible_outside_schedule'] = visibleOutsideSchedule;

      if (scheduleType == ScheduleType.once && scheduledStartAt != null) {
        insertData['scheduled_start_at'] = scheduledStartAt.toUtc().toIso8601String();
      } else if (scheduleType == ScheduleType.recurring && scheduleWindows != null && scheduleWindows.isNotEmpty) {
        insertData['schedule_windows'] = scheduleWindows.map((w) => w.toJson()).toList();
      }
    }

    final response = await _client.from('chats').insert(insertData).select().single();

    final chat = Chat.fromJson(response);

    // NOTE: Translation is now triggered automatically by database trigger
    // (translate_chat_on_insert) which calls the translate Edge Function via pg_net.
    // This is more reliable than fire-and-forget from client.

    return chat;
  }

  /// Get current cycle for a chat
  Future<Cycle?> getCurrentCycle(int chatId) async {
    final response = await _client
        .from('cycles')
        .select()
        .eq('chat_id', chatId)
        .isFilter('completed_at', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return response != null ? Cycle.fromJson(response) : null;
  }

  /// Get current round for a cycle
  Future<Round?> getCurrentRound(int cycleId) async {
    final response = await _client
        .from('rounds')
        .select()
        .eq('cycle_id', cycleId)
        .isFilter('completed_at', null)
        .order('custom_id', ascending: false)
        .limit(1)
        .maybeSingle();

    return response != null ? Round.fromJson(response) : null;
  }

  /// Get all consensus items (cycle winners) for a chat
  /// If [languageCode] is provided, returns translated content.
  Future<List<Proposition>> getConsensusItems(
    int chatId, {
    String? languageCode,
  }) async {
    final response = await _client
        .from('cycles')
        .select('''
          winning_proposition_id,
          propositions:winning_proposition_id(*)
        ''')
        .eq('chat_id', chatId)
        .not('winning_proposition_id', 'is', null)
        .order('completed_at', ascending: true);

    final List<Proposition> items = [];
    for (final cycle in response as List) {
      if (cycle['propositions'] != null) {
        items.add(Proposition.fromJson(cycle['propositions']));
      }
    }

    // If no language code or no items, return as is
    if (languageCode == null || items.isEmpty) {
      return items;
    }

    // Fetch translations for all proposition IDs
    final propositionIds = items.map((p) => p.id).toList();
    final translationsResponse = await _client
        .from('translations')
        .select('proposition_id, translated_text, language_code')
        .inFilter('proposition_id', propositionIds)
        .eq('field_name', 'content')
        .eq('language_code', languageCode);

    // Build a map of proposition_id -> translated_text
    final translationMap = <int, String>{};
    for (final t in translationsResponse as List) {
      translationMap[t['proposition_id'] as int] = t['translated_text'] as String;
    }

    // Return propositions with translations applied
    return items.map((p) {
      final translated = translationMap[p.id];
      if (translated != null) {
        return Proposition(
          id: p.id,
          roundId: p.roundId,
          participantId: p.participantId,
          content: p.content,
          createdAt: p.createdAt,
          carriedFromId: p.carriedFromId,
          finalRating: p.finalRating,
          rank: p.rank,
          contentTranslated: translated,
          translationLanguage: languageCode,
        );
      }
      return p;
    }).toList();
  }

  /// Subscribe to chat changes (updates and deletes)
  RealtimeChannel subscribeToChatChanges(
    int chatId, {
    required void Function(Map<String, dynamic>) onUpdate,
    required void Function() onDelete,
  }) {
    return _client
        .channel('chat:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: chatId,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              onDelete();
            } else if (payload.eventType == PostgresChangeEvent.update) {
              onUpdate(payload.newRecord);
            }
          },
        )
        .subscribe();
  }

  /// Subscribe to round changes for a cycle
  ///
  /// [onUpdate] receives the event type and new record (for INSERT/UPDATE)
  RealtimeChannel subscribeToRoundChanges(
    int cycleId,
    void Function(PostgresChangeEvent event, Map<String, dynamic>? newRecord)
        onUpdate,
  ) {
    return _client
        .channel('rounds:$cycleId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rounds',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'cycle_id',
            value: cycleId,
          ),
          callback: (payload) =>
              onUpdate(payload.eventType, payload.newRecord),
        )
        .subscribe();
  }

  /// Subscribe to cycle changes for a chat
  RealtimeChannel subscribeToCycleChanges(
    int chatId,
    void Function() onUpdate,
  ) {
    return _client
        .channel('cycles:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cycles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  /// Start the proposing phase for a waiting round (host only)
  Future<void> startPhase(int roundId, Chat chat) async {
    final now = DateTime.now().toUtc();

    // Only set phase_ends_at for non-manual modes
    // Manual mode = host controls everything, no timers
    final bool isManualMode = chat.startMode == StartMode.manual;
    final phaseEndsAt = isManualMode
        ? null
        : calculateRoundMinuteEnd(now, chat.proposingDurationSeconds);

    final updateData = {
      'phase': 'proposing',
      'phase_started_at': now.toIso8601String(),
    };

    if (phaseEndsAt != null) {
      updateData['phase_ends_at'] = phaseEndsAt.toIso8601String();
    }

    await _client.from('rounds').update(updateData).eq('id', roundId);
  }

  /// Start a chat by creating the initial cycle and round, then starting the proposing phase.
  /// This is called when the host clicks "Start Phase" on a chat with no existing cycle/round.
  /// Returns the created round ID.
  Future<int> startChat(int chatId, Chat chat) async {
    // Create the initial cycle
    final cycleResponse = await _client
        .from('cycles')
        .insert({'chat_id': chatId})
        .select()
        .single();

    final cycleId = cycleResponse['id'] as int;

    // Create the first round in proposing phase
    final now = DateTime.now().toUtc();

    // Only set phase_ends_at for non-manual modes (auto, scheduled)
    // Manual mode = host controls everything, no timers
    final bool isManualMode = chat.startMode == StartMode.manual;
    // Round up to next :00 for cron alignment
    final phaseEndsAt = isManualMode
        ? null
        : calculateRoundMinuteEnd(now, chat.proposingDurationSeconds);

    final roundData = {
      'cycle_id': cycleId,
      'custom_id': 1,
      'phase': 'proposing',
      'phase_started_at': now.toIso8601String(),
    };

    if (phaseEndsAt != null) {
      roundData['phase_ends_at'] = phaseEndsAt.toIso8601String();
    }

    final roundResponse = await _client.from('rounds')
        .insert(roundData)
        .select()
        .single();

    // Update chat last_activity_at
    await _client.from('chats').update({
      'last_activity_at': now.toIso8601String(),
    }).eq('id', chatId);

    return roundResponse['id'] as int;
  }

  /// Advance from proposing phase to rating phase (host only)
  Future<void> advanceToRating(int roundId, Chat chat) async {
    final now = DateTime.now().toUtc();

    // Only set phase_ends_at for non-manual modes
    final bool isManualMode = chat.startMode == StartMode.manual;
    // Round up to next :00 for cron alignment
    final phaseEndsAt = isManualMode
        ? null
        : calculateRoundMinuteEnd(now, chat.ratingDurationSeconds);

    final updateData = {
      'phase': 'rating',
      'phase_started_at': now.toIso8601String(),
    };

    if (phaseEndsAt != null) {
      updateData['phase_ends_at'] = phaseEndsAt.toIso8601String();
    }

    await _client.from('rounds').update(updateData).eq('id', roundId);
  }

  /// Complete rating phase and start a new proposing round (host only)
  /// This calculates the winner and creates a new round
  Future<void> completeRatingPhase(int roundId, int cycleId, Chat chat) async {
    final now = DateTime.now().toUtc();

    // Get all grid rankings for this round
    final rankings = await _client
        .from('grid_rankings')
        .select('proposition_id, grid_position')
        .eq('round_id', roundId);

    if ((rankings as List).isEmpty) {
      throw AppException.validation(
        message: 'No rankings submitted yet. Cannot complete rating phase without submissions.',
      );
    }

    // Calculate MOVDA scores for this round (populates proposition_movda_ratings and global_scores)
    // CRITICAL: This is the source of truth for winner selection
    // Uses host-only wrapper that validates caller is the chat host
    await _client.rpc('host_calculate_movda_scores', params: {'p_round_id': roundId});

    // Get winners from MOVDA scores (proposition_global_scores)
    // This ensures consistency with what's displayed to users
    final scores = await _client
        .from('proposition_global_scores')
        .select('proposition_id, global_score')
        .eq('round_id', roundId)
        .order('global_score', ascending: false);

    int? primaryWinnerId;
    bool isSoleWinner;
    List<Map<String, dynamic>> tiedWinners;

    if ((scores as List).isEmpty) {
      // No MOVDA scores (shouldn't happen since we have rankings), fall back to oldest proposition
      final propositions = await _client
          .from('propositions')
          .select('id')
          .eq('round_id', roundId)
          .order('created_at', ascending: true)
          .limit(1);

      if ((propositions as List).isNotEmpty) {
        primaryWinnerId = propositions.first['id'] as int;
        isSoleWinner = true;
        tiedWinners = [{'proposition_id': primaryWinnerId, 'global_score': null}];
      } else {
        throw AppException.validation(
          message: 'No propositions found for this round.',
        );
      }
    } else {
      // Find all propositions tied for first place (with tolerance matching edge function)
      const scoreTolerance = 0.001;
      final topScore = (scores.first['global_score'] as num).toDouble();
      tiedWinners = (scores as List<dynamic>)
          .where((s) {
            final score = (s['global_score'] as num).toDouble();
            return (score - topScore).abs() < scoreTolerance;
          })
          .map((s) => s as Map<String, dynamic>)
          .toList();

      isSoleWinner = tiedWinners.length == 1;
      primaryWinnerId = tiedWinners.first['proposition_id'] as int;
    }

    // Upsert ALL winners into round_winners table BEFORE setting winning_proposition_id
    // This is needed because the trigger reads from round_winners to carry forward
    // Using upsert to handle retries (if user clicks button twice)
    for (final winner in tiedWinners) {
      await _client.from('round_winners').upsert(
        {
          'round_id': roundId,
          'proposition_id': winner['proposition_id'],
          'rank': 1,
          'global_score': winner['global_score'],
        },
        onConflict: 'round_id,proposition_id',
      );
    }

    // Update current round with primary winner
    // This triggers on_round_winner_set which:
    // 1. Creates the next round (in 'waiting' phase)
    // 2. Carries forward winners automatically
    // 3. Checks for consensus
    await _client.from('rounds').update({
      'winning_proposition_id': primaryWinnerId,
      'is_sole_winner': isSoleWinner,
    }).eq('id', roundId);

    // Get current round to find the next custom_id
    final currentRound = await _client
        .from('rounds')
        .select('custom_id')
        .eq('id', roundId)
        .single();
    final nextCustomId = (currentRound['custom_id'] as int) + 1;

    // Find the next round (created by trigger) and transition to proposing phase
    final nextRound = await _client
        .from('rounds')
        .select('id, phase')
        .eq('cycle_id', cycleId)
        .eq('custom_id', nextCustomId)
        .maybeSingle();

    if (nextRound != null && nextRound['phase'] == 'waiting') {
      final bool isManualMode = chat.startMode == StartMode.manual;
      // Round up to next :00 for cron alignment
      final phaseEndsAt = isManualMode
          ? null
          : calculateRoundMinuteEnd(now, chat.proposingDurationSeconds);

      final updateData = {
        'phase': 'proposing',
        'phase_started_at': now.toIso8601String(),
      };

      if (phaseEndsAt != null) {
        updateData['phase_ends_at'] = phaseEndsAt.toIso8601String();
      }

      await _client.from('rounds').update(updateData).eq('id', nextRound['id']);
    }
  }

  /// Get the previous round winners (supports multiple tied winners) and consecutive sole wins.
  ///
  /// Returns a map with keys:
  /// - `winners`: List of RoundWinner objects
  /// - `isSoleWinner`: bool
  /// - `consecutiveSoleWins`: int
  /// - `previousRoundId`: int or null
  /// - `primaryWinnerId`: int or null
  ///
  /// If [languageCode] is provided, returns translated content.
  Future<Map<String, dynamic>> getPreviousRoundWinners(
    int cycleId, {
    String? languageCode,
  }) async {
    // Get the most recent completed round
    final roundResponse = await _client
        .from('rounds')
        .select('id, custom_id, is_sole_winner, winning_proposition_id')
        .eq('cycle_id', cycleId)
        .not('winning_proposition_id', 'is', null)
        .order('custom_id', ascending: false)
        .limit(1)
        .maybeSingle();

    if (roundResponse == null) {
      return {
        'winners': <RoundWinner>[],
        'isSoleWinner': false,
        'consecutiveSoleWins': 0,
        'previousRoundId': null,
        'primaryWinnerId': null,
      };
    }

    final previousRoundId = roundResponse['id'] as int;
    final isSoleWinner = roundResponse['is_sole_winner'] as bool? ?? true;
    final primaryWinnerId = roundResponse['winning_proposition_id'] as int;

    // Get all winners for this round from round_winners table
    final winnersResponse = await _client
        .from('round_winners')
        .select('''
          id, round_id, proposition_id, rank, global_score, created_at,
          propositions!inner(content)
        ''')
        .eq('round_id', previousRoundId)
        .eq('rank', 1)
        .order('global_score', ascending: false);

    var winners = (winnersResponse as List)
        .map((json) => RoundWinner.fromJson(json))
        .toList();

    // Apply translations if language code provided
    if (languageCode != null && winners.isNotEmpty) {
      final propositionIds = winners.map((w) => w.propositionId).toList();
      final translationsResponse = await _client
          .from('translations')
          .select('proposition_id, translated_text')
          .inFilter('proposition_id', propositionIds)
          .eq('field_name', 'content')
          .eq('language_code', languageCode);

      final translationMap = <int, String>{};
      for (final t in translationsResponse as List) {
        translationMap[t['proposition_id'] as int] = t['translated_text'] as String;
      }

      winners = winners.map((w) {
        final translated = translationMap[w.propositionId];
        if (translated != null) {
          return w.copyWith(
            contentTranslated: translated,
            translationLanguage: languageCode,
          );
        }
        return w;
      }).toList();
    }

    // Count consecutive SOLE wins of the primary winner
    int consecutiveSoleWins = 0;
    if (isSoleWinner) {
      consecutiveSoleWins = await _countConsecutiveSoleWins(cycleId, primaryWinnerId);
    }

    return {
      'winners': winners,
      'isSoleWinner': isSoleWinner,
      'consecutiveSoleWins': consecutiveSoleWins,
      'previousRoundId': previousRoundId,
      'primaryWinnerId': primaryWinnerId,
    };
  }

  /// Count consecutive SOLE wins for a proposition in a cycle.
  /// Uses root proposition IDs to track the same proposition across rounds.
  Future<int> _countConsecutiveSoleWins(int cycleId, int propositionId) async {
    final response = await _client.rpc(
      'count_consecutive_sole_wins',
      params: {
        'p_cycle_id': cycleId,
        'p_proposition_id': propositionId,
      },
    );
    return response as int;
  }

  /// @deprecated Use getPreviousRoundWinners instead
  /// Get the previous round winner and consecutive wins count for a cycle
  /// Returns: {winner: Proposition?, consecutiveWins: int, previousRoundId: int?}
  Future<Map<String, dynamic>> getPreviousRoundWinner(int cycleId) async {
    // Get all completed rounds for this cycle, ordered by custom_id descending
    final response = await _client
        .from('rounds')
        .select('''
          id,
          custom_id,
          winning_proposition_id,
          propositions:winning_proposition_id(*)
        ''')
        .eq('cycle_id', cycleId)
        .not('winning_proposition_id', 'is', null)
        .order('custom_id', ascending: false);

    final rounds = response as List;

    if (rounds.isEmpty) {
      return {'winner': null, 'consecutiveWins': 0, 'previousRoundId': null};
    }

    // Most recent winner
    final latestRound = rounds.first;
    final latestWinner = latestRound['propositions'];
    final latestWinnerId = latestRound['winning_proposition_id'];
    final previousRoundId = latestRound['id'] as int;

    // Count consecutive wins
    int consecutiveWins = 0;
    for (final round in rounds) {
      if (round['winning_proposition_id'] == latestWinnerId) {
        consecutiveWins++;
      } else {
        break;
      }
    }

    return {
      'winner': latestWinner != null ? Proposition.fromJson(latestWinner) : null,
      'consecutiveWins': consecutiveWins,
      'previousRoundId': previousRoundId,
    };
  }

  /// Pause chat manually (host only)
  /// Saves remaining timer state and stops the phase timer
  Future<void> hostPauseChat(int chatId) async {
    await _client.rpc('host_pause_chat', params: {'p_chat_id': chatId});
  }

  /// Resume chat that was manually paused (host only)
  /// Restores timer from saved state if schedule is not also paused
  Future<void> hostResumeChat(int chatId) async {
    await _client.rpc('host_resume_chat', params: {'p_chat_id': chatId});
  }
}
