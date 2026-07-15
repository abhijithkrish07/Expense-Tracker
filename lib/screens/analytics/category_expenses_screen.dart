import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/category.dart';
import '../../providers/expense_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/empty_state_widget.dart';
import '../home/widgets/home_expense_list.dart';

class CategoryExpensesScreen extends ConsumerWidget {
  final String categoryId;
  final String categoryName;
  final int year;
  final int month;

  const CategoryExpensesScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.year,
    required this.month,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allExpenses = ref.watch(expenseProvider).valueOrNull ?? [];
    final categories = ref.watch(categoryProvider).valueOrNull ?? [];

    final filtered = allExpenses
        .where((e) =>
            e.categoryId == categoryId &&
            e.date.year == year &&
            e.date.month == month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final total = filtered.fold(0.0, (sum, e) => sum + e.amount);
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime(year, month));

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  monthLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                Text(
                  '${filtered.length} expense${filtered.length == 1 ? '' : 's'} · ${formatCurrency(total)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const EmptyStateWidget(
              icon: Icons.receipt_long_outlined,
              title: 'No expenses',
              subtitle: 'No expenses in this category for the selected month',
            )
          : HomeExpenseList(
              expenses: filtered,
              categories: categories.cast<Category>(),
            ),
    );
  }
}
