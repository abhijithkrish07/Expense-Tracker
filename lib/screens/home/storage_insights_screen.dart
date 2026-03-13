// Storage insights screen: page-level composition of cards and history widgets.
// Caveat: heavy calculations and history persistence are delegated to StorageService.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage_insights_provider.dart';
import 'widgets/storage_insights_cards.dart';
import 'widgets/storage_insights_trend_card.dart';

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
                TotalInsightCard(insights: insights),
                const SizedBox(height: 14),
                HistoryTrendCard(history: payload.history),
                const SizedBox(height: 14),
                Text('By Data Type', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...insights.buckets.map((bucket) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BucketInsightCard(bucket: bucket),
                  );
                }),
                const SizedBox(height: 8),
                const StorageInsightsInfoCard(),
              ],
            ),
          );
        },
      ),
    );
  }
}
