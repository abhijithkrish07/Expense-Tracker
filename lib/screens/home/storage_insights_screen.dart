import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/storage_provider.dart';
import '../../services/storage_service.dart';

final storageInsightsProvider = FutureProvider<StorageInsightsWithHistory>((
  ref,
) async {
  final storage = ref.read(storageServiceProvider);
  return storage.loadStorageInsightsWithHistory();
});

class StorageInsightsScreen extends ConsumerWidget {
  const StorageInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(storageInsightsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Storage Insights')),
      body: insightsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (payload) {
          final insights = payload.current;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(storageInsightsProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TotalInsightCard(insights: insights),
                const SizedBox(height: 14),
                _HistoryTrendCard(history: payload.history),
                const SizedBox(height: 14),
                Text('By Data Type', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...insights.buckets.map((bucket) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BucketInsightCard(bucket: bucket),
                  );
                }),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Raw size is estimated from your plain JSON data. Stored size is what is actually saved on this device after compression and encryption.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TotalInsightCard extends StatelessWidget {
  final StorageInsights insights;

  const _TotalInsightCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedBytes = insights.totalDifferenceBytes;
    final reduction = insights.totalReductionPercent;

    final titleColor = savedBytes >= 0
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overall Storage Impact',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _MetricRow(
              label: 'Raw JSON size',
              value: _formatBytes(insights.totalRawBytes),
            ),
            _MetricRow(
              label: 'Stored size',
              value: _formatBytes(insights.totalPersistedBytes),
            ),
            const Divider(height: 20),
            _MetricRow(
              label: savedBytes >= 0 ? 'Space reduced' : 'Storage overhead',
              value: _formatBytes(savedBytes.abs()),
              valueColor: titleColor,
            ),
            const SizedBox(height: 8),
            Text(
              '${reduction >= 0 ? 'Reduction' : 'Overhead'}: ${reduction.abs().toStringAsFixed(1)}%',
              style: theme.textTheme.titleSmall?.copyWith(
                color: titleColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BucketInsightCard extends StatelessWidget {
  final StorageBucketInsight bucket;

  const _BucketInsightCard({required this.bucket});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduction = bucket.reductionPercent;
    final isReduced = reduction >= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bucket.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _MetricRow(label: 'Raw', value: _formatBytes(bucket.rawBytes)),
            _MetricRow(
              label: 'Stored',
              value: _formatBytes(bucket.persistedBytes),
            ),
            const SizedBox(height: 6),
            Text(
              '${isReduced ? 'Reduced' : 'Overhead'}: ${reduction.abs().toStringAsFixed(1)}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isReduced
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTrendCard extends StatelessWidget {
  final List<StorageInsightSnapshot> history;

  const _HistoryTrendCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    final points = history.length <= 12
        ? history
        : history.sublist(history.length - 12);
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
                  final ratio = maxStored <= 0
                      ? 0.0
                      : point.persistedBytes / maxStored;
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
            _MetricRow(
              label: 'Latest stored size',
              value: _formatBytes(last.persistedBytes),
            ),
            _MetricRow(
              label: 'Latest saved',
              value: _formatBytes(last.savedBytes.abs()),
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

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  if (bytes <= 0) return '0 B';

  double size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }

  final precision = size >= 10 || unit == 0 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unit]}';
}
