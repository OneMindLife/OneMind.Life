import 'package:onemind_app/models/participant.dart';

/// Test fixtures for Participant model
class ParticipantFixtures {
  /// Valid JSON matching Supabase response
  static Map<String, dynamic> json({
    int id = 1,
    int chatId = 1,
    String? userId,
    String? sessionToken,
    String displayName = 'Test User',
    bool isHost = false,
    bool isAuthenticated = false,
    String status = 'active',
    DateTime? createdAt,
  }) {
    return {
      'id': id,
      'chat_id': chatId,
      'user_id': userId,
      'session_token': sessionToken ?? 'session-$id',
      'display_name': displayName,
      'is_host': isHost,
      'is_authenticated': isAuthenticated,
      'status': status,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  /// Valid Participant model instance
  static Participant model({
    int id = 1,
    int chatId = 1,
    String displayName = 'Test User',
    bool isHost = false,
    bool isAuthenticated = false,
    ParticipantStatus status = ParticipantStatus.active,
  }) {
    return Participant.fromJson(json(
      id: id,
      chatId: chatId,
      displayName: displayName,
      isHost: isHost,
      isAuthenticated: isAuthenticated,
      status: status.name,
    ));
  }

  /// Host participant
  static Participant host({int id = 1, int chatId = 1}) {
    return Participant.fromJson(json(
      id: id,
      chatId: chatId,
      displayName: 'Host User',
      isHost: true,
    ));
  }

  /// Authenticated participant
  static Participant authenticated({int id = 1, int chatId = 1}) {
    return Participant.fromJson(json(
      id: id,
      chatId: chatId,
      userId: 'user-$id',
      sessionToken: null,
      displayName: 'Auth User',
      isAuthenticated: true,
    ));
  }

  /// Pending participant (awaiting approval)
  static Participant pending({int id = 1, int chatId = 1}) {
    return Participant.fromJson(json(
      id: id,
      chatId: chatId,
      displayName: 'Pending User',
      status: 'pending',
    ));
  }

  /// Kicked participant
  static Participant kicked({int id = 1, int chatId = 1}) {
    return Participant.fromJson(json(
      id: id,
      chatId: chatId,
      displayName: 'Kicked User',
      status: 'kicked',
    ));
  }

  /// List of participants
  static List<Participant> list({
    int count = 5,
    int chatId = 1,
    bool includeHost = true,
  }) {
    final participants = <Participant>[];
    if (includeHost) {
      participants.add(host(id: 1, chatId: chatId));
    }
    final startId = includeHost ? 2 : 1;
    final remaining = includeHost ? count - 1 : count;
    for (int i = 0; i < remaining; i++) {
      participants.add(model(
        id: startId + i,
        chatId: chatId,
        displayName: 'User ${startId + i}',
      ));
    }
    return participants;
  }

  /// Mix of participant statuses
  static List<Participant> mixed({int chatId = 1}) {
    return [
      host(id: 1, chatId: chatId),
      model(id: 2, chatId: chatId, displayName: 'Active User'),
      pending(id: 3, chatId: chatId),
      kicked(id: 4, chatId: chatId),
      authenticated(id: 5, chatId: chatId),
    ];
  }
}
