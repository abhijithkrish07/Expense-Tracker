import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/budget_provider.dart';
import 'providers/category_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/daily_backup_service.dart';

const _restorePromptedKey = 'backup_restore_prompted_v1';

class ExpenseTrackerApp extends ConsumerStatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  ConsumerState<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends ConsumerState<ExpenseTrackerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoRestore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DailyBackupService.ensureDueBackupExecuted();
    }
  }

  Future<void> _checkAutoRestore() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_restorePromptedKey) == true) return;

    final backup = await DailyBackupService.findLatestBackup();
    if (backup == null) {
      await prefs.setBool(_restorePromptedKey, true);
      return;
    }

    // Only prompt when local data is empty (fresh install / cleared app).
    final expenses = await ref.read(expenseProvider.future);
    if (expenses.isNotEmpty) {
      await prefs.setBool(_restorePromptedKey, true);
      return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup Found'),
        content: Text(
          'A previous backup was found from '
          '${DateFormat('dd MMM yyyy, HH:mm').format(backup.createdAt)}.\n\n'
          '${backup.expenseCount} expense${backup.expenseCount == 1 ? '' : 's'}, '
          '${backup.categoryCount} categor${backup.categoryCount == 1 ? 'y' : 'ies'}, '
          '${backup.budgetCount} budget${backup.budgetCount == 1 ? '' : 's'}\n\n'
          'Would you like to restore it now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    await prefs.setBool(_restorePromptedKey, true);

    if (confirmed != true || !mounted) return;

    final ok = await DailyBackupService.restoreFromLatestBackup();

    if (!mounted) return;
    if (ok) {
      ref.invalidate(expenseProvider);
      ref.invalidate(categoryProvider);
      ref.invalidate(budgetProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore failed. The backup file may be corrupt.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.dark;

    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      ),
      home: const HomeScreen(),
    );
  }
}
