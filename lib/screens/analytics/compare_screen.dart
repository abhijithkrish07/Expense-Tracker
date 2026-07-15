import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/analytics_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/empty_state_widget.dart';

class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  late DateTime _monthA;
  late DateTime _monthB;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthA = DateTime(now.year, now.month - 1);
    _monthB = DateTime(now.year, now.month);
  }

  Future<void> _pickMonth(bool isA) async {
    final now = DateTime.now();
    // Build list of last 24 months newest-first
    final months = List.generate(24, (i) {
      return DateTime(now.year, now.month - i);
    });

    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => _MonthPickerSheet(
        months: months,
        current: isA ? _monthA : _monthB,
      ),
    );

    if (selected != null) {
      setState(() {
        if (isA) {
          _monthA = selected;
        } else {
          _monthB = selected;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryProvider).valueOrNull ?? [];
    final data = ref.watch(compareProvider((_monthA, _monthB)));
    final theme = Theme.of(context);

    final bothEmpty = data.monthA.total == 0 && data.monthB.total == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Compare Months')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Month pickers
          Row(
            children: [
              Expanded(child: _MonthChip(
                month: _monthA,
                colorSwatch: theme.colorScheme.primary,
                onTap: () => _pickMonth(true),
              )),
              const SizedBox(width: 12),
              Expanded(child: _MonthChip(
                month: _monthB,
                colorSwatch: theme.colorScheme.secondary,
                onTap: () => _pickMonth(false),
              )),
            ],
          ),
          const SizedBox(height: 20),

          if (bothEmpty)
            const EmptyStateWidget(
              icon: Icons.compare_arrows,
              title: 'No data',
              subtitle: 'No expenses found for either selected month',
            )
          else ...[
            // ── Summary card ──────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Summary', style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _SummaryRow(
                      label: 'Total Spend',
                      valueA: formatCurrency(data.monthA.total),
                      valueB: formatCurrency(data.monthB.total),
                      delta: data.monthB.total - data.monthA.total,
                      baseA: data.monthA.total,
                    ),
                    const Divider(height: 20),
                    _SummaryRow(
                      label: 'Avg / Day',
                      valueA: formatCurrency(data.monthA.avgPerDay),
                      valueB: formatCurrency(data.monthB.avgPerDay),
                      delta: data.monthB.avgPerDay - data.monthA.avgPerDay,
                      baseA: data.monthA.avgPerDay,
                    ),
                    const Divider(height: 20),
                    _SummaryRow(
                      label: 'Expenses',
                      valueA: '${data.monthA.expenseCount}',
                      valueB: '${data.monthB.expenseCount}',
                      delta: (data.monthB.expenseCount - data.monthA.expenseCount).toDouble(),
                      baseA: data.monthA.expenseCount.toDouble(),
                      isCurrency: false,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Category breakdown ────────────────────────────────
            Text('By Category', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _CategoryCompareList(
              monthA: data.monthA,
              monthB: data.monthB,
              categories: categories,
              colorA: theme.colorScheme.primary,
              colorB: theme.colorScheme.secondary,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Month picker chip ────────────────────────────────────────────────────────

class _MonthChip extends StatelessWidget {
  final DateTime month;
  final Color colorSwatch;
  final VoidCallback onTap;

  const _MonthChip({
    required this.month,
    required this.colorSwatch,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: colorSwatch, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: colorSwatch, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                DateFormat('MMM yyyy').format(month),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: colorSwatch),
          ],
        ),
      ),
    );
  }
}

// ── Bottom sheet month picker ────────────────────────────────────────────────

class _MonthPickerSheet extends StatelessWidget {
  final List<DateTime> months;
  final DateTime current;

  const _MonthPickerSheet({required this.months, required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Select Month', style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: months.length,
              itemBuilder: (_, i) {
                final m = months[i];
                final isSelected = m.year == current.year && m.month == current.month;
                return ChoiceChip(
                  label: Text(
                    DateFormat('MMM yy').format(m),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) => Navigator.pop(context, m),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary comparison row ───────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String valueA;
  final String valueB;
  final double delta;
  final double baseA;
  final bool isCurrency;

  const _SummaryRow({
    required this.label,
    required this.valueA,
    required this.valueB,
    required this.delta,
    required this.baseA,
    this.isCurrency = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = baseA != 0 ? (delta / baseA * 100).abs() : 0.0;
    final isIncrease = delta > 0;
    final isFlat = delta == 0;

    final deltaColor = isFlat
        ? theme.colorScheme.outline
        : isIncrease
            ? theme.colorScheme.error
            : Colors.green.shade600;

    final trendIcon = isFlat
        ? Icons.trending_flat
        : isIncrease
            ? Icons.trending_up
            : Icons.trending_down;

    final deltaText = isFlat
        ? 'No change'
        : '${isIncrease ? '+' : ''}${isCurrency ? formatCurrency(delta) : delta.toStringAsFixed(0)}  ${pct.toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(valueA,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.arrow_forward, size: 14, color: theme.colorScheme.outline),
            Expanded(
              child: Text(valueB,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Icon(trendIcon, size: 18, color: deltaColor),
            const SizedBox(width: 4),
            Text(deltaText,
                style: theme.textTheme.bodySmall?.copyWith(color: deltaColor)),
          ],
        ),
      ],
    );
  }
}

// ── Category compare list ────────────────────────────────────────────────────

class _CategoryCompareList extends StatelessWidget {
  final MonthCompare monthA;
  final MonthCompare monthB;
  final List<dynamic> categories;
  final Color colorA;
  final Color colorB;

  const _CategoryCompareList({
    required this.monthA,
    required this.monthB,
    required this.categories,
    required this.colorA,
    required this.colorB,
  });

  @override
  Widget build(BuildContext context) {
    // Union all category IDs from both months
    final allIds = {
      ...monthA.categoryTotals.map((c) => c.categoryId),
      ...monthB.categoryTotals.map((c) => c.categoryId),
    };

    final mapA = {for (final c in monthA.categoryTotals) c.categoryId: c.total};
    final mapB = {for (final c in monthB.categoryTotals) c.categoryId: c.total};

    final sorted = allIds.toList()
      ..sort((a, b) {
        final maxA = [mapA[a] ?? 0.0, mapB[a] ?? 0.0].reduce((x, y) => x > y ? x : y);
        final maxB = [mapA[b] ?? 0.0, mapB[b] ?? 0.0].reduce((x, y) => x > y ? x : y);
        return maxB.compareTo(maxA);
      });

    return Column(
      children: sorted.map((categoryId) {
        final cat = categories.cast<dynamic>().firstWhere(
            (c) => c.id == categoryId, orElse: () => null);
        final catName = cat?.name ?? 'Unknown';
        final catColor = cat != null
            ? Color(int.parse(cat.colorHex.replaceAll('#', ''), radix: 16) + 0xFF000000)
            : Theme.of(context).colorScheme.primary;
        final aVal = mapA[categoryId] ?? 0.0;
        final bVal = mapB[categoryId] ?? 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _CategoryRow(
            name: catName,
            dotColor: catColor,
            amountA: aVal,
            amountB: bVal,
            colorA: colorA,
            colorB: colorB,
          ),
        );
      }).toList(),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String name;
  final Color dotColor;
  final double amountA;
  final double amountB;
  final Color colorA;
  final Color colorB;

  const _CategoryRow({
    required this.name,
    required this.dotColor,
    required this.amountA,
    required this.amountB,
    required this.colorA,
    required this.colorB,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = amountB - amountA;
    final pct = amountA != 0 ? (delta / amountA * 100).abs() : 0.0;
    final isIncrease = delta > 0;
    final isFlat = delta == 0;

    final deltaColor = isFlat
        ? theme.colorScheme.outline
        : isIncrease
            ? theme.colorScheme.error
            : Colors.green.shade600;

    final trendIcon = isFlat
        ? Icons.trending_flat
        : isIncrease
            ? Icons.trending_up
            : Icons.trending_down;

    final maxVal = amountA > amountB ? amountA : amountB;
    final barA = maxVal > 0 ? amountA / maxVal : 0.0;
    final barB = maxVal > 0 ? amountB / maxVal : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name, style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
            ),
            Icon(trendIcon, size: 16, color: deltaColor),
            const SizedBox(width: 4),
            Text(
              isFlat
                  ? 'No change'
                  : '${isIncrease ? '+' : ''}${formatCurrency(delta)}  ${pct.toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall?.copyWith(color: deltaColor),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bar A
                  LayoutBuilder(builder: (ctx, constraints) {
                    return Row(
                      children: [
                        Container(
                          height: 6,
                          width: constraints.maxWidth * barA,
                          decoration: BoxDecoration(
                            color: colorA,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        if (barA < 1)
                          Container(
                            height: 6,
                            width: constraints.maxWidth * (1 - barA),
                            decoration: BoxDecoration(
                              color: colorA.withAlpha(40),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    );
                  }),
                  const SizedBox(height: 3),
                  // Bar B
                  LayoutBuilder(builder: (ctx, constraints) {
                    return Row(
                      children: [
                        Container(
                          height: 6,
                          width: constraints.maxWidth * barB,
                          decoration: BoxDecoration(
                            color: colorB,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        if (barB < 1)
                          Container(
                            height: 6,
                            width: constraints.maxWidth * (1 - barB),
                            decoration: BoxDecoration(
                              color: colorB.withAlpha(40),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatCurrency(amountA),
                      style: theme.textTheme.bodySmall?.copyWith(color: colorA)),
                  Text(formatCurrency(amountB),
                      style: theme.textTheme.bodySmall?.copyWith(color: colorB)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
