import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/user_credits.dart';
import '../../services/billing_service.dart';

/// Screen for viewing and purchasing credits
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  late final BillingService _billingService;
  UserCredits? _credits;
  List<CreditTransaction>? _transactions;
  bool _isLoading = true;
  String? _error;

  // Purchase form state
  int _purchaseCredits = 100;
  bool _isPurchasing = false;
  Timer? _incrementTimer;

  // Auto-refill form state
  bool _isUpdatingAutoRefill = false;
  late TextEditingController _thresholdController;
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _billingService = BillingService(Supabase.instance.client);
    _thresholdController = TextEditingController(text: '50');
    _amountController = TextEditingController(text: '500');
    _loadData();
  }

  @override
  void dispose() {
    _incrementTimer?.cancel();
    _thresholdController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final credits = await _billingService.getMyCredits();
      final transactions = await _billingService.getTransactionHistory(limit: 20);

      setState(() {
        _credits = credits;
        _transactions = transactions;
        _isLoading = false;
        // Update auto-refill controllers with loaded values
        if (credits != null) {
          _thresholdController.text = credits.autoRefillThreshold.toString();
          _amountController.text = credits.autoRefillAmount.toString();
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAutoRefill(bool enabled) async {
    if (_credits == null) return;

    setState(() => _isUpdatingAutoRefill = true);

    try {
      final threshold = int.tryParse(_thresholdController.text) ?? 50;
      final amount = int.tryParse(_amountController.text) ?? 500;

      final updated = await _billingService.updateAutoRefillSettings(
        enabled: enabled,
        threshold: threshold,
        amount: amount,
      );

      if (updated != null) {
        setState(() => _credits = updated);
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(enabled ? l10n.autoRefillEnabled : l10n.autoRefillDisabled),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAutoRefill = false);
      }
    }
  }

  Future<void> _updateAutoRefillSettings() async {
    if (_credits == null) return;

    final l10n = AppLocalizations.of(context)!;
    final threshold = int.tryParse(_thresholdController.text) ?? 50;
    final amount = int.tryParse(_amountController.text) ?? 500;

    if (amount <= threshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.refillAmountMustBeGreater)),
      );
      return;
    }

    setState(() => _isUpdatingAutoRefill = true);

    try {
      final updated = await _billingService.updateAutoRefillSettings(
        enabled: _credits!.autoRefillEnabled,
        threshold: threshold,
        amount: amount,
      );

      if (updated != null) {
        setState(() => _credits = updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.autoRefillSettingsUpdated)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAutoRefill = false);
      }
    }
  }

  void _startIncrement(int delta) {
    _updateCredits(delta);
    _incrementTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateCredits(delta);
    });
  }

  void _stopIncrement() {
    _incrementTimer?.cancel();
    _incrementTimer = null;
  }

  void _updateCredits(int delta) {
    setState(() {
      _purchaseCredits = (_purchaseCredits + delta).clamp(1, 100000);
    });
  }

  Future<void> _handlePurchase() async {
    setState(() => _isPurchasing = true);

    try {
      final url = await _billingService.createCheckoutSession(_purchaseCredits);
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Could not launch checkout URL');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.creditsTitle),
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
              ? Center(child: Text(l10n.error(_error!)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildBalanceCard(),
                        const SizedBox(height: 24),
                        _buildPurchaseCard(),
                        const SizedBox(height: 24),
                        _buildAutoRefillCard(),
                        const SizedBox(height: 24),
                        _buildTransactionHistory(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildBalanceCard() {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.yourBalance,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildBalanceItem(
                    l10n.paidCredits,
                    '${_credits?.creditBalance ?? 0}',
                    Icons.account_balance_wallet,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildBalanceItem(
                    l10n.freeThisMonth,
                    '${_credits?.freeTierRemaining ?? UserCredits.freeTierMonthlyLimit}',
                    Icons.card_giftcard,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.totalAvailable,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${_credits?.totalAvailable ?? UserCredits.freeTierMonthlyLimit} ${l10n.userRounds}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.freeTierResets(_credits?.freeTierResetAt != null ? _formatResetDate(_credits!.freeTierResetAt) : 'next month'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceItem(String label, String value, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }

  Widget _buildPurchaseCard() {
    final l10n = AppLocalizations.of(context)!;
    final cost = BillingService.calculateCostDollars(_purchaseCredits);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.buyCredits,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.pricingInfo,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Decrement button
                GestureDetector(
                  onTap: () => _updateCredits(-1),
                  onLongPressStart: (_) => _startIncrement(-10),
                  onLongPressEnd: (_) => _stopIncrement(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.remove),
                  ),
                ),
                const SizedBox(width: 16),
                // Credits input
                SizedBox(
                  width: 120,
                  child: TextField(
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                    controller: TextEditingController(text: '$_purchaseCredits'),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        setState(() {
                          _purchaseCredits = parsed.clamp(1, 100000);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Increment button
                GestureDetector(
                  onTap: () => _updateCredits(1),
                  onLongPressStart: (_) => _startIncrement(10),
                  onLongPressEnd: (_) => _stopIncrement(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.total,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  BillingService.formatDollars(cost),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isPurchasing ? null : _handlePurchase,
                icon: _isPurchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.payment),
                label: Text(_isPurchasing ? l10n.processing : l10n.purchaseWithStripe),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoRefillCard() {
    final l10n = AppLocalizations.of(context)!;
    final hasPaymentMethod = _credits?.hasPaymentMethod ?? false;
    final autoRefillEnabled = _credits?.autoRefillEnabled ?? false;
    final lastError = _credits?.autoRefillLastError;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.autorenew,
                  color: autoRefillEnabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.autoRefillTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_isUpdatingAutoRefill)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: autoRefillEnabled,
                    onChanged: hasPaymentMethod
                        ? (value) => _toggleAutoRefill(value)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.autoRefillDesc,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            if (lastError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.lastError(lastError),
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (!hasPaymentMethod) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.autoRefillComingSoon,
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _thresholdController,
                      decoration: InputDecoration(
                        labelText: l10n.whenBelow,
                        suffixText: l10n.credits,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      decoration: InputDecoration(
                        labelText: l10n.refillTo,
                        suffixText: l10n.credits,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isUpdatingAutoRefill ? null : _updateAutoRefillSettings,
                      child: Text(l10n.saveSettings),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(l10n.removePaymentMethodQuestion),
                          content: Text(
                            l10n.disableAutoRefillMessage,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: Text(l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: Text(l10n.remove),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _billingService.removePaymentMethod();
                        _loadData();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(l10n.removeCard),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionHistory() {
    final l10n = AppLocalizations.of(context)!;
    if (_transactions == null || _transactions!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.history, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                l10n.noTransactionHistory,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
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
              l10n.recentTransactions,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions!.length,
              separatorBuilder: (_, a) => const Divider(),
              itemBuilder: (context, index) {
                final tx = _transactions![index];
                return _buildTransactionItem(tx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(CreditTransaction tx) {
    final isCredit = tx.isCredit;
    final color = isCredit ? Colors.green : Colors.red;
    final sign = isCredit ? '+' : '';

    IconData icon;
    switch (tx.transactionType) {
      case TransactionType.purchase:
        icon = Icons.shopping_cart;
        break;
      case TransactionType.usage:
        icon = Icons.play_circle_outline;
        break;
      case TransactionType.refund:
        icon = Icons.replay;
        break;
      case TransactionType.adjustment:
        icon = Icons.tune;
        break;
      case TransactionType.autoRefill:
        icon = Icons.autorenew;
        break;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(icon, color: color),
      ),
      title: Text(tx.description ?? tx.transactionType.name),
      subtitle: Text(_formatDate(tx.createdAt)),
      trailing: Text(
        '$sign${tx.amount}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 16,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatResetDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);

    if (diff.inDays > 1) {
      return 'in ${diff.inDays} days';
    } else if (diff.inDays == 1) {
      return 'tomorrow';
    } else if (diff.inHours > 1) {
      return 'in ${diff.inHours} hours';
    } else {
      return 'soon';
    }
  }
}
