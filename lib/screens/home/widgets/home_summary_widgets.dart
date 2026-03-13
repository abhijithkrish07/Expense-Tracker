// Home summary widgets: month navigation and monthly budget/spend snapshot.
// Caveat: month navigation intentionally blocks future months.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/currency_formatter.dart';

class HomeMonthSelector extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const HomeMonthSelector({
    super.key,
    required this.selectedMonth,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
          Text(
            DateFormat('MMMM yyyy').format(selectedMonth),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

class HomeBudgetCard extends StatelessWidget {
  final double totalSpent;
  final double? budget;

  const HomeBudgetCard({
    super.key,
    required this.totalSpent,
    required this.budget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBudget = budget != null && budget! > 0;
    final progress = hasBudget ? (totalSpent / budget!).clamp(0.0, 1.0) : 0.0;

    var progressColor = theme.colorScheme.primary;
    if (hasBudget) {
      if (progress >= 1.0) {
        progressColor = theme.colorScheme.error;
      } else if (progress >= 0.75) {
        progressColor = Colors.orange;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Spent',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  if (hasBudget)
                    Text(
                      'Budget: ${formatCurrency(budget!)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatCurrency(totalSpent),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hasBudget) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}% of budget used',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'No budget set for this month',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
