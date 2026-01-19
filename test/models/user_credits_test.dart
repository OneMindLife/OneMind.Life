import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/user_credits.dart';

void main() {
  group('UserCredits', () {
    group('fromJson', () {
      test('parses all fields correctly', () {
        final json = {
          'id': 1,
          'user_id': 'user-123',
          'credit_balance': 500,
          'free_tier_used': 100,
          'free_tier_reset_at': '2025-02-01T00:00:00Z',
          'created_at': '2025-01-01T00:00:00Z',
          'updated_at': '2025-01-15T00:00:00Z',
          'stripe_customer_id': 'cus_test123',
          'stripe_payment_method_id': 'pm_test456',
          'auto_refill_enabled': true,
          'auto_refill_threshold': 50,
          'auto_refill_amount': 500,
          'auto_refill_last_triggered_at': '2025-01-10T00:00:00Z',
          'auto_refill_last_error': null,
        };

        final credits = UserCredits.fromJson(json);

        expect(credits.id, 1);
        expect(credits.userId, 'user-123');
        expect(credits.creditBalance, 500);
        expect(credits.freeTierUsed, 100);
        expect(credits.stripeCustomerId, 'cus_test123');
        expect(credits.stripePaymentMethodId, 'pm_test456');
        expect(credits.autoRefillEnabled, true);
        expect(credits.autoRefillThreshold, 50);
        expect(credits.autoRefillAmount, 500);
        expect(credits.autoRefillLastTriggeredAt, isNotNull);
        expect(credits.autoRefillLastError, isNull);
      });

      test('handles null optional fields', () {
        final json = {
          'id': 1,
          'user_id': 'user-123',
          'credit_balance': 0,
          'free_tier_used': 0,
          'free_tier_reset_at': '2025-02-01T00:00:00Z',
          'created_at': '2025-01-01T00:00:00Z',
          'updated_at': '2025-01-15T00:00:00Z',
        };

        final credits = UserCredits.fromJson(json);

        expect(credits.stripeCustomerId, isNull);
        expect(credits.stripePaymentMethodId, isNull);
        expect(credits.autoRefillEnabled, false);
        expect(credits.autoRefillThreshold, 50);
        expect(credits.autoRefillAmount, 500);
        expect(credits.autoRefillLastTriggeredAt, isNull);
        expect(credits.autoRefillLastError, isNull);
      });

      test('handles null credit_balance and free_tier_used', () {
        final json = {
          'id': 1,
          'user_id': 'user-123',
          'credit_balance': null,
          'free_tier_used': null,
          'free_tier_reset_at': '2025-02-01T00:00:00Z',
          'created_at': '2025-01-01T00:00:00Z',
          'updated_at': '2025-01-15T00:00:00Z',
        };

        final credits = UserCredits.fromJson(json);

        expect(credits.creditBalance, 0);
        expect(credits.freeTierUsed, 0);
      });
    });

    group('toJson', () {
      test('serializes all fields correctly', () {
        final credits = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 500,
          freeTierUsed: 100,
          freeTierResetAt: DateTime.parse('2025-02-01T00:00:00Z'),
          createdAt: DateTime.parse('2025-01-01T00:00:00Z'),
          updatedAt: DateTime.parse('2025-01-15T00:00:00Z'),
          stripeCustomerId: 'cus_test',
          stripePaymentMethodId: 'pm_test',
          autoRefillEnabled: true,
          autoRefillThreshold: 100,
          autoRefillAmount: 1000,
        );

        final json = credits.toJson();

        expect(json['id'], 1);
        expect(json['user_id'], 'user-123');
        expect(json['credit_balance'], 500);
        expect(json['free_tier_used'], 100);
        expect(json['stripe_customer_id'], 'cus_test');
        expect(json['stripe_payment_method_id'], 'pm_test');
        expect(json['auto_refill_enabled'], true);
        expect(json['auto_refill_threshold'], 100);
        expect(json['auto_refill_amount'], 1000);
      });
    });

    group('computed properties', () {
      test('freeTierRemaining calculates correctly', () {
        final credits = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 300,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(credits.freeTierRemaining, 200);
      });

      test('freeTierRemaining clamps to 0 when exceeded', () {
        final credits = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 600, // Over the limit
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(credits.freeTierRemaining, 0);
      });

      test('totalAvailable combines free tier and paid credits', () {
        final credits = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 1000,
          freeTierUsed: 200,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(credits.freeTierRemaining, 300);
        expect(credits.totalAvailable, 1300); // 300 free + 1000 paid
      });

      test('hasCredits returns true when totalAvailable > 0', () {
        final creditsWithBalance = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 100,
          freeTierUsed: 500,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(creditsWithBalance.hasCredits, true);

        final creditsWithFreeTier = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(creditsWithFreeTier.hasCredits, true);
      });

      test('hasCredits returns false when no credits available', () {
        final credits = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 500, // All free tier used
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(credits.hasCredits, false);
      });

      test('canAfford checks total available', () {
        final credits = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 100,
          freeTierUsed: 400,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(credits.totalAvailable, 200); // 100 free + 100 paid
        expect(credits.canAfford(200), true);
        expect(credits.canAfford(201), false);
      });

      test('hasPaymentMethod checks stripe_payment_method_id', () {
        final withPayment = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          stripePaymentMethodId: 'pm_test',
        );

        final withoutPayment = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(withPayment.hasPaymentMethod, true);
        expect(withoutPayment.hasPaymentMethod, false);
      });

      test('isAutoRefillActive requires enabled and payment method', () {
        final activeAutoRefill = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          stripePaymentMethodId: 'pm_test',
          autoRefillEnabled: true,
        );

        final enabledNoPayment = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          autoRefillEnabled: true,
        );

        final disabledWithPayment = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 0,
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          stripePaymentMethodId: 'pm_test',
          autoRefillEnabled: false,
        );

        expect(activeAutoRefill.isAutoRefillActive, true);
        expect(enabledNoPayment.isAutoRefillActive, false);
        expect(disabledWithPayment.isAutoRefillActive, false);
      });
    });

    group('constants', () {
      test('freeTierMonthlyLimit is 500', () {
        expect(UserCredits.freeTierMonthlyLimit, 500);
      });

      test('creditPriceCents is 1', () {
        expect(UserCredits.creditPriceCents, 1);
      });
    });

    group('equatable', () {
      test('equality based on all fields', () {
        final fixedDate = DateTime.utc(2024, 1, 1);
        final credits1 = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 100,
          freeTierUsed: 0,
          freeTierResetAt: fixedDate,
          createdAt: fixedDate,
          updatedAt: fixedDate,
        );

        final credits2 = UserCredits(
          id: 1,
          userId: 'user-123',
          creditBalance: 100,
          freeTierUsed: 0,
          freeTierResetAt: fixedDate,
          createdAt: fixedDate,
          updatedAt: fixedDate,
        );

        expect(credits1, equals(credits2));
      });
    });
  });

  group('PaymentMethod', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'pm_test123',
        'last4': '4242',
        'brand': 'visa',
        'expMonth': 12,
        'expYear': 2025,
      };

      final pm = PaymentMethod.fromJson(json);

      expect(pm.id, 'pm_test123');
      expect(pm.last4, '4242');
      expect(pm.brand, 'visa');
      expect(pm.expMonth, 12);
      expect(pm.expYear, 2025);
    });

    test('displayName formats correctly', () {
      final pm = PaymentMethod(
        id: 'pm_test',
        last4: '4242',
        brand: 'visa',
      );

      expect(pm.displayName, 'VISA •••• 4242');
    });

    test('displayName handles null brand', () {
      final pm = PaymentMethod(
        id: 'pm_test',
        last4: '1234',
      );

      expect(pm.displayName, 'Card •••• 1234');
    });

    test('expiry formats correctly', () {
      final pm = PaymentMethod(
        id: 'pm_test',
        expMonth: 3,
        expYear: 2026,
      );

      expect(pm.expiry, '03/26');
    });

    test('expiry handles null values', () {
      final pm = PaymentMethod(id: 'pm_test');

      expect(pm.expiry, '');
    });
  });

  group('TransactionType', () {
    test('fromString parses all types', () {
      expect(TransactionType.fromString('purchase'), TransactionType.purchase);
      expect(TransactionType.fromString('usage'), TransactionType.usage);
      expect(TransactionType.fromString('refund'), TransactionType.refund);
      expect(TransactionType.fromString('adjustment'), TransactionType.adjustment);
      expect(TransactionType.fromString('auto_refill'), TransactionType.autoRefill);
    });

    test('fromString defaults to adjustment for unknown', () {
      expect(TransactionType.fromString('unknown'), TransactionType.adjustment);
    });
  });

  group('CreditTransaction', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'user_id': 'user-123',
        'transaction_type': 'purchase',
        'amount': 500,
        'balance_after': 500,
        'description': 'Purchased 500 credits',
        'stripe_checkout_session_id': 'cs_test123',
        'created_at': '2025-01-15T00:00:00Z',
      };

      final tx = CreditTransaction.fromJson(json);

      expect(tx.id, 1);
      expect(tx.userId, 'user-123');
      expect(tx.transactionType, TransactionType.purchase);
      expect(tx.amount, 500);
      expect(tx.balanceAfter, 500);
      expect(tx.description, 'Purchased 500 credits');
      expect(tx.stripeCheckoutSessionId, 'cs_test123');
    });

    test('isCredit returns true for positive amount', () {
      final tx = CreditTransaction(
        id: 1,
        userId: 'user-123',
        transactionType: TransactionType.purchase,
        amount: 100,
        balanceAfter: 100,
        createdAt: DateTime.now(),
      );

      expect(tx.isCredit, true);
    });

    test('isCredit returns false for negative amount', () {
      final tx = CreditTransaction(
        id: 1,
        userId: 'user-123',
        transactionType: TransactionType.usage,
        amount: -50,
        balanceAfter: 50,
        createdAt: DateTime.now(),
      );

      expect(tx.isCredit, false);
    });
  });

  group('MonthlyUsage', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'user_id': 'user-123',
        'month_start': '2025-01-01',
        'total_user_rounds': 100,
        'free_tier_user_rounds': 80,
        'paid_user_rounds': 20,
        'total_chats': 5,
        'total_rounds': 10,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-15T00:00:00Z',
      };

      final usage = MonthlyUsage.fromJson(json);

      expect(usage.id, 1);
      expect(usage.userId, 'user-123');
      expect(usage.totalUserRounds, 100);
      expect(usage.freeTierUserRounds, 80);
      expect(usage.paidUserRounds, 20);
      expect(usage.totalChats, 5);
      expect(usage.totalRounds, 10);
    });

    test('fromJson handles null values with defaults', () {
      final json = {
        'id': 1,
        'user_id': 'user-123',
        'month_start': '2025-01-01',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-15T00:00:00Z',
      };

      final usage = MonthlyUsage.fromJson(json);

      expect(usage.totalUserRounds, 0);
      expect(usage.freeTierUserRounds, 0);
      expect(usage.paidUserRounds, 0);
      expect(usage.totalChats, 0);
      expect(usage.totalRounds, 0);
    });
  });
}
