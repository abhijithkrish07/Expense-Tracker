// Home expense list widgets: grouped daily list with swipe-to-delete and edit navigation.
// Caveat: grouping key uses formatted day headers, so locale format changes can affect ordering visuals.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/category.dart';
import '../../../models/expense.dart';
import '../../../providers/expense_provider.dart';
import '../../../utils/category_icons.dart';
import '../../../utils/currency_formatter.dart';
import '../../../utils/date_helpers.dart';
import '../../expense/add_edit_expense_screen.dart';

class HomeExpenseList extends ConsumerWidget {
  final List<Expense> expenses;
  final List<Category> categories;

  const HomeExpenseList({
    super.key,
    required this.expenses,
    required this.categories,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryById = <String, Category>{for (final c in categories) c.id: c};

    final grouped = <String, List<Expense>>{};
    for (final expense in expenses) {
      final key = formatDayHeader(expense.date);
      grouped.putIfAbsent(key, () => []).add(expense);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final dateKey = grouped.keys.elementAt(index);
        final dayExpenses = grouped[dateKey]!;
        final dayTotal = dayExpenses.fold(0.0, (sum, e) => sum + e.amount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateKey,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Text(
                    formatCurrency(dayTotal),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            ...dayExpenses.map((expense) {
              final category = categoryById[expense.categoryId];
              return _ExpenseTile(expense: expense, category: category, ref: ref);
            }),
          ],
        );
      },
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final Category? category;
  final WidgetRef ref;

  const _ExpenseTile({
    required this.expense,
    required this.category,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _safeCategoryColor(theme);

    return Dismissible(
      key: Key(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Expense'),
            content: Text('Delete "${expense.title}"? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref.read(expenseProvider.notifier).deleteExpense(expense.id);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"${expense.title}" deleted')));
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(
            iconFromName(category?.iconName ?? 'more_horiz'),
            color: color,
            size: 20,
          ),
        ),
        title: Text(expense.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: category != null
            ? Text(
                category!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            : null,
        trailing: SizedBox(
          width: 110,
          child: Text(
            formatCurrency(expense.amount),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddEditExpenseScreen(expense: expense)),
        ),
      ),
    );
  }

  Color _safeCategoryColor(ThemeData theme) {
    if (category == null) return theme.colorScheme.primary;
    final parsed = int.tryParse(category!.colorHex.replaceAll('#', ''), radix: 16);
    if (parsed == null) return theme.colorScheme.primary;
    return Color(parsed + 0xFF000000);
  }
}
