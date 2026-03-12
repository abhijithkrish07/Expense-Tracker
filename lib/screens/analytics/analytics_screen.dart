import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/empty_state_widget.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(analyticsMonthProvider);
    final summary = ref.watch(analyticsProvider);
    final categories = ref.watch(categoryProvider).valueOrNull ?? [];
    final budgets = ref.watch(budgetProvider).valueOrNull ?? [];

    final budget = budgets.cast<dynamic>().firstWhere(
          (b) =>
              b.year == selectedMonth.year &&
              b.month == selectedMonth.month &&
              b.categoryId == null,
          orElse: () => null,
        );

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Month selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  ref.read(analyticsMonthProvider.notifier).state =
                      DateTime(selectedMonth.year, selectedMonth.month - 1);
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
                  final next = DateTime(
                      selectedMonth.year, selectedMonth.month + 1);
                  if (!next.isAfter(DateTime.now())) {
                    ref.read(analyticsMonthProvider.notifier).state = next;
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Summary row
          Row(
            children: [
              _SummaryChip(
                  label: 'Total',
                  value: formatCurrency(summary.totalSpent)),
              const SizedBox(width: 8),
              _SummaryChip(
                  label: 'Avg/day',
                  value: formatCurrency(summary.avgPerDay)),
              const SizedBox(width: 8),
              _SummaryChip(
                  label: 'Expenses',
                  value: summary.categoryTotals
                      .fold(0, (sum, c) => sum + c.count)
                      .toString()),
            ],
          ),
          const SizedBox(height: 24),

          // Pie chart
          Text('By Category', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          summary.categoryTotals.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.pie_chart_outline,
                  title: 'No expenses',
                  subtitle: 'No data for this month',
                )
              : _CategoryPieChart(
                  summary: summary,
                  categories: categories,
                ),
          const SizedBox(height: 32),

          // Bar chart
          Text('Last 6 Months', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _MonthlyBarChart(
            summary: summary,
            budgetLimit: budget?.limitAmount,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 4),
              Text(value,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPieChart extends StatefulWidget {
  final AnalyticsSummary summary;
  final List<dynamic> categories;

  const _CategoryPieChart(
      {required this.summary, required this.categories});

  @override
  State<_CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<_CategoryPieChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = widget.summary.categoryTotals;
    final total = widget.summary.totalSpent;

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null) {
                      _touchedIndex = -1;
                    } else {
                      _touchedIndex =
                          response.touchedSection!.touchedSectionIndex;
                    }
                  });
                },
              ),
              sections: totals.asMap().entries.map((entry) {
                final i = entry.key;
                final ct = entry.value;
                final cat = widget.categories.cast<dynamic>().firstWhere(
                    (c) => c.id == ct.categoryId,
                    orElse: () => null);
                final color = cat != null
                    ? Color(int.parse(
                            cat.colorHex.replaceAll('#', ''),
                            radix: 16) +
                        0xFF000000)
                    : theme.colorScheme.primary;
                final isTouched = i == _touchedIndex;
                return PieChartSectionData(
                  value: ct.total,
                  color: color,
                  radius: isTouched ? 65 : 55,
                  title: isTouched
                      ? '${(ct.total / total * 100).toStringAsFixed(0)}%'
                      : '',
                  titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                );
              }).toList(),
              centerSpaceRadius: 50,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Legend
        ...totals.map((ct) {
          final cat = widget.categories.cast<dynamic>().firstWhere(
              (c) => c.id == ct.categoryId,
              orElse: () => null);
          final color = cat != null
              ? Color(int.parse(cat.colorHex.replaceAll('#', ''),
                      radix: 16) +
                  0xFF000000)
              : theme.colorScheme.primary;
          final pct = total > 0 ? ct.total / total * 100 : 0.0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(cat?.name ?? 'Unknown',
                        style: theme.textTheme.bodyMedium)),
                Text('${pct.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(width: 12),
                Text(formatCurrency(ct.total),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _MonthlyBarChart extends StatelessWidget {
  final AnalyticsSummary summary;
  final double? budgetLimit;

  const _MonthlyBarChart({required this.summary, this.budgetLimit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = summary.last6Months;
    if (months.every((m) => m.total == 0)) {
      return const EmptyStateWidget(
        icon: Icons.bar_chart,
        title: 'No data',
        subtitle: 'Start adding expenses to see trends',
      );
    }

    final maxY = [
      ...months.map((m) => m.total),
      ?budgetLimit,
    ].reduce((a, b) => a > b ? a : b) *
        1.2;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: months.asMap().entries.map((entry) {
            final i = entry.key;
            final m = entry.value;
            final isCurrentMonth = i == months.length - 1;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: m.total,
                  color: isCurrentMonth
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withAlpha(120),
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),
          extraLinesData: budgetLimit != null
              ? ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: budgetLimit!,
                    color: theme.colorScheme.error,
                    strokeWidth: 2,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      labelResolver: (_) =>
                          'Budget ${formatCurrency(budgetLimit!)}',
                      style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 10),
                    ),
                  ),
                ])
              : const ExtraLinesData(),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= months.length) {
                    return const SizedBox.shrink();
                  }
                  final m = months[i];
                  return Text(
                    DateFormat('MMM').format(DateTime(m.year, m.month)),
                    style:
                        TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final m = months[group.x.toInt()];
                return BarTooltipItem(
                  '${DateFormat('MMM yyyy').format(DateTime(m.year, m.month))}\n${formatCurrency(rod.toY)}',
                  TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontSize: 12),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
