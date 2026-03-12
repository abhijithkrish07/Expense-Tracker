import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense.dart';
import 'expense_provider.dart';

class CategoryTotal {
  final String categoryId;
  final double total;
  final int count;

  const CategoryTotal({
    required this.categoryId,
    required this.total,
    required this.count,
  });
}

class MonthlyTotal {
  final int year;
  final int month;
  final double total;

  const MonthlyTotal({
    required this.year,
    required this.month,
    required this.total,
  });
}

class AnalyticsSummary {
  final List<CategoryTotal> categoryTotals;
  final List<MonthlyTotal> last6Months;
  final double totalSpent;
  final double avgPerDay;
  final int daysInPeriod;

  const AnalyticsSummary({
    required this.categoryTotals,
    required this.last6Months,
    required this.totalSpent,
    required this.avgPerDay,
    required this.daysInPeriod,
  });

  static AnalyticsSummary compute(
      List<Expense> all, int year, int month) {
    // Filter to selected month
    final monthly = all
        .where((e) => e.date.year == year && e.date.month == month)
        .toList();

    // Category totals
    final Map<String, double> catMap = {};
    final Map<String, int> catCount = {};
    for (final e in monthly) {
      catMap[e.categoryId] = (catMap[e.categoryId] ?? 0) + e.amount;
      catCount[e.categoryId] = (catCount[e.categoryId] ?? 0) + 1;
    }
    final categoryTotals = catMap.entries
        .map((entry) => CategoryTotal(
              categoryId: entry.key,
              total: entry.value,
              count: catCount[entry.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // Total
    final totalSpent = monthly.fold(0.0, (sum, e) => sum + e.amount);

    // Days in period (for avg/day)
    final now = DateTime.now();
    int daysInPeriod;
    if (year == now.year && month == now.month) {
      daysInPeriod = now.day;
    } else {
      daysInPeriod = DateTime(year, month + 1, 0).day;
    }
    final avgPerDay = daysInPeriod > 0 ? totalSpent / daysInPeriod : 0.0;

    // Last 6 months totals
    final last6 = <MonthlyTotal>[];
    for (int i = 5; i >= 0; i--) {
      final dt = DateTime(year, month - i, 1);
      final y = dt.year;
      final m = dt.month;
      final total = all
          .where((e) => e.date.year == y && e.date.month == m)
          .fold(0.0, (sum, e) => sum + e.amount);
      last6.add(MonthlyTotal(year: y, month: m, total: total));
    }

    return AnalyticsSummary(
      categoryTotals: categoryTotals,
      last6Months: last6,
      totalSpent: totalSpent,
      avgPerDay: avgPerDay,
      daysInPeriod: daysInPeriod,
    );
  }
}

// Holds the currently selected month for analytics
final analyticsMonthProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

final analyticsProvider = Provider<AnalyticsSummary>((ref) {
  final expenses = ref.watch(expenseProvider).valueOrNull ?? [];
  final month = ref.watch(analyticsMonthProvider);
  return AnalyticsSummary.compute(expenses, month.year, month.month);
});
