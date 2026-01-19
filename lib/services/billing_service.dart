import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/app_exception.dart';
import '../models/user_credits.dart';

/// Service for billing and credits operations
class BillingService {
  final SupabaseClient _client;

  BillingService(this._client);

  /// Get the current user's credit balance and free tier usage
  Future<UserCredits?> getMyCredits() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    // Use the database function which handles creation and free tier reset
    final response = await _client.rpc(
      'get_or_create_user_credits',
      params: {'p_user_id': userId},
    );

    if (response == null) return null;
    return UserCredits.fromJson(response);
  }

  /// Check if the current user can afford a given number of user-rounds
  Future<bool> canAfford(int userRounds) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await _client.rpc(
      'can_afford_user_rounds',
      params: {
        'p_user_id': userId,
        'p_user_round_count': userRounds,
      },
    );

    return response == true;
  }

  /// Get credit transaction history for the current user
  Future<List<CreditTransaction>> getTransactionHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('credit_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((json) => CreditTransaction.fromJson(json))
        .toList();
  }

  /// Get monthly usage statistics for the current user
  Future<List<MonthlyUsage>> getMonthlyUsage({int months = 6}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('monthly_usage')
        .select()
        .eq('user_id', userId)
        .order('month_start', ascending: false)
        .limit(months);

    return (response as List)
        .map((json) => MonthlyUsage.fromJson(json))
        .toList();
  }

  /// Create a Stripe checkout session for purchasing credits
  /// Returns the checkout URL to redirect the user to
  Future<String?> createCheckoutSession(int credits) async {
    if (credits < 1 || credits > 100000) {
      throw AppException.invalidCreditAmount(
        min: 1,
        max: 100000,
        actual: credits,
      );
    }

    final response = await _client.functions.invoke(
      'create-checkout-session',
      body: {'credits': credits},
    );

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Unknown error';
      throw AppException.billingError(
        message: 'Failed to create checkout session: $error',
      );
    }

    return response.data?['url'] as String?;
  }

  /// Calculate the cost in cents for a given number of credits
  static int calculateCostCents(int credits) {
    return credits * UserCredits.creditPriceCents;
  }

  /// Calculate the cost in dollars for a given number of credits
  static double calculateCostDollars(int credits) {
    return calculateCostCents(credits) / 100.0;
  }

  /// Format a dollar amount for display
  static String formatDollars(double amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }

  /// Format credits for display with cost
  static String formatCreditsWithCost(int credits) {
    return '$credits credits (${formatDollars(calculateCostDollars(credits))})';
  }

  // ============================================================================
  // Auto-refill methods
  // ============================================================================

  /// Create a SetupIntent to save a payment method for auto-refill
  /// Returns the client secret to use with Stripe.js
  Future<Map<String, String>> setupPaymentMethod() async {
    final response = await _client.functions.invoke(
      'setup-payment-method',
      body: {},
    );

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Unknown error';
      throw AppException.billingError(
        message: 'Failed to setup payment method: $error',
      );
    }

    return {
      'clientSecret': response.data?['clientSecret'] as String,
      'customerId': response.data?['customerId'] as String,
    };
  }

  /// Confirm a payment method after SetupIntent completion
  /// Returns the saved payment method details
  Future<PaymentMethod> confirmPaymentMethod(String setupIntentId) async {
    final response = await _client.functions.invoke(
      'confirm-payment-method',
      body: {'setupIntentId': setupIntentId},
    );

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Unknown error';
      throw AppException.billingError(
        message: 'Failed to confirm payment method: $error',
      );
    }

    return PaymentMethod.fromJson(response.data?['paymentMethod']);
  }

  /// Update auto-refill settings
  Future<UserCredits?> updateAutoRefillSettings({
    required bool enabled,
    int? threshold,
    int? amount,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _client.rpc(
      'update_auto_refill_settings',
      params: {
        'p_user_id': userId,
        'p_enabled': enabled,
        'p_threshold': threshold,
        'p_amount': amount,
      },
    );

    if (response == null) return null;
    return UserCredits.fromJson(response);
  }

  /// Remove saved payment method (disables auto-refill)
  Future<void> removePaymentMethod() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('user_credits').update({
      'stripe_payment_method_id': null,
      'auto_refill_enabled': false,
    }).eq('user_id', userId);
  }
}
