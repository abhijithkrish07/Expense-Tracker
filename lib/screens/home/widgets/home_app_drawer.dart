// Home app drawer: central navigation hub with backup/restore actions.
import 'package:flutter/material.dart';

import '../../analytics/analytics_screen.dart';
import '../../budget/budget_settings_screen.dart';
import '../../categories/categories_screen.dart';
import '../storage_insights_screen.dart';

class HomeAppDrawer extends StatelessWidget {
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;

  const HomeAppDrawer({
    super.key,
    required this.onCreateBackup,
    required this.onRestoreBackup,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  'Expense Tracker',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Analytics'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('Categories'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.savings),
            title: const Text('Budget Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BudgetSettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Storage Insights'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StorageInsightsScreen()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Create Data Backup'),
            subtitle: const Text('Create compact delta + refresh latest full backup'),
            onTap: () {
              Navigator.pop(context);
              onCreateBackup();
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore_page_outlined),
            title: const Text('Restore Data Backup'),
            subtitle: const Text('Restore from Downloads/ExpenseTracker_Backups/'),
            onTap: () {
              Navigator.pop(context);
              onRestoreBackup();
            },
          ),
        ],
      ),
    );
  }
}
