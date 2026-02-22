import 'package:equatable/equatable.dart';

class ChatCredits extends Equatable {
  final int id;
  final int chatId;
  final int creditBalance;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatCredits({
    required this.id,
    required this.chatId,
    required this.creditBalance,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Cost per credit in cents.
  static const int creditPriceCents = 1;

  /// Free credits granted on chat creation.
  static const int initialFreeCredits = 50;

  bool get hasCredits => creditBalance > 0;

  bool canAfford(int participantCount) => creditBalance >= participantCount;

  static double calculateCostDollars(int credits) =>
      credits * creditPriceCents / 100.0;

  static String formatDollars(int credits) {
    final dollars = calculateCostDollars(credits);
    return '\$${dollars.toStringAsFixed(2)}';
  }

  factory ChatCredits.fromJson(Map<String, dynamic> json) {
    return ChatCredits(
      id: json['id'] as int,
      chatId: json['chat_id'] as int,
      creditBalance: json['credit_balance'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, chatId, creditBalance, createdAt, updatedAt];
}
