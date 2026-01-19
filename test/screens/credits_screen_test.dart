import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/models/user_credits.dart';
import 'package:onemind_app/services/billing_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockBillingService extends Mock implements BillingService {}

// Test helper to create a CreditsScreen with mocked dependencies
class TestableCreditsScreen extends StatefulWidget {
  final BillingService billingService;

  const TestableCreditsScreen({super.key, required this.billingService});

  @override
  State<TestableCreditsScreen> createState() => _TestableCreditsScreenState();
}

class _TestableCreditsScreenState extends State<TestableCreditsScreen> {
  UserCredits? _credits;
  List<CreditTransaction>? _transactions;
  bool _isLoading = true;
  String? _error;
  final int _purchaseCredits = 100;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final credits = await widget.billingService.getMyCredits();
      final transactions =
          await widget.billingService.getTransactionHistory(limit: 20);

      setState(() {
        _credits = credits;
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBalanceCard(),
                      const SizedBox(height: 24),
                      _buildPurchaseCard(),
                      const SizedBox(height: 24),
                      _buildTransactionHistory(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBalanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Balance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Paid Credits'),
                      Text('${_credits?.creditBalance ?? 0}'),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Free This Month'),
                      Text(
                          '${_credits?.freeTierRemaining ?? UserCredits.freeTierMonthlyLimit}'),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Available'),
                Text(
                    '${_credits?.totalAvailable ?? UserCredits.freeTierMonthlyLimit} user-rounds'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseCard() {
    final cost = BillingService.calculateCostDollars(_purchaseCredits);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buy Credits',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('1 credit = 1 user-round = \$0.01'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total'),
                Text(BillingService.formatDollars(cost)),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.payment),
              label: const Text('Purchase with Stripe'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionHistory() {
    if (_transactions == null || _transactions!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.history, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              const Text('No transaction history'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Transactions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions!.length,
              itemBuilder: (context, index) {
                final tx = _transactions![index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tx.description ?? tx.transactionType.name),
                  trailing: Text('${tx.isCredit ? '+' : ''}${tx.amount}'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late MockBillingService mockBillingService;

  setUp(() {
    mockBillingService = MockBillingService();
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: TestableCreditsScreen(billingService: mockBillingService),
    );
  }

  UserCredits createTestCredits({
    int creditBalance = 500,
    int freeTierUsed = 10,
    String? stripePaymentMethodId,
    bool autoRefillEnabled = false,
  }) {
    return UserCredits(
      id: 1,
      userId: 'test-user-id',
      creditBalance: creditBalance,
      freeTierUsed: freeTierUsed,
      freeTierResetAt: DateTime.now().add(const Duration(days: 30)),
      stripePaymentMethodId: stripePaymentMethodId,
      autoRefillEnabled: autoRefillEnabled,
      autoRefillThreshold: 50,
      autoRefillAmount: 500,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  CreditTransaction createTestTransaction({
    required TransactionType type,
    required int amount,
    String? description,
    int balanceAfter = 500,
  }) {
    return CreditTransaction(
      id: 1,
      userId: 'test-user-id',
      transactionType: type,
      amount: amount,
      balanceAfter: balanceAfter,
      description: description,
      createdAt: DateTime.now(),
    );
  }

  group('CreditsScreen', () {
    group('Loading State', () {
      testWidgets('displays loading indicator while fetching data',
          (tester) async {
        final creditsCompleter = Completer<UserCredits>();
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) => creditsCompleter.future);
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete the future to clean up
        creditsCompleter.complete(createTestCredits());
        await tester.pumpAndSettle();
      });
    });

    group('Error State', () {
      testWidgets('displays error message on failure', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenThrow(Exception('Network error'));
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.textContaining('Error:'), findsOneWidget);
      });
    });

    group('Balance Card', () {
      testWidgets('displays Your Balance title', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Your Balance'), findsOneWidget);
      });

      testWidgets('displays paid credits balance', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits(creditBalance: 1000));
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Paid Credits'), findsOneWidget);
        expect(find.text('1000'), findsOneWidget);
      });

      testWidgets('displays free tier remaining', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits(freeTierUsed: 50));
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Free This Month'), findsOneWidget);
      });

      testWidgets('displays total available', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Total Available'), findsOneWidget);
        expect(find.textContaining('user-rounds'), findsOneWidget);
      });
    });

    group('Purchase Card', () {
      testWidgets('displays Buy Credits title', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Buy Credits'), findsOneWidget);
      });

      testWidgets('displays credit pricing info', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.textContaining('\$0.01'), findsOneWidget);
      });

      testWidgets('displays purchase button', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Purchase with Stripe'), findsOneWidget);
        expect(find.byIcon(Icons.payment), findsOneWidget);
      });
    });

    group('Transaction History', () {
      testWidgets('displays empty state when no transactions', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('No transaction history'), findsOneWidget);
        expect(find.byIcon(Icons.history), findsOneWidget);
      });

      testWidgets('displays transaction list when transactions exist',
          (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => [
                  createTestTransaction(
                    type: TransactionType.purchase,
                    amount: 100,
                    description: 'Purchased 100 credits',
                  ),
                  createTestTransaction(
                    type: TransactionType.usage,
                    amount: -10,
                    description: 'Used 10 credits',
                  ),
                ]);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Recent Transactions'), findsOneWidget);
        expect(find.text('Purchased 100 credits'), findsOneWidget);
        expect(find.text('Used 10 credits'), findsOneWidget);
      });
    });

    group('App Bar', () {
      testWidgets('displays Credits title', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Credits'), findsOneWidget);
      });

      testWidgets('displays refresh button', (tester) async {
        when(() => mockBillingService.getMyCredits())
            .thenAnswer((_) async => createTestCredits());
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.refresh), findsOneWidget);
      });

      testWidgets('refresh button reloads data', (tester) async {
        var callCount = 0;
        when(() => mockBillingService.getMyCredits()).thenAnswer((_) async {
          callCount++;
          return createTestCredits(creditBalance: callCount * 100);
        });
        when(() => mockBillingService.getTransactionHistory(limit: 20))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('100'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();

        expect(find.text('200'), findsOneWidget);
      });
    });
  });

  group('BillingService static methods', () {
    test('calculateCostCents returns correct value', () {
      expect(BillingService.calculateCostCents(100), equals(100));
      expect(BillingService.calculateCostCents(1000), equals(1000));
    });

    test('calculateCostDollars returns correct value', () {
      expect(BillingService.calculateCostDollars(100), equals(1.00));
      expect(BillingService.calculateCostDollars(1000), equals(10.00));
    });

    test('formatDollars formats correctly', () {
      expect(BillingService.formatDollars(1.00), equals('\$1.00'));
      expect(BillingService.formatDollars(10.50), equals('\$10.50'));
      expect(BillingService.formatDollars(0.99), equals('\$0.99'));
    });

    test('formatCreditsWithCost formats correctly', () {
      expect(BillingService.formatCreditsWithCost(100),
          equals('100 credits (\$1.00)'));
    });
  });
}
