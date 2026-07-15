import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:uuid/uuid.dart';
import '../../models/expense.dart';
import '../../models/category.dart';
import '../../models/budget.dart';
import '../../providers/expense_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/backup_utils.dart' as backup_utils;
import '../../widgets/empty_state_widget.dart';
import '../analytics/analytics_screen.dart';
import '../expense/add_edit_expense_screen.dart';
import 'widgets/home_app_drawer.dart';
import 'widgets/home_expense_list.dart';
import 'widgets/home_fab.dart';
import 'widgets/home_summary_widgets.dart';

class _PendingImportExpense {
  final String categoryName;
  final double amount;
  final DateTime expenseDate;
  final String sheetName;

  const _PendingImportExpense({
    required this.categoryName,
    required this.amount,
    required this.expenseDate,
    required this.sheetName,
  });
}

class _AppBackupPayload {
  final DateTime createdAt;
  final int schemaVersion;
  final String type;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> budgets;

  const _AppBackupPayload({
    required this.createdAt,
    required this.schemaVersion,
    this.type = 'full',
    required this.expenses,
    required this.categories,
    required this.budgets,
  });

  Map<String, dynamic> toJson() {
    return {
      'app': 'expense_tracker',
      'schemaVersion': schemaVersion,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
      'expenses': expenses,
      'categories': categories,
      'budgets': budgets,
    };
  }

