import 'package:onemind_app/models/chat.dart';

/// Test fixtures for Chat model
class ChatFixtures {
  /// Valid JSON matching Supabase response
  static Map<String, dynamic> json({
    int id = 1,
    String name = 'Test Chat',
    String? initialMessage = 'What should we discuss?',
    String? description,
    String inviteCode = 'ABC123',
    String accessMethod = 'code',
    bool requireAuth = false,
    bool requireApproval = false,
    String? creatorId,
    String? creatorSessionToken = 'session-creator',
    bool isActive = true,
    bool isOfficial = false,
    DateTime? expiresAt,
    DateTime? lastActivityAt,
    String startMode = 'manual',
    int? autoStartParticipantCount,
    int proposingDurationSeconds = 86400,
    int ratingDurationSeconds = 86400,
    int proposingMinimum = 2,
    int ratingMinimum = 2,
    int? proposingThresholdPercent,
    int? proposingThresholdCount,
    int? ratingThresholdPercent,
    int? ratingThresholdCount,
    bool enableAiParticipant = false,
    int? aiPropositionsCount,
    int confirmationRoundsRequired = 2,
    bool showPreviousResults = false,
    int propositionsPerUser = 1,
    DateTime? createdAt,
    String? scheduleType,
    String scheduleTimezone = 'UTC',
    DateTime? scheduledStartAt,
    List<Map<String, String>>? scheduleWindows,
    bool visibleOutsideSchedule = true,
    bool schedulePaused = false,
    bool hostPaused = false,
    // Translation fields
    String? nameTranslated,
    String? descriptionTranslated,
    String? initialMessageTranslated,
    String? translationLanguage,
  }) {
    return {
      'id': id,
      'name': name,
      'initial_message': initialMessage,
      'description': description,
      'invite_code': inviteCode,
      'access_method': accessMethod,
      'require_auth': requireAuth,
      'require_approval': requireApproval,
      'creator_id': creatorId,
      'creator_session_token': creatorSessionToken,
      'is_active': isActive,
      'is_official': isOfficial,
      'expires_at': expiresAt?.toIso8601String(),
      'last_activity_at': lastActivityAt?.toIso8601String(),
      'start_mode': startMode,
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
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'schedule_type': scheduleType,
      'schedule_timezone': scheduleTimezone,
      'scheduled_start_at': scheduledStartAt?.toIso8601String(),
      'schedule_windows': scheduleWindows,
      'visible_outside_schedule': visibleOutsideSchedule,
      'schedule_paused': schedulePaused,
      'host_paused': hostPaused,
      'name_translated': nameTranslated,
      'description_translated': descriptionTranslated,
      'initial_message_translated': initialMessageTranslated,
      'translation_language': translationLanguage,
    };
  }

  /// Valid Chat model instance
  static Chat model({
    int id = 1,
    String name = 'Test Chat',
    String? initialMessage = 'What should we discuss?',
    String inviteCode = 'ABC123',
    bool isActive = true,
    bool isOfficial = false,
    bool hostPaused = false,
  }) {
    return Chat.fromJson(json(
      id: id,
      name: name,
      initialMessage: initialMessage,
      inviteCode: inviteCode,
      isActive: isActive,
      isOfficial: isOfficial,
      hostPaused: hostPaused,
    ));
  }

  /// Official OneMind chat
  static Chat official() {
    return Chat.fromJson(json(
      id: 1,
      name: 'OneMind',
      initialMessage: 'What should humanity focus on?',
      isOfficial: true,
    ));
  }

  /// Public discoverable chat
  static Chat public({
    int id = 1,
    String name = 'Public Chat',
    String initialMessage = 'Join the discussion!',
    String? description = 'A public chat for everyone',
  }) {
    return Chat.fromJson(json(
      id: id,
      name: name,
      initialMessage: initialMessage,
      description: description,
      accessMethod: 'public',
      inviteCode: '', // Public chats don't need invite codes
    ));
  }

  /// Chat with code access (requires invite code)
  static Chat codeAccess({
    int id = 1,
    String name = 'Code Access Chat',
    String inviteCode = 'ABC123',
  }) {
    return Chat.fromJson(json(
      id: id,
      name: name,
      inviteCode: inviteCode,
      accessMethod: 'code',
    ));
  }

  /// Chat with invite-only access (email invites)
  static Chat inviteOnly({
    int id = 1,
    String name = 'Invite Only Chat',
  }) {
    return Chat.fromJson(json(
      id: id,
      name: name,
      accessMethod: 'invite_only',
    ));
  }

  /// Chat requiring approval
  static Chat requiresApproval() {
    return Chat.fromJson(json(requireApproval: true));
  }

  /// Chat requiring authentication
  static Chat requiresAuth() {
    return Chat.fromJson(json(requireAuth: true));
  }

  /// Chat with AI enabled
  static Chat withAi({int propositionsCount = 3}) {
    return Chat.fromJson(json(
      enableAiParticipant: true,
      aiPropositionsCount: propositionsCount,
    ));
  }

  /// Chat with auto-start enabled
  static Chat withAutoStart({int participantCount = 5}) {
    return Chat.fromJson(json(
      startMode: 'auto',
      autoStartParticipantCount: participantCount,
    ));
  }

