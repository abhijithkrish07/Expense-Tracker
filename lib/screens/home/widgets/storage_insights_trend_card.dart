// Storage insights trend card: compact history visualization for stored payload growth.
// Caveat: chart intentionally shows latest 12 points only to keep UI lightweight.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/storage_service.dart';
import 'storage_insights_formatters.dart';
import 'storage_insights_metric_row.dart';

class HistoryTrendCard extends StatelessWidget {
  final List<StorageInsightSnapshot> history;

  const HistoryTrendCard({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    final points =
        history.length <= 12 ? history : history.sublist(history.length - 12);
    final maxStored = points
        .map((e) => e.persistedBytes)
        .fold<int>(0, (max, value) => value > max ? value : max);
    final last = points.last;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage Trend',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last ${points.length} snapshots (stored size)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 84,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: points.map((point) {
                  final ratio =
                      maxStored <= 0 ? 0.0 : point.persistedBytes / maxStored;
                  final barHeight = 10 + (ratio * 64);
                  final isLast = identical(point, last);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: isLast
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withAlpha(90),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('dd MMM').format(points.first.measuredAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  DateFormat('dd MMM').format(points.last.measuredAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            StorageInsightsMetricRow(
              label: 'Latest stored size',
              value: formatStorageBytes(last.persistedBytes),
            ),
            StorageInsightsMetricRow(
              label: 'Latest saved',
              value: formatStorageBytes(last.savedBytes.abs()),
              valueColor: last.savedBytes >= 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}
