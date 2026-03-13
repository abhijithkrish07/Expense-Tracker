import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/expense.dart';
import '../models/category.dart' as cat_model;
import '../models/budget.dart';

// Conditional import: use dart:io File on mobile/desktop, stub on web
import 'storage_service_io.dart'
    if (dart.library.html) 'storage_service_web.dart';

class StorageService {
  static const _expensesKey = 'expenses';
  static const _categoriesKey = 'categories';
  static const _budgetsKey = 'budgets';
  static const _themeModeKey = 'theme_mode';

  static const _legacyMigratedPrefix = 'legacy_migrated_';
  static const _insightsHistoryKey = 'storage_insights_history_v1';
  static const _maxInsightSnapshots = 30;
  static const _trackedDataKeys = <String>[
    _expensesKey,
    _categoriesKey,
    _budgetsKey,
  ];

  // Secure storage for sensitive financial data on native platforms
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<List<Map<String, dynamic>>> _read(String key) async {
    if (kIsWeb) {
      // Web: use SharedPreferences (no secure storage available)
      return readFromPrefs(key);
    } else {
      // Native: encrypted + compressed file storage
      return _readNativeWithMigration(key);
    }
  }

  Future<void> _write(String key, List<Map<String, dynamic>> data) async {
    if (kIsWeb) {
      await writeToPrefs(key, data);
    } else {
      await writeToFile(key, data);
      await _secureStorage.delete(key: key);
    }
  }

  Future<List<Map<String, dynamic>>> _readNativeWithMigration(String key) async {
    final fromFile = await readFromFile(key);
    if (fromFile.isNotEmpty) {
      return fromFile;
    }

    final migrationMarker = await _secureStorage.read(
      key: '$_legacyMigratedPrefix$key',
    );
    if (migrationMarker == '1') {
      return fromFile;
    }

    final migrated = await _readSecure(key);
    await writeToFile(key, migrated);
    await _secureStorage.write(key: '$_legacyMigratedPrefix$key', value: '1');
    await _secureStorage.delete(key: key);
    return migrated;
  }

  Future<List<Map<String, dynamic>>> _readSecure(String key) async {
    try {
      final json = await _secureStorage.read(key: key);
      if (json == null || json.isEmpty) return [];
      return List<Map<String, dynamic>>.from(jsonDecode(json) as List);
    } catch (_) {
      return [];
    }
  }

  Future<List<Expense>> loadExpenses() async {
    final list = await _read(_expensesKey);
    return list.map(Expense.fromJson).toList();
  }

  Future<void> saveExpenses(List<Expense> expenses) async {
    await _write(_expensesKey, expenses.map((e) => e.toJson()).toList());
  }

  Future<List<cat_model.Category>> loadCategories() async {
    final list = await _read(_categoriesKey);
    return list.map(cat_model.Category.fromJson).toList();
  }

  Future<void> saveCategories(List<cat_model.Category> categories) async {
    await _write(_categoriesKey, categories.map((c) => c.toJson()).toList());
  }

  Future<List<Budget>> loadBudgets() async {
    final list = await _read(_budgetsKey);
    return list.map(Budget.fromJson).toList();
  }

  Future<void> saveBudgets(List<Budget> budgets) async {
    await _write(_budgetsKey, budgets.map((b) => b.toJson()).toList());
  }

