import 'package:equatable/equatable.dart';

enum JoinRequestStatus { pending, approved, denied, cancelled }

class JoinRequest extends Equatable {
  final int id;
  final int chatId;
  final String? userId;
  final String? sessionToken;
  final String displayName;
  final bool isAuthenticated;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  // Optional: joined chat data for display in requester's list
  final String? chatName;
  final String? chatInitialMessage;
  final List<String> translationLanguages;

  const JoinRequest({
    required this.id,
    required this.chatId,
    this.userId,
    this.sessionToken,
    required this.displayName,
    required this.isAuthenticated,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.chatName,
    this.chatInitialMessage,
    this.translationLanguages = const ['en'],
  });

  factory JoinRequest.fromJson(Map<String, dynamic> json) {
    // Handle nested chat data if present (from joined query)
    final chatData = json['chats'] as Map<String, dynamic>?;

    return JoinRequest(
      id: json['id'] as int,
      chatId: json['chat_id'] as int,
      userId: json['user_id'] as String?,
      sessionToken: json['session_token'] as String?,
      displayName: json['display_name'] as String,
      isAuthenticated: json['is_authenticated'] as bool? ?? false,
      status: _parseStatus(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      chatName: chatData?['name'] as String?,
      chatInitialMessage: chatData?['initial_message'] as String?,
      translationLanguages:
          (chatData?['translation_languages'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              const ['en'],
    );
  }

  static JoinRequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'approved':
        return JoinRequestStatus.approved;
      case 'denied':
        return JoinRequestStatus.denied;
      case 'cancelled':
        return JoinRequestStatus.cancelled;
      default:
        return JoinRequestStatus.pending;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'chat_id': chatId,
      'user_id': userId,
      'session_token': sessionToken,
      'display_name': displayName,
      'is_authenticated': isAuthenticated,
      'status': status.name,
    };
  }

  @override
  List<Object?> get props => [
        id,
        chatId,
        userId,
        sessionToken,
        displayName,
        isAuthenticated,
        status,
        createdAt,
        resolvedAt,
        chatName,
        chatInitialMessage,
        translationLanguages,
      ];
}