  static _AppBackupPayload? tryParse(Map<String, dynamic> json) {
    final rawVersion = json['schemaVersion'];
    final rawType = json['type'];
    final rawCreatedAt = json['createdAt'];
    final rawExpenses = json['expenses'];
    final rawCategories = json['categories'];
    final rawBudgets = json['budgets'];

    if (rawVersion is! int || rawCreatedAt is! String) {
      return null;
    }

    if (rawType != null && rawType != 'full') return null;

    if (rawExpenses is! List || rawCategories is! List || rawBudgets is! List) {
      return null;
    }

    final createdAt = DateTime.tryParse(rawCreatedAt);
    if (createdAt == null) return null;

    List<Map<String, dynamic>> asMapList(List<dynamic> input) {
      return input
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return _AppBackupPayload(
      createdAt: createdAt,
      schemaVersion: rawVersion,
      type: 'full',
      expenses: asMapList(rawExpenses),
      categories: asMapList(rawCategories),
      budgets: asMapList(rawBudgets),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _uuid = Uuid();
  static const _backupSchemaVersion = 1;
  static const _latestFullBackupFileName = 'ExpenseTracker_Backup_Latest.json';
  static const _maxDeltaBackupFiles = 24;

  static String _humanCount(int value, String noun) {
    return '$value $noun${value == 1 ? '' : 's'}';
  }

  static _AppBackupPayload _buildBackupPayload(WidgetRef ref) {
    final expenses = ref.read(expenseProvider).valueOrNull ?? <Expense>[];
    final categories = ref.read(categoryProvider).valueOrNull ?? <Category>[];
    final budgets = ref.read(budgetProvider).valueOrNull ?? <Budget>[];

    return _AppBackupPayload(
      createdAt: DateTime.now(),
      schemaVersion: _backupSchemaVersion,
      expenses: expenses.map((e) => e.toJson()).toList(),
      categories: categories.map((c) => c.toJson()).toList(),
      budgets: budgets.map((b) => b.toJson()).toList(),
    );
  }

  static String _sanitizeFileLabel(String input) {
    return input.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  static Future<_AppBackupPayload?> _loadLatestFullBackup(
    io.Directory backupDir,
  ) async {
    final latestFile = io.File('${backupDir.path}/$_latestFullBackupFileName');
    try {
      final content = await backup_utils.readEncryptedBackup(latestFile);
      if (content == null) return null;
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      return _AppBackupPayload.tryParse(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _pruneOldDeltaBackups(io.Directory backupDir) async {
    final all = await backupDir.list().toList();
    final deltaFiles = all
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
        // Keep going; retention is best effort.
      }
    }
  }

  static Future<io.File> _writeBackupFile({
    required _AppBackupPayload payload,
    required String filePrefix,
  }) async {
    final backupDir = await backup_utils.resolveBackupDirectory();

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final safePrefix = _sanitizeFileLabel(filePrefix);
    final fileName = '${safePrefix}_$timestamp.json';
    final filePath = '${backupDir.path}/$fileName';
    final file = io.File(filePath);

    final encoded = const JsonEncoder.withIndent('  ').convert(payload.toJson());
    await backup_utils.writeEncryptedBackup(file, encoded);

    return file;
  }

  static Future<void> _createRecoveryBackup(
    BuildContext context,
    WidgetRef ref, {
    bool showFeedback = true,
    String filePrefix = 'ExpenseTracker_Backup',
  }) async {
    final payload = _buildBackupPayload(ref);
    final backupDir = await backup_utils.resolveBackupDirectory();
    final previous = await _loadLatestFullBackup(backupDir);

    io.File? deltaFile;
    var changedItems = 0;
    if (previous != null) {
      final expenseDelta = backup_utils.computeCollectionDelta(previous.expenses, payload.expenses);
      final categoryDelta = backup_utils.computeCollectionDelta(previous.categories, payload.categories);
      final budgetDelta = backup_utils.computeCollectionDelta(previous.budgets, payload.budgets);

      changedItems =
          expenseDelta.upsert.length +
          expenseDelta.delete.length +
          categoryDelta.upsert.length +
          categoryDelta.delete.length +
          budgetDelta.upsert.length +
          budgetDelta.delete.length;

      if (changedItems > 0) {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final safePrefix = _sanitizeFileLabel(filePrefix);
        deltaFile = io.File(
          '${backupDir.path}/${safePrefix}_Delta_$timestamp.json',
        );
        final deltaPayload = {
          'app': 'expense_tracker',
          'schemaVersion': _backupSchemaVersion,
          'type': 'delta',
          'createdAt': DateTime.now().toIso8601String(),
          'baseCreatedAt': previous.createdAt.toIso8601String(),
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
        final encodedDelta = const JsonEncoder.withIndent('  ').convert(deltaPayload);
        await backup_utils.writeEncryptedBackup(deltaFile, encodedDelta);
      }
    }

    final latestFullFile = io.File(
      '${backupDir.path}/$_latestFullBackupFileName',
    );
    final encodedFull = const JsonEncoder.withIndent('  ').convert(payload.toJson());
    await backup_utils.writeEncryptedBackup(latestFullFile, encodedFull);
    await _pruneOldDeltaBackups(backupDir);

    io.File? fullArchiveFile;
    if (previous == null) {
      fullArchiveFile = await _writeBackupFile(
        payload: payload,
        filePrefix: '${filePrefix}_Full',
      );
    }

    if (!showFeedback || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          previous == null
              ? 'Full backup created: ${fullArchiveFile?.uri.pathSegments.last ?? _latestFullBackupFileName}.'
              : changedItems == 0
                  ? 'No data changes since last backup. Latest full snapshot refreshed.'
                  : 'Delta backup saved: ${deltaFile?.uri.pathSegments.last ?? 'delta file'}. '
                      'Updated $changedItems item${changedItems == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  static Future<void> _restoreFromBackup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Wait for the drawer close animation before showing any overlay.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!context.mounted) return;

    if (!kIsWeb) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Find Your Backup File'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your backup files are saved in:'),
              SizedBox(height: 8),
              Text(
                'Downloads/ExpenseTracker_Backups/',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('Select this file to restore:'),
              SizedBox(height: 8),
              Text(
                'ExpenseTracker_Backup_Latest.json',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Note: Delta backup files (ending in _Delta_…) cannot be used for restore.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Choose File'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!context.mounted) return;
    }

    // Capture current counts before the async file picker gap.
    final currentExpenseCount = ref.read(expenseProvider).valueOrNull?.length ?? 0;
    final currentCategoryCount = ref.read(categoryProvider).valueOrNull?.length ?? 0;
    final currentBudgetCount = ref.read(budgetProvider).valueOrNull?.length ?? 0;
    final storage = ref.read(storageServiceProvider);

    final picked = await FilePicker.platform.pickFiles(
      type: kIsWeb ? FileType.any : FileType.custom,
      allowedExtensions: kIsWeb ? null : ['json'],
      withData: true,
    );
    if (picked == null) return;

    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read selected backup file.')),
      );
      return;
    }

    _AppBackupPayload? payload;
    List<Expense> expenses;
    List<Category> categories;
    List<Budget> budgets;

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid backup structure');
      }

      if (decoded['type'] == 'delta') {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Delta backup selected. Choose ExpenseTracker_Backup_Latest.json to restore.',
            ),
          ),
        );
        return;
      }

      payload = _AppBackupPayload.tryParse(decoded);
      if (payload == null) {
        throw const FormatException('Invalid backup payload');
      }

      expenses = payload.expenses.map(Expense.fromJson).toList();
      categories = payload.categories.map(Category.fromJson).toList();
      budgets = payload.budgets.map(Budget.fromJson).toList();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid backup file.')),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Backup'),
        content: Text(
          'This will replace your current local data.\n\n'
          'Current: ${_humanCount(currentExpenseCount, 'expense')}, '
          '${_humanCount(currentCategoryCount, 'category')}, '
          '${_humanCount(currentBudgetCount, 'budget')}\n'
          'Backup: ${_humanCount(expenses.length, 'expense')}, '
          '${_humanCount(categories.length, 'category')}, '
          '${_humanCount(budgets.length, 'budget')}\n\n'
          'Backup date: ${DateFormat('dd MMM yyyy, HH:mm').format(payload!.createdAt)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await storage.saveCategories(categories);
    await storage.saveBudgets(budgets);
    await storage.saveExpenses(expenses);

    ref.read(categoryProvider.notifier).restoreFrom(categories);
    ref.read(budgetProvider.notifier).restoreFrom(budgets);
    ref.read(expenseProvider.notifier).restoreFrom(expenses);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup restored successfully.')),
    );
  }