  Future<String?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey);
  }

  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode);
  }

  Future<StorageInsights> loadStorageInsights() async {
    final buckets = <StorageBucketInsight>[];

    for (final key in _trackedDataKeys) {
      final data = await _read(key);
      final rawBytes = utf8.encode(jsonEncode(data)).length;
      final persistedBytes = await readStoredBytesForKey(key);

      buckets.add(
        StorageBucketInsight(
          key: key,
          label: _displayLabelForKey(key),
          rawBytes: rawBytes,
          persistedBytes: persistedBytes,
        ),
      );
    }

    return StorageInsights(buckets: buckets);
  }

  Future<StorageInsightsWithHistory> loadStorageInsightsWithHistory() async {
    final current = await loadStorageInsights();
    final previous = await _loadInsightHistory();
    final now = DateTime.now();

    final updated = List<StorageInsightSnapshot>.from(previous);
    if (updated.isEmpty) {
      updated.add(
        StorageInsightSnapshot(
          measuredAt: now,
          rawBytes: current.totalRawBytes,
          persistedBytes: current.totalPersistedBytes,
        ),
      );
    } else {
      final last = updated.last;
      final hasSameMetrics =
          last.rawBytes == current.totalRawBytes &&
          last.persistedBytes == current.totalPersistedBytes;

      if (_isSameDay(last.measuredAt, now)) {
        if (!hasSameMetrics) {
          updated[updated.length - 1] = StorageInsightSnapshot(
            measuredAt: now,
            rawBytes: current.totalRawBytes,
            persistedBytes: current.totalPersistedBytes,
          );
        }
      } else {
        updated.add(
          StorageInsightSnapshot(
            measuredAt: now,
            rawBytes: current.totalRawBytes,
            persistedBytes: current.totalPersistedBytes,
          ),
        );
      }
    }

    final trimmed = updated.length > _maxInsightSnapshots
        ? updated.sublist(updated.length - _maxInsightSnapshots)
        : updated;
    await _saveInsightHistory(trimmed);

    return StorageInsightsWithHistory(current: current, history: trimmed);
  }

  Future<List<StorageInsightSnapshot>> _loadInsightHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_insightsHistoryKey);
    if (json == null || json.isEmpty) return const [];

    try {
      final list = List<Map<String, dynamic>>.from(jsonDecode(json) as List);
      return list
          .map(StorageInsightSnapshot.fromJson)
          .where((item) => item != null)
          .cast<StorageInsightSnapshot>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveInsightHistory(List<StorageInsightSnapshot> history) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(history.map((e) => e.toJson()).toList());
    await prefs.setString(_insightsHistoryKey, encoded);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _displayLabelForKey(String key) {
    switch (key) {
      case _expensesKey:
        return 'Expenses';
      case _categoriesKey:
        return 'Categories';
      case _budgetsKey:
        return 'Budgets';
      default:
        return key;
    }
  }
}

class StorageBucketInsight {
  final String key;
  final String label;
  final int rawBytes;
  final int persistedBytes;

  const StorageBucketInsight({
    required this.key,
    required this.label,
    required this.rawBytes,
    required this.persistedBytes,
  });

  int get differenceBytes => rawBytes - persistedBytes;

  double get reductionPercent {
    if (rawBytes <= 0) return 0;
    return ((rawBytes - persistedBytes) / rawBytes) * 100;
  }
}

class StorageInsights {
  final List<StorageBucketInsight> buckets;

  const StorageInsights({required this.buckets});

  int get totalRawBytes => buckets.fold(0, (sum, b) => sum + b.rawBytes);

  int get totalPersistedBytes =>
      buckets.fold(0, (sum, b) => sum + b.persistedBytes);

  int get totalDifferenceBytes => totalRawBytes - totalPersistedBytes;

  double get totalReductionPercent {
    if (totalRawBytes <= 0) return 0;
    return ((totalRawBytes - totalPersistedBytes) / totalRawBytes) * 100;
  }
}

class StorageInsightSnapshot {
  final DateTime measuredAt;
  final int rawBytes;
  final int persistedBytes;

  const StorageInsightSnapshot({
    required this.measuredAt,
    required this.rawBytes,
    required this.persistedBytes,
  });

  int get savedBytes => rawBytes - persistedBytes;

  Map<String, dynamic> toJson() {
    return {
      'at': measuredAt.toIso8601String(),
      'raw': rawBytes,
      'stored': persistedBytes,
    };
  }

  static StorageInsightSnapshot? fromJson(Map<String, dynamic> json) {
    final atRaw = json['at'];
    final raw = json['raw'];
    final stored = json['stored'];

    if (atRaw is! String || raw is! int || stored is! int) {
      return null;
    }

    final parsed = DateTime.tryParse(atRaw);
    if (parsed == null) return null;

    return StorageInsightSnapshot(
      measuredAt: parsed,
      rawBytes: raw,
      persistedBytes: stored,
    );
  }
}

class StorageInsightsWithHistory {
  final StorageInsights current;
  final List<StorageInsightSnapshot> history;

  const StorageInsightsWithHistory({
    required this.current,
    required this.history,
  });
}

// Shared prefs implementation (web + fallback)
Future<List<Map<String, dynamic>>> readFromPrefs(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(key);
    if (json == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(json) as List);
  } catch (_) {
    return [];
  }
}

Future<void> writeToPrefs(String key, List<Map<String, dynamic>> data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, jsonEncode(data));
}

Future<int> readStoredBytesForKey(String key) async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(key);
    if (json == null) return 0;
    return utf8.encode(json).length;
  }

  return readFileBytesForKey(key);
}
