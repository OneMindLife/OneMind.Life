import 'package:equatable/equatable.dart';

/// User credits balance and free tier tracking
class UserCredits extends Equatable {
  final int id;
  final String userId;
  final int creditBalance;
  final int freeTierUsed;
  final DateTime freeTierResetAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Stripe info
  final String? stripeCustomerId;
  final String? stripePaymentMethodId;

  // Auto-refill settings
  final bool autoRefillEnabled;
  final int autoRefillThreshold;
  final int autoRefillAmount;
  final DateTime? autoRefillLastTriggeredAt;
  final String? autoRefillLastError;

  const UserCredits({
    required this.id,
    required this.userId,
    required this.creditBalance,
    required this.freeTierUsed,
    required this.freeTierResetAt,
    required this.createdAt,
    required this.updatedAt,
    this.stripeCustomerId,
    this.stripePaymentMethodId,
    this.autoRefillEnabled = false,
    this.autoRefillThreshold = 50,
    this.autoRefillAmount = 500,
    this.autoRefillLastTriggeredAt,
    this.autoRefillLastError,
  });

  /// Free tier monthly limit (500 user-rounds)
  static const int freeTierMonthlyLimit = 500;

  /// Credit price in cents (1 credit = 1 cent = $0.01)
  static const int creditPriceCents = 1;

  /// Remaining free tier user-rounds this month
  int get freeTierRemaining => (freeTierMonthlyLimit - freeTierUsed).clamp(0, freeTierMonthlyLimit);

  /// Total available user-rounds (free tier + paid credits)
  int get totalAvailable => freeTierRemaining + creditBalance;

  /// Whether user has any available credits (free or paid)
  bool get hasCredits => totalAvailable > 0;

  /// Check if user can afford a given number of user-rounds
  bool canAfford(int userRounds) => totalAvailable >= userRounds;

  /// Whether a payment method is saved
  bool get hasPaymentMethod => stripePaymentMethodId != null;

  /// Whether auto-refill is fully configured and active
  bool get isAutoRefillActive => autoRefillEnabled && hasPaymentMethod;

  factory UserCredits.fromJson(Map<String, dynamic> json) {
    return UserCredits(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      creditBalance: json['credit_balance'] as int? ?? 0,
      freeTierUsed: json['free_tier_used'] as int? ?? 0,
      freeTierResetAt: DateTime.parse(json['free_tier_reset_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      stripeCustomerId: json['stripe_customer_id'] as String?,
      stripePaymentMethodId: json['stripe_payment_method_id'] as String?,
      autoRefillEnabled: json['auto_refill_enabled'] as bool? ?? false,
      autoRefillThreshold: json['auto_refill_threshold'] as int? ?? 50,
      autoRefillAmount: json['auto_refill_amount'] as int? ?? 500,
      autoRefillLastTriggeredAt: json['auto_refill_last_triggered_at'] != null
          ? DateTime.parse(json['auto_refill_last_triggered_at'] as String)
          : null,
      autoRefillLastError: json['auto_refill_last_error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'credit_balance': creditBalance,
      'free_tier_used': freeTierUsed,
      'free_tier_reset_at': freeTierResetAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'stripe_customer_id': stripeCustomerId,
      'stripe_payment_method_id': stripePaymentMethodId,
      'auto_refill_enabled': autoRefillEnabled,
      'auto_refill_threshold': autoRefillThreshold,
      'auto_refill_amount': autoRefillAmount,
      'auto_refill_last_triggered_at': autoRefillLastTriggeredAt?.toIso8601String(),
      'auto_refill_last_error': autoRefillLastError,
    };
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        creditBalance,
        freeTierUsed,
        freeTierResetAt,
        createdAt,
        updatedAt,
        stripeCustomerId,
        stripePaymentMethodId,
        autoRefillEnabled,
        autoRefillThreshold,
        autoRefillAmount,
        autoRefillLastTriggeredAt,
        autoRefillLastError,
      ];
}

/// Saved payment method info
class PaymentMethod {
  final String id;
  final String? last4;
  final String? brand;
  final int? expMonth;
  final int? expYear;

  const PaymentMethod({
    required this.id,
    this.last4,
    this.brand,
    this.expMonth,
    this.expYear,
  });

  String get displayName {
    final brandName = brand?.toUpperCase() ?? 'Card';
    return '$brandName •••• ${last4 ?? '****'}';
  }

  String get expiry {
    if (expMonth == null || expYear == null) return '';
    return '${expMonth.toString().padLeft(2, '0')}/${expYear.toString().substring(2)}';
  }

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as String,
      last4: json['last4'] as String?,
      brand: json['brand'] as String?,
      expMonth: json['expMonth'] as int?,
      expYear: json['expYear'] as int?,
    );
  }
}

/// Types of credit transactions
enum TransactionType {
  purchase,
  usage,
  refund,
  adjustment,
  autoRefill;

