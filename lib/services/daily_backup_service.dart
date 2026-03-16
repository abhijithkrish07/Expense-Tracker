import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart'
  show kIsWeb, debugPrint, debugPrintStack;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../services/storage_service.dart';

enum BackupRunSource { foregroundApp, backgroundWorker }

class DailyBackupService {
  DailyBackupService._();

  static const _backupSchemaVersion = 1;
  static const _backupDirectoryName = 'ExpenseTracker_Backups';
  static const _latestFullBackupFileName = 'ExpenseTracker_Backup_Latest.json';
  static const _maxDeltaBackupFiles = 24;
  static const _lastAutoBackupDateKey = 'last_auto_backup_date_v1';

  static const _notificationChannelId = 'daily_backup_channel';
  static const _notificationChannelName = 'Daily Backup';
  static const _notificationChannelDescription =
      'Notifications for mandatory daily backup at 09:00';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  static Future<void> initialize() async {
    if (kIsWeb) return;

    await _ensureNotificationsInitialized();
    await _scheduleDailyReminder();
  }

  static Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _notifications.initialize(initSettings);
    _notificationsInitialized = true;

    final androidImpl =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl =
        _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> _scheduleDailyReminder() async {
    tz.initializeTimeZones();
    final local = tz.local;

    await _notifications.zonedSchedule(
      9001,
      'Expense Tracker Backup',
      'Mandatory backup check runs now. Keep app opened briefly.',
      _nextInstanceOfNineAm(local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannelId,
          _notificationChannelName,
          channelDescription: _notificationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> ensureDueBackupExecuted({
    BackupRunSource source = BackupRunSource.foregroundApp,
  }) async {
    if (kIsWeb) return;

    await _ensureNotificationsInitialized();

    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    // Enforce daily backup at or after 09:00 local time.
    final isAfterBackupTime =
        now.hour > 9 || (now.hour == 9 && now.minute >= 0);
    if (!isAfterBackupTime) return;

    final prefs = await SharedPreferences.getInstance();
    final lastBackupDate = prefs.getString(_lastAutoBackupDateKey);
    if (lastBackupDate == todayKey) return;

    int changedItems;
    try {
      changedItems = await _createOrUpdateDeltaBackup();
    } on io.FileSystemException catch (error) {
      debugPrint('Daily backup skipped due to file system access: $error');
      return;
    } catch (error, stackTrace) {
      debugPrint('Daily backup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }

    await prefs.setString(_lastAutoBackupDateKey, todayKey);

    final title = source == BackupRunSource.backgroundWorker
        ? 'Daily Backup Completed (Background)'
        : 'Daily Backup Completed';

    await _notifications.show(
      9002,
      title,
      changedItems == 0
          ? 'No data changes today. Latest full snapshot refreshed.'
          : 'Daily backup saved with $changedItems change${changedItems == 1 ? '' : 's'}.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannelId,
          _notificationChannelName,
          channelDescription: _notificationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }

  static tz.TZDateTime _nextInstanceOfNineAm(tz.Location location) {
    final now = tz.TZDateTime.now(location);
    var scheduled = tz.TZDateTime(location, now.year, now.month, now.day, 9);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static Future<int> _createOrUpdateDeltaBackup() async {
    final storage = StorageService();

    final expenses = (await storage.loadExpenses()).map((e) => e.toJson()).toList();
    final categories = (await storage.loadCategories()).map((c) => c.toJson()).toList();
    final budgets = (await storage.loadBudgets()).map((b) => b.toJson()).toList();

    final payload = {
      'app': 'expense_tracker',
      'schemaVersion': _backupSchemaVersion,
      'type': 'full',
      'createdAt': DateTime.now().toIso8601String(),
      'expenses': expenses,
      'categories': categories,
      'budgets': budgets,
    };

    final backupDir = await _resolveBackupDirectory();
    final previous = await _loadLatestFullBackup(backupDir);

    var changedItems = 0;
    if (previous != null) {
      final expenseDelta = _computeCollectionDelta(
        previous['expenses'] as List<dynamic>? ?? const [],
        expenses,
      );
      final categoryDelta = _computeCollectionDelta(
        previous['categories'] as List<dynamic>? ?? const [],
        categories,
      );
      final budgetDelta = _computeCollectionDelta(
        previous['budgets'] as List<dynamic>? ?? const [],
        budgets,
      );

      changedItems =
          expenseDelta.upsert.length +
          expenseDelta.delete.length +
          categoryDelta.upsert.length +
          categoryDelta.delete.length +
          budgetDelta.upsert.length +
          budgetDelta.delete.length;

      if (changedItems > 0) {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final deltaFile = io.File(
          '${backupDir.path}/ExpenseTracker_Auto_Delta_$timestamp.json',
        );
        final deltaPayload = {
          'app': 'expense_tracker',
          'schemaVersion': _backupSchemaVersion,
          'type': 'delta',
          'createdAt': DateTime.now().toIso8601String(),
          'baseCreatedAt': previous['createdAt'],
          'changes': {
            'expenses': {
              'upsert': expenseDelta.upsert,
              'delete': expenseDelta.delete,
            },
            'categories': {
              'upsert': categoryDelta.upsert,
              'delete': categoryDelta.delete,
            },
            'budgets': {
              'upsert': budgetDelta.upsert,
              'delete': budgetDelta.delete,
            },
          },
        };
        await deltaFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(deltaPayload),
        );
      }
    }

    final latestFull = io.File('${backupDir.path}/$_latestFullBackupFileName');
    await latestFull.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

    await _pruneOldDeltaBackups(backupDir);
    return changedItems;
  }

  static Future<io.Directory> _resolveBackupDirectory() async {
    final downloadsPath = await _resolveDownloadsPath();
    final backupDir = io.Directory('$downloadsPath/$_backupDirectoryName');
    await backupDir.create(recursive: true);
    return backupDir;
  }

  static Future<String> _resolveDownloadsPath() async {
    if (io.Platform.isAndroid) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw io.FileSystemException(
          'Could not determine app-scoped external storage directory on Android',
        );
      }
      return externalDir.path;
    }
    final homeDir = io.Platform.environment['HOME'] ?? '';
    if (homeDir.isEmpty) {
      throw 'Could not determine home directory';
    }
    return '$homeDir/Downloads';
  }

  static Future<Map<String, dynamic>?> _loadLatestFullBackup(
    io.Directory backupDir,
  ) async {
    final latestFile = io.File('${backupDir.path}/$_latestFullBackupFileName');
    if (!await latestFile.exists()) return null;

    try {
      final content = await latestFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != 'full') return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static ({List<Map<String, dynamic>> upsert, List<String> delete})
      _computeCollectionDelta(
    List<dynamic> previous,
    List<Map<String, dynamic>> current,
  ) {
    final prevById = <String, Map<String, dynamic>>{};
    for (final row in previous) {
      if (row is Map) {
        final normalized = Map<String, dynamic>.from(row);
        final id = normalized['id'];
        if (id is String && id.isNotEmpty) {
          prevById[id] = normalized;
        }
      }
    }

    final currentById = <String, Map<String, dynamic>>{};
    for (final row in current) {
      final id = row['id'];
      if (id is String && id.isNotEmpty) {
        currentById[id] = row;
      }
    }

    final upsert = <Map<String, dynamic>>[];
    final deleted = <String>[];

    for (final entry in currentById.entries) {
      final previousRow = prevById[entry.key];
      if (previousRow == null || jsonEncode(previousRow) != jsonEncode(entry.value)) {
        upsert.add(entry.value);
      }
    }

    for (final id in prevById.keys) {
      if (!currentById.containsKey(id)) {
        deleted.add(id);
      }
    }

    return (upsert: upsert, delete: deleted);
  }

  static Future<void> _pruneOldDeltaBackups(io.Directory backupDir) async {
    final entities = await backupDir.list().toList();
    final deltaFiles = entities
        .whereType<io.File>()
        .where((file) => file.path.endsWith('.json'))
        .where((file) => file.uri.pathSegments.last.contains('_Delta_'))
        .toList();

    if (deltaFiles.length <= _maxDeltaBackupFiles) return;

    deltaFiles.sort((a, b) => b.path.compareTo(a.path));
    final toDelete = deltaFiles.skip(_maxDeltaBackupFiles);

    for (final file in toDelete) {
      try {
        await file.delete();
      } catch (_) {
        // Retention cleanup is best effort.
      }
    }
  }
}
