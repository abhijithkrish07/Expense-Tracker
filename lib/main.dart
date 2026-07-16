import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/background_backup_dispatcher.dart';
import 'services/daily_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch Flutter framework errors (widget build exceptions, etc.) so they
  // show as red-screen in debug but never terminate the release process.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // Startup services are best-effort — a failure must never prevent the app
  // from opening, which would trap the user with no way to recover data.
  try {
    await configureBackgroundBackupWork();
  } catch (e) {
    debugPrint('Background work setup failed: $e');
  }

  try {
    await DailyBackupService.initialize();
    await DailyBackupService.ensureDueBackupExecuted();
  } catch (e) {
    debugPrint('Backup service startup failed: $e');
  }

  runApp(const ProviderScope(child: ExpenseTrackerApp()));
}