  static TransactionType fromString(String value) {
    switch (value) {
      case 'purchase':
        return TransactionType.purchase;
      case 'usage':
        return TransactionType.usage;
      case 'refund':
        return TransactionType.refund;
      case 'adjustment':
        return TransactionType.adjustment;
      case 'auto_refill':
        return TransactionType.autoRefill;
      default:
        return TransactionType.adjustment;
    }
  }
}

/// Credit transaction history entry
class CreditTransaction extends Equatable {
  final int id;
  final String userId;
  final TransactionType transactionType;
  final int amount;
  final int balanceAfter;
  final String? description;
  final String? stripePaymentIntentId;
  final String? stripeCheckoutSessionId;
  final int? chatId;
  final int? roundId;
  final int? userRoundCount;
  final DateTime createdAt;

  const CreditTransaction({
    required this.id,
    required this.userId,
    required this.transactionType,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.stripePaymentIntentId,
    this.stripeCheckoutSessionId,
    this.chatId,
    this.roundId,
    this.userRoundCount,
    required this.createdAt,
  });

  /// Whether this is a credit (positive) or debit (negative) transaction
  bool get isCredit => amount > 0;

  factory CreditTransaction.fromJson(Map<String, dynamic> json) {
    return CreditTransaction(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      transactionType: TransactionType.fromString(json['transaction_type'] as String),
      amount: json['amount'] as int,
      balanceAfter: json['balance_after'] as int,
      description: json['description'] as String?,
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      stripeCheckoutSessionId: json['stripe_checkout_session_id'] as String?,
      chatId: json['chat_id'] as int?,
      roundId: json['round_id'] as int?,
      userRoundCount: json['user_round_count'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        transactionType,
        amount,
        balanceAfter,
        description,
        stripePaymentIntentId,
        stripeCheckoutSessionId,
        chatId,
        roundId,
        userRoundCount,
        createdAt,
      ];
}

/// Monthly usage statistics
class MonthlyUsage extends Equatable {
  final int id;
  final String userId;
  final DateTime monthStart;
  final int totalUserRounds;
  final int freeTierUserRounds;
  final int paidUserRounds;
  final int totalChats;
  final int totalRounds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MonthlyUsage({
    required this.id,
    required this.userId,
    required this.monthStart,
    required this.totalUserRounds,
    required this.freeTierUserRounds,
    required this.paidUserRounds,
    required this.totalChats,
    required this.totalRounds,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MonthlyUsage.fromJson(Map<String, dynamic> json) {
    return MonthlyUsage(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      monthStart: DateTime.parse(json['month_start'] as String),
      totalUserRounds: json['total_user_rounds'] as int? ?? 0,
      freeTierUserRounds: json['free_tier_user_rounds'] as int? ?? 0,
      paidUserRounds: json['paid_user_rounds'] as int? ?? 0,
      totalChats: json['total_chats'] as int? ?? 0,
      totalRounds: json['total_rounds'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        monthStart,
        totalUserRounds,
        freeTierUserRounds,
        paidUserRounds,
        totalChats,
        totalRounds,
        createdAt,
        updatedAt,
      ];
}
