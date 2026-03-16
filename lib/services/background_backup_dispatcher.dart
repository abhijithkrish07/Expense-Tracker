import 'dart:io' as io;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'daily_backup_service.dart';

const String dailyBackupTaskName = 'dailyBackupTask';
const String dailyBackupUniqueWorkName = 'expenseTrackerDailyBackupWork';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (task == dailyBackupTaskName) {
      try {
        await DailyBackupService.ensureDueBackupExecuted(
          source: BackupRunSource.backgroundWorker,
        );
      } catch (_) {
        return Future.value(false);
      }
    }

    return Future.value(true);
  });
}

Future<void> configureBackgroundBackupWork() async {
  if (io.Platform.isIOS || io.Platform.isAndroid) {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  if (!io.Platform.isAndroid) {
    return;
  }

  await Workmanager().registerPeriodicTask(
    dailyBackupUniqueWorkName,
    dailyBackupTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: _initialDelayToNineAm(),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 30),
  );
}

Duration _initialDelayToNineAm() {
  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, 9);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next.difference(now);
}
