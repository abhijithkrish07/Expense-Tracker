// Storage insights metric row: shared label/value line used by multiple cards.
// Caveat: value text width is unconstrained by design and may clip in extreme localization scenarios.
import 'package:flutter/material.dart';

class StorageInsightsMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const StorageInsightsMetricRow({
    super.key,
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
