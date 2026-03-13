// Home app drawer: central navigation hub for home-related routes.
// Caveat: route navigation uses MaterialPageRoute and does not preserve nested navigation stacks.
import 'package:flutter/material.dart';

import '../../analytics/analytics_screen.dart';
import '../../budget/budget_settings_screen.dart';
import '../../categories/categories_screen.dart';
import '../storage_insights_screen.dart';

class HomeAppDrawer extends StatelessWidget {
  const HomeAppDrawer({super.key});

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
        ],
      ),
    );
  }
}
