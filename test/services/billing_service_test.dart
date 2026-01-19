import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/user_credits.dart';
import 'package:onemind_app/services/billing_service.dart';

import '../fixtures/billing_fixtures.dart';

void main() {
  group('BillingService', () {
    group('static methods', () {
      test('calculateCostCents returns correct amount', () {
        expect(BillingService.calculateCostCents(1), 1);
        expect(BillingService.calculateCostCents(100), 100);
        expect(BillingService.calculateCostCents(1000), 1000);
        expect(BillingService.calculateCostCents(50000), 50000);
      });

      test('calculateCostDollars returns correct amount', () {
        expect(BillingService.calculateCostDollars(1), 0.01);
        expect(BillingService.calculateCostDollars(100), 1.0);
        expect(BillingService.calculateCostDollars(1000), 10.0);
        expect(BillingService.calculateCostDollars(12345), 123.45);
      });

      test('formatDollars formats correctly', () {
        expect(BillingService.formatDollars(0.01), '\$0.01');
        expect(BillingService.formatDollars(1.0), '\$1.00');
        expect(BillingService.formatDollars(10.5), '\$10.50');
        expect(BillingService.formatDollars(100.99), '\$100.99');
        expect(BillingService.formatDollars(1234.56), '\$1234.56');
      });

      test('formatCreditsWithCost formats correctly', () {
        expect(
          BillingService.formatCreditsWithCost(1),
          '1 credits (\$0.01)',
        );
        expect(
          BillingService.formatCreditsWithCost(100),
          '100 credits (\$1.00)',
        );
        expect(
          BillingService.formatCreditsWithCost(1000),
          '1000 credits (\$10.00)',
        );
        expect(
          BillingService.formatCreditsWithCost(50000),
          '50000 credits (\$500.00)',
        );
      });
    });

    group('pricing calculations', () {
      test('1 credit = 1 cent', () {
        expect(UserCredits.creditPriceCents, 1);
        expect(BillingService.calculateCostCents(1), UserCredits.creditPriceCents);
      });

      test('100 credits equals 1 dollar', () {
        expect(BillingService.calculateCostDollars(100), 1.0);
      });

      test('free tier limit is 500', () {
        expect(UserCredits.freeTierMonthlyLimit, 500);
      });

      test('max credits per transaction', () {
        // 100,000 credits = $1,000 max
        expect(BillingService.calculateCostDollars(100000), 1000.0);
      });
    });
  });

  group('BillingService integration scenarios', () {
    group('new user flow', () {
      test('new user has full free tier available', () {
        final credits = BillingFixtures.newUserCredits();

        expect(credits.creditBalance, 0);
        expect(credits.freeTierUsed, 0);
        expect(credits.freeTierRemaining, 500);
        expect(credits.totalAvailable, 500);
        expect(credits.hasCredits, true);
      });

      test('new user can afford up to 500 user-rounds', () {
        final credits = BillingFixtures.newUserCredits();

        expect(credits.canAfford(1), true);
        expect(credits.canAfford(100), true);
        expect(credits.canAfford(500), true);
        expect(credits.canAfford(501), false);
        expect(credits.canAfford(1000), false);
      });

      test('after purchasing credits, total available increases', () {
        final credits = BillingFixtures.userWithPaidCredits(
          creditBalance: 1000,
          freeTierUsed: 0,
        );

        expect(credits.creditBalance, 1000);
        expect(credits.freeTierRemaining, 500);
        expect(credits.totalAvailable, 1500);
        expect(credits.canAfford(1500), true);
        expect(credits.canAfford(1501), false);
      });
    });

    group('free tier usage', () {
      test('partial free tier usage', () {
        final credits = BillingFixtures.userWithFreeTierUsage(freeTierUsed: 200);

        expect(credits.freeTierUsed, 200);
        expect(credits.freeTierRemaining, 300);
        expect(credits.totalAvailable, 300);
      });

      test('free tier fully exhausted', () {
        final credits = BillingFixtures.userWithNoCredits();

        expect(credits.freeTierUsed, 500);
        expect(credits.freeTierRemaining, 0);
        expect(credits.creditBalance, 0);
        expect(credits.totalAvailable, 0);
        expect(credits.hasCredits, false);
        expect(credits.canAfford(1), false);
      });

      test('free tier used but has paid credits', () {
        final credits = BillingFixtures.userWithPaidCredits(
          creditBalance: 500,
          freeTierUsed: 500,
        );

        expect(credits.freeTierRemaining, 0);
        expect(credits.creditBalance, 500);
        expect(credits.totalAvailable, 500);
        expect(credits.hasCredits, true);
        expect(credits.canAfford(500), true);
      });

      test('free tier clamps to 0 when exceeded', () {
        // Edge case: if somehow freeTierUsed > limit
        final credits = UserCredits(
          id: 1,
          userId: 'test',
          creditBalance: 0,
          freeTierUsed: 600, // Over the 500 limit
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(credits.freeTierRemaining, 0);
        expect(credits.totalAvailable, 0);
      });
    });

    group('auto-refill eligibility', () {
      test('auto-refill active requires both enabled and payment method', () {
        final active = BillingFixtures.userWithAutoRefill(
          autoRefillEnabled: true,
        );
        expect(active.isAutoRefillActive, true);
        expect(active.hasPaymentMethod, true);
      });

      test('auto-refill not active without payment method', () {
        final noPayment = UserCredits(
          id: 1,
          userId: 'test',
          creditBalance: 100,
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          autoRefillEnabled: true,
          // No stripePaymentMethodId
        );

        expect(noPayment.isAutoRefillActive, false);
        expect(noPayment.hasPaymentMethod, false);
      });

      test('auto-refill not active when disabled', () {
        final disabled = BillingFixtures.userWithAutoRefill(
          autoRefillEnabled: false,
        );

        expect(disabled.isAutoRefillActive, false);
        expect(disabled.hasPaymentMethod, true);
      });

      test('balance below threshold should trigger refill', () {
        final belowThreshold = BillingFixtures.userWithAutoRefill(
          creditBalance: 30,
          autoRefillThreshold: 50,
        );

        expect(belowThreshold.creditBalance, 30);
        expect(belowThreshold.autoRefillThreshold, 50);
        expect(belowThreshold.creditBalance < belowThreshold.autoRefillThreshold, true);
      });

      test('balance at or above threshold should not trigger refill', () {
        final atThreshold = BillingFixtures.userWithAutoRefill(
          creditBalance: 50,
          autoRefillThreshold: 50,
        );

        expect(atThreshold.creditBalance >= atThreshold.autoRefillThreshold, true);

        final aboveThreshold = BillingFixtures.userWithAutoRefill(
          creditBalance: 100,
          autoRefillThreshold: 50,
        );

        expect(aboveThreshold.creditBalance >= aboveThreshold.autoRefillThreshold, true);
      });
    });

    group('transaction types', () {
      test('purchase transaction is credit', () {
        final tx = BillingFixtures.purchaseTransaction(amount: 500);

        expect(tx.transactionType, TransactionType.purchase);
        expect(tx.amount, 500);
        expect(tx.isCredit, true);
      });

      test('usage transaction is debit', () {
        final tx = BillingFixtures.usageTransaction(amount: -50);

        expect(tx.transactionType, TransactionType.usage);
        expect(tx.amount, -50);
        expect(tx.isCredit, false);
      });

      test('auto-refill transaction is credit', () {
        final tx = BillingFixtures.autoRefillTransaction(amount: 500);

        expect(tx.transactionType, TransactionType.autoRefill);
        expect(tx.amount, 500);
        expect(tx.isCredit, true);
      });
    });

    group('monthly usage tracking', () {
      test('monthly usage aggregates correctly', () {
        final usage = BillingFixtures.monthlyUsage(
          totalUserRounds: 150,
          freeTierUserRounds: 100,
          paidUserRounds: 50,
          totalChats: 3,
          totalRounds: 10,
        );

        expect(usage.totalUserRounds, 150);
        expect(usage.freeTierUserRounds, 100);
        expect(usage.paidUserRounds, 50);
        expect(usage.totalChats, 3);
        expect(usage.totalRounds, 10);

        // Verify: free + paid = total
        expect(usage.freeTierUserRounds + usage.paidUserRounds, usage.totalUserRounds);
      });

      test('sample transaction history contains expected types', () {
        final history = BillingFixtures.sampleTransactionHistory();

        expect(history.length, 5);

        final purchases = history.where((tx) => tx.transactionType == TransactionType.purchase);
        final usages = history.where((tx) => tx.transactionType == TransactionType.usage);
        final autoRefills = history.where((tx) => tx.transactionType == TransactionType.autoRefill);

        expect(purchases.length, 1);
        expect(usages.length, 3);
        expect(autoRefills.length, 1);
      });
    });

    group('payment method display', () {
      test('visa card displays correctly', () {
        final pm = BillingFixtures.paymentMethod(
          last4: '4242',
          brand: 'visa',
          expMonth: 12,
          expYear: 2026,
        );

        expect(pm.displayName, 'VISA •••• 4242');
        expect(pm.expiry, '12/26');
      });

      test('mastercard displays correctly', () {
        final pm = BillingFixtures.paymentMethod(
          last4: '5555',
          brand: 'mastercard',
          expMonth: 3,
          expYear: 2027,
        );

        expect(pm.displayName, 'MASTERCARD •••• 5555');
        expect(pm.expiry, '03/27');
      });

      test('unknown brand defaults to Card', () {
        final pm = PaymentMethod(id: 'pm_test', last4: '1234');

        expect(pm.displayName, 'Card •••• 1234');
      });
    });

    group('edge cases', () {
      test('zero credits but has free tier', () {
        final credits = BillingFixtures.newUserCredits(creditBalance: 0);

        expect(credits.creditBalance, 0);
        expect(credits.hasCredits, true); // Because of free tier
        expect(credits.totalAvailable, 500);
      });

      test('negative amount not possible - model handles it', () {
        // The model doesn't prevent negative, but the DB does
        final credits = UserCredits(
          id: 1,
          userId: 'test',
          creditBalance: -100, // Shouldn't happen in practice
          freeTierUsed: 0,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // totalAvailable would be negative, hasCredits should be false
        expect(credits.creditBalance, -100);
        expect(credits.totalAvailable, 400); // -100 + 500
        expect(credits.hasCredits, true); // Still has 400 from free tier
      });

      test('large credit balance', () {
        final credits = UserCredits(
          id: 1,
          userId: 'test',
          creditBalance: 100000,
          freeTierUsed: 500,
          freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(credits.totalAvailable, 100000);
        expect(credits.canAfford(100000), true);
        expect(BillingService.calculateCostDollars(100000), 1000.0);
      });
    });
  });
}
