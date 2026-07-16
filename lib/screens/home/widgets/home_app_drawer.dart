// Home app drawer: central navigation hub with data and danger-zone actions.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../analytics/analytics_screen.dart';
import '../../budget/budget_settings_screen.dart';
import '../../categories/categories_screen.dart';
import '../storage_insights_screen.dart';

class HomeAppDrawer extends StatelessWidget {
  final DateTime selectedMonth;
  final bool canDeleteMonthlyExpenses;
  final bool canDeleteAllYearsExpenses;
  final Future<void> Function() onExportExpenses;
  final Future<void> Function() onImportFromExcel;
  final Future<void> Function() onDeleteMonthlyExpenses;
  final Future<void> Function() onDeleteAllYearsExpenses;

  const HomeAppDrawer({
    super.key,
    required this.selectedMonth,
    required this.canDeleteMonthlyExpenses,
    required this.canDeleteAllYearsExpenses,
    required this.onExportExpenses,
    required this.onImportFromExcel,
    required this.onDeleteMonthlyExpenses,
    required this.onDeleteAllYearsExpenses,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final monthLabel = DateFormat('MMMM yyyy').format(selectedMonth);

    return Drawer(
      child: Column(
        children: [
          _DrawerHeader(colorScheme: colorScheme),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _SectionLabel('NAVIGATE'),
                _DrawerItem(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  selected: true,
                  onTap: () => Navigator.pop(context),
                ),
                _DrawerItem(
                  icon: Icons.bar_chart,
                  label: 'Analytics',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnalyticsScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _SectionLabel('MANAGE'),
                _DrawerItem(
                  icon: Icons.category_outlined,
                  label: 'Categories',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CategoriesScreen(),
                      ),
                    );
                  },
                ),
                _DrawerItem(
                  icon: Icons.savings_outlined,
                  label: 'Budget Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BudgetSettingsScreen(),
                      ),
                    );
                  },
                ),
                _DrawerItem(
                  icon: Icons.storage_outlined,
                  label: 'Storage Insights',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StorageInsightsScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _SectionLabel('DATA'),
                _DrawerItem(
                  icon: Icons.file_download_outlined,
                  label: 'Export to Excel',
                  onTap: () {
                    Navigator.pop(context);
                    onExportExpenses();
                  },
                ),
                _DrawerItem(
                  icon: Icons.file_upload_outlined,
                  label: 'Import from Excel',
                  subtitle: 'Add expenses from an exported .xlsx',
                  onTap: () {
                    Navigator.pop(context);
                    onImportFromExcel();
                  },
                ),
                const SizedBox(height: 8),
                _SectionLabel('DANGER ZONE'),
                _DrawerItem(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Delete Monthly Expenses',
                  subtitle: monthLabel,
                  danger: true,
                  enabled: canDeleteMonthlyExpenses,
                  onTap: () {
                    Navigator.pop(context);
                    onDeleteMonthlyExpenses();
                  },
                ),
                _DrawerItem(
                  icon: Icons.delete_forever_outlined,
                  label: 'Delete All Expenses',
                  danger: true,
                  enabled: canDeleteAllYearsExpenses,
                  onTap: () {
                    Navigator.pop(context);
                    onDeleteAllYearsExpenses();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  final ColorScheme colorScheme;

  const _DrawerHeader({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: MediaQuery.paddingOf(context).top + 20,
        bottom: 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            Color.alphaBlend(
              colorScheme.tertiary.withAlpha(120),
              colorScheme.primaryContainer,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(50),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Expense Tracker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'v1.0.1',
            style: TextStyle(
              color: Colors.white.withAlpha(200),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final bool danger;
  final bool enabled;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color contentColor;
    if (!enabled) {
      contentColor = theme.disabledColor;
    } else if (danger) {
      contentColor = colorScheme.error;
    } else if (selected) {
      contentColor = colorScheme.primary;
    } else {
      contentColor = colorScheme.onSurface;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected
            ? colorScheme.primary.withAlpha(30)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: contentColor, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: contentColor,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? colorScheme.onSurfaceVariant
                                : theme.disabledColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
