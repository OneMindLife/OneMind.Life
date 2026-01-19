import 'package:onemind_app/models/user_credits.dart';

/// Test fixtures for billing models
class BillingFixtures {
  /// User credits with no usage
  static UserCredits newUserCredits({
    int id = 1,
    String userId = 'test-user-id',
    int creditBalance = 0,
    int freeTierUsed = 0,
  }) {
    return UserCredits(
      id: id,
      userId: userId,
      creditBalance: creditBalance,
      freeTierUsed: freeTierUsed,
      freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// User credits with some free tier used
  static UserCredits userWithFreeTierUsage({
    int id = 1,
    String userId = 'test-user-id',
    int creditBalance = 0,
    int freeTierUsed = 200,
  }) {
    return UserCredits(
      id: id,
      userId: userId,
      creditBalance: creditBalance,
      freeTierUsed: freeTierUsed,
      freeTierResetAt: DateTime.now().add(const Duration(days: 15)),
      createdAt: DateTime.now().subtract(const Duration(days: 15)),
      updatedAt: DateTime.now(),
    );
  }

  /// User credits with paid credits
  static UserCredits userWithPaidCredits({
    int id = 1,
    String userId = 'test-user-id',
    int creditBalance = 1000,
    int freeTierUsed = 500,
  }) {
    return UserCredits(
      id: id,
      userId: userId,
      creditBalance: creditBalance,
      freeTierUsed: freeTierUsed,
      freeTierResetAt: DateTime.now().add(const Duration(days: 10)),
      createdAt: DateTime.now().subtract(const Duration(days: 20)),
      updatedAt: DateTime.now(),
    );
  }

  /// User credits with auto-refill configured
  static UserCredits userWithAutoRefill({
    int id = 1,
    String userId = 'test-user-id',
    int creditBalance = 100,
    bool autoRefillEnabled = true,
    int autoRefillThreshold = 50,
    int autoRefillAmount = 500,
  }) {
    return UserCredits(
      id: id,
      userId: userId,
      creditBalance: creditBalance,
      freeTierUsed: 500,
      freeTierResetAt: DateTime.now().add(const Duration(days: 5)),
      createdAt: DateTime.now().subtract(const Duration(days: 25)),
      updatedAt: DateTime.now(),
      stripeCustomerId: 'cus_test123',
      stripePaymentMethodId: 'pm_test456',
      autoRefillEnabled: autoRefillEnabled,
      autoRefillThreshold: autoRefillThreshold,
      autoRefillAmount: autoRefillAmount,
    );
  }

  /// User credits with no remaining credits
  static UserCredits userWithNoCredits({
    int id = 1,
    String userId = 'test-user-id',
  }) {
    return UserCredits(
      id: id,
      userId: userId,
      creditBalance: 0,
      freeTierUsed: 500, // All free tier used
      freeTierResetAt: DateTime.now().add(const Duration(days: 20)),
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      updatedAt: DateTime.now(),
    );
  }

  /// Sample credit transaction - purchase
  static CreditTransaction purchaseTransaction({
    int id = 1,
    String userId = 'test-user-id',
    int amount = 500,
    int balanceAfter = 500,
  }) {
    return CreditTransaction(
      id: id,
      userId: userId,
      transactionType: TransactionType.purchase,
      amount: amount,
      balanceAfter: balanceAfter,
      description: 'Purchased $amount credits',
      stripeCheckoutSessionId: 'cs_test_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );
  }

  /// Sample credit transaction - usage
  static CreditTransaction usageTransaction({
    int id = 2,
    String userId = 'test-user-id',
    int amount = -50,
    int balanceAfter = 450,
    int? chatId,
    int? roundId,
    int userRoundCount = 50,
  }) {
    return CreditTransaction(
      id: id,
      userId: userId,
      transactionType: TransactionType.usage,
      amount: amount,
      balanceAfter: balanceAfter,
      description: 'Used ${amount.abs()} paid credits for $userRoundCount user-rounds',
      chatId: chatId,
      roundId: roundId,
      userRoundCount: userRoundCount,
      createdAt: DateTime.now(),
    );
  }

  /// Sample credit transaction - auto-refill
  static CreditTransaction autoRefillTransaction({
    int id = 3,
    String userId = 'test-user-id',
    int amount = 500,
    int balanceAfter = 530,
  }) {
    return CreditTransaction(
      id: id,
      userId: userId,
      transactionType: TransactionType.autoRefill,
      amount: amount,
      balanceAfter: balanceAfter,
      description: 'Auto-refill: added $amount credits',
      stripePaymentIntentId: 'pi_test_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );
  }

  /// Sample monthly usage
  static MonthlyUsage monthlyUsage({
    int id = 1,
    String userId = 'test-user-id',
    int totalUserRounds = 150,
    int freeTierUserRounds = 100,
    int paidUserRounds = 50,
    int totalChats = 3,
    int totalRounds = 10,
  }) {
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
    return MonthlyUsage(
      id: id,
      userId: userId,
      monthStart: monthStart,
      totalUserRounds: totalUserRounds,
      freeTierUserRounds: freeTierUserRounds,
      paidUserRounds: paidUserRounds,
      totalChats: totalChats,
      totalRounds: totalRounds,
      createdAt: monthStart,
      updatedAt: DateTime.now(),
    );
  }

  /// Sample payment method
  static PaymentMethod paymentMethod({
    String id = 'pm_test123',
    String last4 = '4242',
    String brand = 'visa',
    int expMonth = 12,
    int expYear = 2026,
  }) {
    return PaymentMethod(
      id: id,
      last4: last4,
      brand: brand,
      expMonth: expMonth,
      expYear: expYear,
    );
  }

  /// List of sample transactions
  static List<CreditTransaction> sampleTransactionHistory() {
    return [
      purchaseTransaction(id: 1, amount: 1000, balanceAfter: 1000),
      usageTransaction(id: 2, amount: -100, balanceAfter: 900),
      usageTransaction(id: 3, amount: -50, balanceAfter: 850),
      autoRefillTransaction(id: 4, amount: 500, balanceAfter: 1350),
      usageTransaction(id: 5, amount: -200, balanceAfter: 1150),
    ];
  }

  /// List of sample monthly usage records
  static List<MonthlyUsage> sampleMonthlyUsageHistory() {
    final now = DateTime.now();
    return [
      monthlyUsage(
        id: 1,
        totalUserRounds: 500,
        freeTierUserRounds: 450,
        paidUserRounds: 50,
      ),
      MonthlyUsage(
        id: 2,
        userId: 'test-user-id',
        monthStart: DateTime(now.year, now.month - 1, 1),
        totalUserRounds: 350,
        freeTierUserRounds: 350,
        paidUserRounds: 0,
        totalChats: 5,
        totalRounds: 15,
        createdAt: DateTime(now.year, now.month - 1, 1),
        updatedAt: DateTime(now.year, now.month - 1, 28),
      ),
    ];
  }
}
