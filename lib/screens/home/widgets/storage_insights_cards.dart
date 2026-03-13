// Storage insights cards: summary and per-bucket compression/encryption impact views.
// Caveat: negative reduction is displayed as overhead when encrypted payload exceeds raw size.
import 'package:flutter/material.dart';

import '../../../services/storage_service.dart';
import 'storage_insights_formatters.dart';
import 'storage_insights_metric_row.dart';

class TotalInsightCard extends StatelessWidget {
  final StorageInsights insights;

  const TotalInsightCard({super.key, required this.insights});

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
            StorageInsightsMetricRow(
              label: 'Raw JSON size',
              value: formatStorageBytes(insights.totalRawBytes),
            ),
            StorageInsightsMetricRow(
              label: 'Stored size',
              value: formatStorageBytes(insights.totalPersistedBytes),
            ),
            const Divider(height: 20),
            StorageInsightsMetricRow(
              label: savedBytes >= 0 ? 'Space reduced' : 'Storage overhead',
              value: formatStorageBytes(savedBytes.abs()),
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

class BucketInsightCard extends StatelessWidget {
  final StorageBucketInsight bucket;

  const BucketInsightCard({super.key, required this.bucket});

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
            StorageInsightsMetricRow(
              label: 'Raw',
              value: formatStorageBytes(bucket.rawBytes),
            ),
            StorageInsightsMetricRow(
              label: 'Stored',
              value: formatStorageBytes(bucket.persistedBytes),
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

class StorageInsightsInfoCard extends StatelessWidget {
  const StorageInsightsInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Raw size is estimated from your plain JSON data. Stored size is what is actually saved on this device after compression and encryption.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
