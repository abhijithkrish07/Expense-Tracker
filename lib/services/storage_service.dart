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
      // Native: use encrypted secure storage for financial data
      return _readSecure(key);
    }
  }

  Future<void> _write(String key, List<Map<String, dynamic>> data) async {
    if (kIsWeb) {
      await writeToPrefs(key, data);
    } else {
      await _writeSecure(key, data);
    }
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

  Future<void> _writeSecure(String key, List<Map<String, dynamic>> data) async {
    await _secureStorage.write(key: key, value: jsonEncode(data));
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
