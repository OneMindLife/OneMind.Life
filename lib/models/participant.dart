import 'package:equatable/equatable.dart';
import '../core/errors/app_exception.dart';

enum ParticipantStatus { pending, active, kicked, left }

class Participant extends Equatable {
  final int id;
  final int chatId;
  final String? userId;
  final String? sessionToken;
  final String displayName;
  final bool isHost;
  final bool isAuthenticated;
  final ParticipantStatus status;
  final DateTime createdAt;

  const Participant({
    required this.id,
    required this.chatId,
    this.userId,
    this.sessionToken,
    required this.displayName,
    required this.isHost,
    required this.isAuthenticated,
    required this.status,
    required this.createdAt,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as int,
      chatId: json['chat_id'] as int,
      userId: json['user_id'] as String?,
      sessionToken: json['session_token'] as String?,
      displayName: json['display_name'] as String,
      isHost: json['is_host'] as bool? ?? false,
      isAuthenticated: json['is_authenticated'] as bool? ?? false,
      status: _parseStatus(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static ParticipantStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return ParticipantStatus.pending;
      case 'kicked':
        return ParticipantStatus.kicked;
      case 'left':
        return ParticipantStatus.left;
      case 'active':
      case null:
        return ParticipantStatus.active; // Default for null or explicit active
      default:
        throw AppException.validation(
          message: 'Unknown participant status: $status',
          field: 'status',
        );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'chat_id': chatId,
      'user_id': userId,
      'session_token': sessionToken,
      'display_name': displayName,
      'is_host': isHost,
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
        isHost,
        isAuthenticated,
        status,
        createdAt,
      ];
}