  /// Chat with multiple propositions per user
  static Chat withMultiplePropositions({int count = 3}) {
    return Chat.fromJson(json(
      propositionsPerUser: count,
    ));
  }

  /// Chat with take-profit thresholds
  static Chat withThresholds({
    int proposingPercent = 80,
    int proposingCount = 5,
    int ratingPercent = 80,
    int ratingCount = 5,
  }) {
    return Chat.fromJson(json(
      proposingThresholdPercent: proposingPercent,
      proposingThresholdCount: proposingCount,
      ratingThresholdPercent: ratingPercent,
      ratingThresholdCount: ratingCount,
    ));
  }

  /// Inactive chat
  static Chat inactive() {
    return Chat.fromJson(json(isActive: false));
  }

  /// Expired chat
  static Chat expired() {
    return Chat.fromJson(json(
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    ));
  }

  /// Chat with one-time scheduled start
  /// Note: Schedule is now independent of start_mode (facilitation)
  static Chat scheduledOnce({DateTime? startAt}) {
    return Chat.fromJson(json(
      startMode: 'manual', // Facilitation is separate from schedule
      scheduleType: 'once',
      scheduledStartAt: startAt ?? DateTime.now().add(const Duration(hours: 1)),
    ));
  }

  /// Chat with recurring schedule (e.g., weekly therapy sessions)
  /// Now uses schedule_windows for flexible scheduling.
  /// Note: Schedule is now independent of start_mode (facilitation)
  static Chat scheduledRecurring({
    List<Map<String, String>>? windows,
    String timezone = 'America/New_York',
    bool visibleOutside = true,
  }) {
    return Chat.fromJson(json(
      startMode: 'manual', // Facilitation is separate from schedule
      scheduleType: 'recurring',
      scheduleWindows: windows ?? [
        {
          'start_day': 'wednesday',
          'start_time': '10:00',
          'end_day': 'wednesday',
          'end_time': '11:00',
        }
      ],
      scheduleTimezone: timezone,
      visibleOutsideSchedule: visibleOutside,
    ));
  }

  /// Chat that is currently paused due to schedule
  /// Note: Schedule is now independent of start_mode (facilitation)
  static Chat schedulePaused() {
    return Chat.fromJson(json(
      startMode: 'manual', // Facilitation is separate from schedule
      scheduleType: 'recurring',
      scheduleWindows: [
        {
          'start_day': 'monday',
          'start_time': '09:00',
          'end_day': 'monday',
          'end_time': '10:00',
        }
      ],
      schedulePaused: true,
    ));
  }

  /// Chat with manual facilitation and auto start combined with schedule
  static Chat manualWithSchedule({
    List<Map<String, String>>? windows,
    String timezone = 'UTC',
  }) {
    return Chat.fromJson(json(
      startMode: 'manual',
      scheduleType: 'recurring',
      scheduleWindows: windows ?? [
        {
          'start_day': 'monday',
          'start_time': '09:00',
          'end_day': 'friday',
          'end_time': '17:00',
        }
      ],
      scheduleTimezone: timezone,
    ));
  }

  /// Chat with auto facilitation combined with schedule
  static Chat autoWithSchedule({
    int participantCount = 5,
    List<Map<String, String>>? windows,
    String timezone = 'UTC',
  }) {
    return Chat.fromJson(json(
      startMode: 'auto',
      autoStartParticipantCount: participantCount,
      scheduleType: 'recurring',
      scheduleWindows: windows ?? [
        {
          'start_day': 'monday',
          'start_time': '09:00',
          'end_day': 'friday',
          'end_time': '17:00',
        }
      ],
      scheduleTimezone: timezone,
    ));
  }

  /// List of chats for sidebar tests
  static List<Chat> list({int count = 3}) {
    return List.generate(
      count,
      (i) => model(
        id: i + 1,
        name: 'Chat ${i + 1}',
        inviteCode: 'CODE${i + 1}'.padRight(6, '0').substring(0, 6),
      ),
    );
  }

  /// Chat with Spanish translations
  static Chat withSpanishTranslation({
    int id = 1,
    String name = 'Test Chat',
    String initialMessage = 'What should we discuss?',
    String? description = 'A test chat description',
    String nameTranslated = 'Chat de Prueba',
    String initialMessageTranslated = 'Que deberiamos discutir?',
    String? descriptionTranslated = 'Una descripcion de chat de prueba',
  }) {
    return Chat.fromJson(json(
      id: id,
      name: name,
      initialMessage: initialMessage,
      description: description,
      nameTranslated: nameTranslated,
      initialMessageTranslated: initialMessageTranslated,
      descriptionTranslated: descriptionTranslated,
      translationLanguage: 'es',
    ));
  }

  /// Chat with translations for testing display getters
  static Chat withTranslation({
    int id = 1,
    String name = 'Original Name',
    String initialMessage = 'Original message',
    String? description = 'Original description',
    String? nameTranslated,
    String? initialMessageTranslated,
    String? descriptionTranslated,
    String? translationLanguage,
  }) {
    return Chat.fromJson(json(
      id: id,
      name: name,
      initialMessage: initialMessage,
      description: description,
      nameTranslated: nameTranslated,
      initialMessageTranslated: initialMessageTranslated,
      descriptionTranslated: descriptionTranslated,
      translationLanguage: translationLanguage,
    ));
  }
}
