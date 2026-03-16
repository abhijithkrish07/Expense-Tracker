import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/background_backup_dispatcher.dart';
import 'services/daily_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureBackgroundBackupWork();
  await DailyBackupService.initialize();
  await DailyBackupService.ensureDueBackupExecuted();
  runApp(const ProviderScope(child: ExpenseTrackerApp()));
}
