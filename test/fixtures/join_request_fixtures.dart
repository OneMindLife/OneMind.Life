import 'package:onemind_app/models/join_request.dart';

class JoinRequestFixtures {
  /// Fixed date for equality testing
  static final DateTime _fixedDate = DateTime.utc(2024, 1, 1);

  static Map<String, dynamic> json({
    int id = 1,
    int chatId = 1,
    String? sessionToken = 'test-session-token',
    String? userId,
    String displayName = 'Test Requester',
    bool isAuthenticated = false,
    String status = 'pending',
    String? chatName = 'Test Chat',
    String? chatInitialMessage = 'Welcome!',
  }) {
    return {
      'id': id,
      'chat_id': chatId,
      'session_token': sessionToken,
      'user_id': userId,
      'display_name': displayName,
      'is_authenticated': isAuthenticated,
      'status': status,
      'created_at': _fixedDate.toIso8601String(),
      if (chatName != null)
        'chats': {
          'name': chatName,
          'initial_message': chatInitialMessage,
        },
    };
  }

  static JoinRequest model({
    int id = 1,
    int chatId = 1,
    String? sessionToken = 'test-session-token',
    String? userId,
    String displayName = 'Test Requester',
    bool isAuthenticated = false,
    JoinRequestStatus status = JoinRequestStatus.pending,
    String? chatName = 'Test Chat',
    String? chatInitialMessage = 'Welcome!',
  }) {
    return JoinRequest(
      id: id,
      chatId: chatId,
      sessionToken: sessionToken,
      userId: userId,
      displayName: displayName,
      isAuthenticated: isAuthenticated,
      status: status,
      createdAt: _fixedDate,
      chatName: chatName,
      chatInitialMessage: chatInitialMessage,
    );
  }

  static List<JoinRequest> list({int count = 3}) {
    return List.generate(
      count,
      (i) => model(
        id: i + 1,
        chatId: i + 1,
        displayName: 'Requester ${i + 1}',
        chatName: 'Chat ${i + 1}',
      ),
    );
  }

  static JoinRequest approved({int id = 1, int chatId = 1}) {
    return model(
      id: id,
      chatId: chatId,
      status: JoinRequestStatus.approved,
    );
  }

  static JoinRequest denied({int id = 1, int chatId = 1}) {
    return model(
      id: id,
      chatId: chatId,
      status: JoinRequestStatus.denied,
    );
  }

  static JoinRequest cancelled({int id = 1, int chatId = 1}) {
    return model(
      id: id,
      chatId: chatId,
      status: JoinRequestStatus.cancelled,
    );
  }
}