  Future<bool> _showImportFormatGuide(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excel Import Format'),
        content: const Text(
          'Expected columns (2):\n'
          '1) Category\n'
          '2) Expense\n\n'
          'Example:\n'
          'Food | 250\n'
          'Transport | 80\n'
          'Shopping | 1200\n'
          'Food | 200+15+30 (imports as 3 separate expenses)\n'
          'Total Expenses | 1530\n\n'
          'Import will stop before the row where Category is "Total Expenses".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Choose File'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _importExpensesFromExcel(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Avoid opening dialogs while the drawer close animation is in progress.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!context.mounted) return;

    final shouldPickFile = await _showImportFormatGuide(context);
    if (!shouldPickFile) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null) return;

    final Uint8List? bytes = picked.files.single.bytes;
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read selected file.')),
        );
      }
      return;
    }

    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No sheets found in Excel file.')),
        );
      }
      return;
    }

    final categoryNotifier = ref.read(categoryProvider.notifier);
    final expenseNotifier = ref.read(expenseProvider.notifier);
    final categories = ref.read(categoryProvider).valueOrNull ?? <Category>[];
    final categoryByName = <String, Category>{
      for (final c in categories) c.name.trim().toLowerCase(): c,
    };

    final pendingImports = <_PendingImportExpense>[];
    var skipped = 0;
    var stopMarkerReachedCount = 0;
    var validSheetCount = 0;
    var skippedSheetCount = 0;

    for (final entry in excel.tables.entries) {
      final sheetName = entry.key;
      final sheet = entry.value;

      final monthDate = _inferMonthDateFromSheetName(sheetName);
      if (monthDate == null) {
        skippedSheetCount++;
        continue;
      }

      validSheetCount++;
      var stopReachedInThisSheet = false;

      for (final row in sheet.rows) {
        if (row.length < 2) {
          skipped++;
          continue;
        }

        final categoryName = _cellAsText(row[0]);
        if (categoryName == null || categoryName.isEmpty) {
          skipped++;
          continue;
        }

        if (categoryName.toLowerCase() == 'total expenses') {
          stopReachedInThisSheet = true;
          break;
        }

        final amounts = _cellAsAmounts(row[1]);
        if (amounts == null || amounts.isEmpty) {
          skipped++;
          continue;
        }

        for (final amount in amounts) {
          if (amount <= 0) {
            skipped++;
            continue;
          }

          pendingImports.add(
            _PendingImportExpense(
              categoryName: categoryName,
              amount: amount,
              expenseDate: monthDate,
              sheetName: sheetName,
            ),
          );
        }
      }

      if (stopReachedInThisSheet) {
        stopMarkerReachedCount++;
      }
    }

    final categoriesToCreate = pendingImports
        .map((e) => e.categoryName.trim().toLowerCase())
        .where((name) => !categoryByName.containsKey(name))
        .toSet()
        .length;

    if (!context.mounted) return;

    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Preview'),
        content: Text(
          'Rows to import: ${pendingImports.length}\n'
          'Rows skipped: $skipped\n'
          'Sheets recognized: $validSheetCount\n'
          'Sheets skipped (name not recognized): $skippedSheetCount\n'
          'New categories to create: $categoriesToCreate\n'
          'Sheets with stop marker: $stopMarkerReachedCount\n\n'
          'Continue importing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (shouldImport != true) return;

    final expensesToImport = <Expense>[];

    for (final pending in pendingImports) {
      final key = pending.categoryName.toLowerCase();
      var category = categoryByName[key];
      if (category == null) {
        category = await categoryNotifier.addCategory(
          name: pending.categoryName,
          colorHex: '#9E9E9E',
          iconName: 'more_horiz',
        );
        categoryByName[key] = category;
      }

      expensesToImport.add(
        Expense(
          id: _uuid.v4(),
          title: category.name,
          amount: pending.amount,
          date: pending.expenseDate,
          categoryId: category.id,
          note: 'Imported from Excel (${pending.sheetName})',
        ),
      );
    }

    await expenseNotifier.addExpensesBulk(expensesToImport);

    final imported = expensesToImport.length;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported > 0
                ? 'Imported $imported expense${imported == 1 ? '' : 's'} from Excel${skipped > 0 ? ' ($skipped skipped)' : ''}.'
                : 'No valid expenses found to import.',
          ),
        ),
      );
    }
  }

  String? _cellAsText(dynamic cell) {
    final value = _rawCellValue(cell);
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<double>? _cellAsAmounts(dynamic cell) {
    final value = _rawCellValue(cell);
    if (value == null) return null;
    if (value is num) return [value.toDouble()];

    var raw = value.toString().trim();
    if (raw.isEmpty) return null;

    // Handle Excel-style formulas entered as plain text, e.g. "=202+13".
    if (raw.startsWith('=')) {
      raw = raw.substring(1);
    }

    // For inputs like "200+15+30", create separate imported expense entries.
    if (raw.contains('+')) {
      final parts = raw
          .split('+')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();

      if (parts.isEmpty) return null;

      final parsed = <double>[];
      for (final part in parts) {
        final amount = _parseSingleAmount(part);
        if (amount == null) return null;
        parsed.add(amount);
      }

      return parsed;
    }

    final singleAmount = _parseSingleAmount(raw);
    if (singleAmount == null) return null;
    return [singleAmount];
  }

  double? _parseSingleAmount(String raw) {
    if (raw.isEmpty) return null;

    final hasArithmeticOperator = RegExp(r'[+\-*/]').hasMatch(raw);
    if (hasArithmeticOperator) {
      final evaluated = _evaluateSimpleExpression(raw);
      if (evaluated != null) return evaluated;
      return null;
    }

    // Fast path for plain numeric values with optional commas/currency symbols.
    final normalizedNumeric = raw
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.\-]'), '');
    final directNumber = double.tryParse(normalizedNumeric);
    if (directNumber != null) return directNumber;

    return null;
  }

  double? _evaluateSimpleExpression(String input) {
    var expression = input.replaceAll(' ', '').replaceAll(',', '');
    expression = expression.replaceAll(RegExp(r'[^0-9.+\-*/]'), '');
    if (expression.isEmpty) return null;

    // Make a leading negative number parseable as binary operation.
    if (expression.startsWith('-')) {
      expression = '0$expression';
    }

    final tokenMatches = RegExp(
      r'(\d+(?:\.\d+)?)|[+\-*/]',
    ).allMatches(expression).map((m) => m.group(0)!).toList();

    if (tokenMatches.isEmpty || tokenMatches.join() != expression) return null;
    if (tokenMatches.first.length == 1 && '+-*/'.contains(tokenMatches.first)) {
      return null;
    }

    final firstNumber = double.tryParse(tokenMatches.first);
    if (firstNumber == null) return null;

    final values = <double>[];
    final addSubOps = <String>[];
    var current = firstNumber;

    var i = 1;
    while (i + 1 < tokenMatches.length) {
      final op = tokenMatches[i];
      final next = double.tryParse(tokenMatches[i + 1]);
      if (next == null) return null;

      if (op == '*') {
        current *= next;
      } else if (op == '/') {
        if (next == 0) return null;
        current /= next;
      } else if (op == '+' || op == '-') {
        values.add(current);
        addSubOps.add(op);
        current = next;
      } else {
        return null;
      }

      i += 2;
    }

    if (i != tokenMatches.length) return null;

    values.add(current);
    var result = values.first;
    for (var j = 0; j < addSubOps.length; j++) {
      result = addSubOps[j] == '+'
          ? result + values[j + 1]
          : result - values[j + 1];
    }

    return result;
  }

  DateTime? _inferMonthDateFromSheetName(String sheetName) {
    var normalized = sheetName.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    normalized = normalized
        .replaceAll(RegExp(r"[^A-Z0-9]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const monthMap = <String, int>{
      'JAN': 1,
      'JANUARY': 1,
      'FEB': 2,
      'FEBRUARY': 2,
      'MAR': 3,
      'MARCH': 3,
      'APR': 4,
      'APRIL': 4,
      'MAY': 5,
      'JUN': 6,
      'JUNE': 6,
      'JUL': 7,
      'JULY': 7,
      'AUG': 8,
      'AUGUST': 8,
      'SEP': 9,
      'SEPT': 9,
      'SEPTEMBER': 9,
      'OCT': 10,
      'OCTOBER': 10,
      'NOV': 11,
      'NOVEMBER': 11,
      'DEC': 12,
      'DECEMBER': 12,
    };

    int? month;
    for (final entry in monthMap.entries) {
      if (normalized.contains(entry.key)) {
        month = entry.value;
        break;
      }
    }
    if (month == null) return null;

    final yearMatches = RegExp(
      r'\d{2,4}',
    ).allMatches(normalized).map((m) => m.group(0)!).toList();
    if (yearMatches.isEmpty) return null;

    final rawYear = yearMatches.last;
    final parsed = int.tryParse(rawYear);
    if (parsed == null) return null;

    final year = rawYear.length == 2 ? (2000 + parsed) : parsed;
    if (year < 2000 || year > 2100) return null;

    return DateTime(year, month, 1);
  }

  dynamic _rawCellValue(dynamic cell) {
    try {
      return cell?.value;
    } catch (_) {
      return cell;
    }
  }

  Future<void> _openAddExpense(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEditExpenseScreen()),
    );
  }

  Future<void> _deleteMonthlyExpenses(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedMonth,
  ) async {
    final allExpenses = ref.read(expenseProvider).valueOrNull ?? <Expense>[];
    final monthExpenses = allExpenses
        .where(
          (e) =>
              e.date.year == selectedMonth.year &&
              e.date.month == selectedMonth.month,
        )
        .toList();

    if (monthExpenses.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No expenses found for this month.')),
        );
      }
      return;
    }

    final monthLabel = DateFormat('MMMM yyyy').format(selectedMonth);
    final count = monthExpenses.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Monthly Delete'),
        content: Text(
          'Please confirm: delete all $count expense${count == 1 ? '' : 's'} for $monthLabel. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await HomeScreen._createRecoveryBackup(
        context,
        ref,
        showFeedback: false,
        filePrefix: 'ExpenseTracker_AutoBackup_BeforeMonthlyDelete',
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not create auto-backup before delete. Continuing anyway.',
            ),
          ),
        );
      }
    }

    final deleted = await ref
        .read(expenseProvider.notifier)
        .deleteExpensesForMonth(selectedMonth.year, selectedMonth.month);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted > 0
                ? 'Deleted $deleted expense${deleted == 1 ? '' : 's'} for $monthLabel.'
                : 'No expenses were deleted.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteAllYearsExpenses(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final allExpenses = ref.read(expenseProvider).valueOrNull ?? <Expense>[];
    if (allExpenses.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No expenses found to delete.')),
        );
      }
      return;
    }

    final count = allExpenses.length;
    var typedValue = '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final canDelete = typedValue.trim().toLowerCase() == 'confirm';
          return AlertDialog(
            title: const Text('Delete All Years Expenses'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This will permanently delete all $count expenses across all years.',
                  ),
                  const SizedBox(height: 12),
                  const Text('Type "confirm" to continue:'),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    onChanged: (value) => setDialogState(() {
                      typedValue = value;
                    }),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'confirm',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Delete All'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await HomeScreen._createRecoveryBackup(
        context,
        ref,
        showFeedback: false,
        filePrefix: 'ExpenseTracker_AutoBackup_BeforeDeleteAll',
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not create auto-backup before delete. Continuing anyway.',
            ),
          ),
        );
      }
    }

    final deleted = await ref
        .read(expenseProvider.notifier)
        .deleteAllExpenses();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted > 0
                ? 'Deleted $deleted expense${deleted == 1 ? '' : 's'} across all years.'
                : 'No expenses were deleted.',
          ),
        ),
      );
    }
  }

  Future<void> _exportExpensesToExcel(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final allExpenses = ref.read(expenseProvider).valueOrNull ?? <Expense>[];
    if (allExpenses.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No expenses to export.')));
      }
      return;
    }

    final categories = ref.read(categoryProvider).valueOrNull ?? <Category>[];
    final categoryById = <String, Category>{
      for (final c in categories) c.id: c,
    };

    // Group expenses by year-month
    final Map<DateTime, List<Expense>> monthGroups = {};
    for (final expense in allExpenses) {
      final monthKey = DateTime(expense.date.year, expense.date.month);
      monthGroups.putIfAbsent(monthKey, () => []).add(expense);
    }

    // Sort months in ascending order
    final sortedMonths = monthGroups.keys.toList()..sort();

    // Create Excel workbook
    final excel = Excel.createExcel();
    excel.delete('Sheet1'); // Remove default sheet

    // Create a sheet for each month
    for (final monthKey in sortedMonths) {
      final expenses = monthGroups[monthKey]!;
      final monthLabel = DateFormat('MMM yyyy').format(monthKey).toUpperCase();
      final sheet = excel[monthLabel];

      // Group expenses by category within the month
      final Map<String, List<Expense>> categoryGroups = {};
      for (final expense in expenses) {
        final category = categoryById[expense.categoryId];
        final categoryName = category?.name ?? 'Uncategorized';
        categoryGroups.putIfAbsent(categoryName, () => []).add(expense);
      }

      final sortedCategories = categoryGroups.keys.toList()..sort();

      // Add headers
      const headers = ['Category', 'Date', 'Expense', 'Amount'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          ..value = TextCellValue(headers[i])
          ..cellStyle = CellStyle(bold: true);
      }

      // Add expense rows grouped by category
      var rowIndex = 1;
      for (final categoryName in sortedCategories) {
        final categoryExpenses = categoryGroups[categoryName]!
          ..sort((a, b) => b.date.compareTo(a.date)); // Sort by date descending

        double categoryTotal = 0;

        for (final expense in categoryExpenses) {
          final row = [
            TextCellValue(categoryName),
            TextCellValue(DateFormat('dd MMM yyyy').format(expense.date)),
            TextCellValue(expense.title),
            DoubleCellValue(expense.amount),
          ];
          sheet.appendRow(row);
          rowIndex++;
          categoryTotal += expense.amount;
        }

        // Add category subtotal row
        final subtotalRow = [
          TextCellValue('$categoryName - Subtotal'),
          TextCellValue(''),
          TextCellValue(''),
          DoubleCellValue(categoryTotal),
        ];
        sheet.appendRow(subtotalRow);
        final subtotalRowIndex = rowIndex;
        for (int i = 0; i < 4; i++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: subtotalRowIndex));
          cell.cellStyle = CellStyle(bold: true);
        }
        rowIndex++;
      }

      // Add total row
      final monthTotal = expenses.fold(0.0, (sum, e) => sum + e.amount);
      final totalRow = [
        TextCellValue('TOTAL FOR $monthLabel'),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(monthTotal),
      ];
      sheet.appendRow(totalRow);
      final totalRowIndex = rowIndex;
      for (int i = 0; i < 4; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: totalRowIndex));
        cell.cellStyle = CellStyle(bold: true);
      }

      // Auto-fit columns
      sheet.setColumnWidth(0, 20);
      sheet.setColumnWidth(1, 15);
      sheet.setColumnWidth(2, 25);
      sheet.setColumnWidth(3, 12);
    }

    // Save the file
    try {
      final downloadsPath = await backup_utils.resolveDownloadsPath();
      final downloadsDir = io.Directory(downloadsPath);
      await downloadsDir.create(recursive: true);

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'ExpenseTracker_Export_$timestamp.xlsx';
      final filePath = '$downloadsPath/$fileName';

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final file = io.File(filePath);
        await file.writeAsBytes(fileBytes);

        if (context.mounted) {
          final openFile = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text(
                'File saved to:\n$fileName\n\nWould you like to open it now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open'),
                ),
              ],
            ),
          );

          if (openFile == true && context.mounted) {
            try {
              final exportedFile = io.File(filePath);
              final exists = await exportedFile.exists();
              if (!context.mounted) return;
              if (exists) {
                await OpenFile.open(filePath, type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File not found. Please check your Downloads folder.')),
                );
              }
            } catch (e) {
              debugPrint('Could not open exported file: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open the file.')),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Export failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export failed. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(homeMonthProvider);
    final expensesAsync = ref.watch(expenseProvider);
    final categoriesAsync = ref.watch(categoryProvider);
    final budgetsAsync = ref.watch(budgetProvider);
    final monthExpenseCount =
        expensesAsync.valueOrNull
            ?.where(
              (e) =>
                  e.date.year == selectedMonth.year &&
                  e.date.month == selectedMonth.month,
            )
            .length ??
        0;
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.light;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          IconButton(
            tooltip: themeMode == ThemeMode.dark
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: () =>
                ref.read(themeModeProvider.notifier).toggleLightDark(),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
            ),
          ),
        ],
      ),
      drawer: HomeAppDrawer(
        onCreateBackup: () => _createRecoveryBackup(context, ref),
        onRestoreBackup: () => _restoreFromBackup(context, ref),
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allExpenses) {
          final categories = categoriesAsync.valueOrNull ?? [];
          final budgets = budgetsAsync.valueOrNull ?? [];

          // Filter expenses for selected month
          final monthExpenses =
              allExpenses
                  .where(
                    (e) =>
                        e.date.year == selectedMonth.year &&
                        e.date.month == selectedMonth.month,
                  )
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date));

          final totalSpent = monthExpenses.fold(
            0.0,
            (sum, e) => sum + e.amount,
          );
          final budget = budgets
              .where(
                (b) =>
                    b.year == selectedMonth.year &&
                    b.month == selectedMonth.month &&
                    b.categoryId == null,
              )
              .firstOrNull;

          return Column(
            children: [
              HomeMonthSelector(
                selectedMonth: selectedMonth,
                onPrevious: () => ref.read(homeMonthProvider.notifier).state =
                    DateTime(selectedMonth.year, selectedMonth.month - 1),
                onNext: () {
                  final next = DateTime(selectedMonth.year, selectedMonth.month + 1);
                  if (!next.isAfter(DateTime.now())) {
                    ref.read(homeMonthProvider.notifier).state = next;
                  }
                },
              ),
              HomeBudgetCard(totalSpent: totalSpent, budget: budget?.limitAmount),
              Expanded(
                child: monthExpenses.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.receipt_long,
                        title: 'No expenses yet',
                        subtitle: 'Tap + to add your first expense',
                      )
                    : HomeExpenseList(
                        expenses: monthExpenses,
                        categories: categories,
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: ExpandableHomeFab(
        onAddExpense: () => _openAddExpense(context),
        onImportExpenses: () => _importExpensesFromExcel(context, ref),
        onExportExpenses: () => _exportExpensesToExcel(context, ref),
        onDeleteMonthlyExpenses: () =>
            _deleteMonthlyExpenses(context, ref, selectedMonth),
        onDeleteAllYearsExpenses: () => _deleteAllYearsExpenses(context, ref),
        canDeleteMonthlyExpenses: monthExpenseCount > 0,
        canDeleteAllYearsExpenses:
            (expensesAsync.valueOrNull ?? const []).isNotEmpty,
      ),
    );
  }
}

