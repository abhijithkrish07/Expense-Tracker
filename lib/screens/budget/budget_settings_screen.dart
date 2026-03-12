import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/budget_provider.dart';
import '../../utils/currency_formatter.dart';

final _budgetMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

class BudgetSettingsScreen extends ConsumerStatefulWidget {
  const BudgetSettingsScreen({super.key});

  @override
  ConsumerState<BudgetSettingsScreen> createState() =>
      _BudgetSettingsScreenState();
}

class _BudgetSettingsScreenState
    extends ConsumerState<BudgetSettingsScreen> {
  final _amountController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _loadBudgetForMonth(DateTime month) {
    final budget = ref
        .read(budgetProvider.notifier)
        .budgetFor(month.year, month.month);
    _amountController.text =
        budget != null ? budget.limitAmount.toStringAsFixed(2) : '';
  }

  Future<void> _save(DateTime month) async {
    final text = _amountController.text.replaceAll(',', '');
    final amount = double.tryParse(text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid budget amount')));
      return;
    }
    setState(() => _saving = true);
    await ref.read(budgetProvider.notifier).setBudget(
          year: month.year,
          month: month.month,
          limitAmount: amount,
        );
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Budget saved')));
    }
  }

  Future<void> _clear(DateTime month) async {
    final budget = ref
        .read(budgetProvider.notifier)
        .budgetFor(month.year, month.month);
    if (budget == null) return;
    await ref.read(budgetProvider.notifier).deleteBudget(budget.id);
    _amountController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Budget cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonth = ref.watch(_budgetMonthProvider);
    final budgets = ref.watch(budgetProvider).valueOrNull ?? [];
    final budget = budgets.cast<dynamic>().firstWhere(
          (b) =>
              b.year == selectedMonth.year &&
              b.month == selectedMonth.month &&
              b.categoryId == null,
          orElse: () => null,
        );

    // Sync text field when month changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadBudgetForMonth(selectedMonth);
    });

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Budget Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    final prev = DateTime(selectedMonth.year,
                        selectedMonth.month - 1);
                    ref.read(_budgetMonthProvider.notifier).state = prev;
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(selectedMonth),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    final next = DateTime(selectedMonth.year,
                        selectedMonth.month + 1);
                    ref.read(_budgetMonthProvider.notifier).state = next;
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Current budget status
            if (budget != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green),
                      const SizedBox(width: 12),
                      Text(
                        'Current budget: ${formatCurrency(budget.limitAmount)}',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: theme.colorScheme.outline),
                      const SizedBox(width: 12),
                      Text(
                        'No budget set for this month',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),

            Text('Monthly Budget Limit',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Budget Amount',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(selectedMonth),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save Budget'),
                  ),
                ),
                if (budget != null) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => _clear(selectedMonth),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
