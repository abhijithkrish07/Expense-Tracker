import 'dart:io' as io;
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:uuid/uuid.dart';
import '../../models/expense.dart';
import '../../models/category.dart';
import '../../providers/expense_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_helpers.dart';
import '../../utils/category_icons.dart';
import '../../widgets/empty_state_widget.dart';
import '../expense/add_edit_expense_screen.dart';
import '../analytics/analytics_screen.dart';
import '../categories/categories_screen.dart';
import '../budget/budget_settings_screen.dart';
import 'storage_insights_screen.dart';

// Selected month for home screen
final homeMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _uuid = Uuid();

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

        final amount = _cellAsAmount(row[1]);
        if (amount == null || amount <= 0) {
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

  double? _cellAsAmount(dynamic cell) {
    final value = _rawCellValue(cell);
    if (value == null) return null;
    if (value is num) return value.toDouble();

    var raw = value.toString().trim();
    if (raw.isEmpty) return null;

    // Handle Excel-style formulas entered as plain text, e.g. "=202+13".
    if (raw.startsWith('=')) {
      raw = raw.substring(1);
    }

    final hasArithmeticOperator = RegExp(r'[+\-*/]').hasMatch(raw);
    if (hasArithmeticOperator) {
      // Strict expression path: never fall back to digit-stripping for values like
      // "20+13", otherwise operators are removed and become "2013".
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

    final monthMap = <String, int>{
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
      // Get Downloads directory based on platform
      final String downloadsPath;
      if (io.Platform.isAndroid) {
        downloadsPath = '/storage/emulated/0/Download';
      } else {
        final homeDir = io.Platform.environment['HOME'] ?? '';
        if (homeDir.isEmpty) {
          throw 'Could not determine home directory';
        }
        downloadsPath = '$homeDir/Downloads';
      }
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
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open file: $e')),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
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
      drawer: const _AppDrawer(),
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
              // Month selector
              _MonthSelector(selectedMonth: selectedMonth),
              // Budget card
              _BudgetCard(totalSpent: totalSpent, budget: budget?.limitAmount),
              // Expense list
              Expanded(
                child: monthExpenses.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.receipt_long,
                        title: 'No expenses yet',
                        subtitle: 'Tap + to add your first expense',
                      )
                    : _ExpenseList(
                        expenses: monthExpenses,
                        categories: categories,
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _ExpandableHomeFab(
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

class _ExpandableHomeFab extends StatefulWidget {
  final Future<void> Function() onAddExpense;
  final Future<void> Function() onImportExpenses;
  final Future<void> Function() onExportExpenses;
  final Future<void> Function() onDeleteMonthlyExpenses;
  final Future<void> Function() onDeleteAllYearsExpenses;
  final bool canDeleteMonthlyExpenses;
  final bool canDeleteAllYearsExpenses;

  const _ExpandableHomeFab({
    required this.onAddExpense,
    required this.onImportExpenses,
    required this.onExportExpenses,
    required this.onDeleteMonthlyExpenses,
    required this.onDeleteAllYearsExpenses,
    required this.canDeleteMonthlyExpenses,
    required this.canDeleteAllYearsExpenses,
  });

  @override
  State<_ExpandableHomeFab> createState() => _ExpandableHomeFabState();
}

class _ExpandableHomeFabState extends State<_ExpandableHomeFab> {
  var _isExpanded = false;

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _isExpanded = false);
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _isExpanded
              ? Column(
                  key: const ValueKey('expanded-actions'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _FabActionRow(
                      label: 'Add Expense',
                      icon: Icons.add,
                      onPressed: () => _runAction(widget.onAddExpense),
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Import from Excel',
                      icon: Icons.file_upload_outlined,
                      onPressed: () => _runAction(widget.onImportExpenses),
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Export to Excel',
                      icon: Icons.file_download_outlined,
                      onPressed: () => _runAction(widget.onExportExpenses),
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Delete Monthly Expense',
                      icon: Icons.delete_sweep_outlined,
                      backgroundColor: widget.canDeleteMonthlyExpenses
                          ? theme.colorScheme.errorContainer
                          : theme.disabledColor.withAlpha(40),
                      foregroundColor: widget.canDeleteMonthlyExpenses
                          ? theme.colorScheme.onErrorContainer
                          : theme.disabledColor,
                      onPressed: widget.canDeleteMonthlyExpenses
                          ? () => _runAction(widget.onDeleteMonthlyExpenses)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Delete All Years Expenses',
                      icon: Icons.delete_forever_outlined,
                      backgroundColor: widget.canDeleteAllYearsExpenses
                          ? theme.colorScheme.error
                          : theme.disabledColor.withAlpha(40),
                      foregroundColor: widget.canDeleteAllYearsExpenses
                          ? theme.colorScheme.onError
                          : theme.disabledColor,
                      onPressed: widget.canDeleteAllYearsExpenses
                          ? () => _runAction(widget.onDeleteAllYearsExpenses)
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        FloatingActionButton(
          onPressed: _toggle,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 180),
            turns: _isExpanded ? 0.125 : 0,
            child: Icon(_isExpanded ? Icons.close : Icons.menu),
          ),
        ),
      ],
    );
  }
}

class _FabActionRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _FabActionRow({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = onPressed != null;
    final maxLabelWidth = MediaQuery.sizeOf(context).width * 0.62;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLabelWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isEnabled ? null : theme.disabledColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          onPressed: onPressed,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          child: Icon(icon),
        ),
      ],
    );
  }
}

class _MonthSelector extends ConsumerWidget {
  final DateTime selectedMonth;
  const _MonthSelector({required this.selectedMonth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref.read(homeMonthProvider.notifier).state = DateTime(
                selectedMonth.year,
                selectedMonth.month - 1,
              );
            },
          ),
          Text(
            DateFormat('MMMM yyyy').format(selectedMonth),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              final next = DateTime(
                selectedMonth.year,
                selectedMonth.month + 1,
              );
              if (!next.isAfter(DateTime.now())) {
                ref.read(homeMonthProvider.notifier).state = next;
              }
            },
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final double totalSpent;
  final double? budget;

  const _BudgetCard({required this.totalSpent, this.budget});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBudget = budget != null && budget! > 0;
    final progress = hasBudget ? (totalSpent / budget!).clamp(0.0, 1.0) : 0.0;

    Color progressColor = theme.colorScheme.primary;
    if (hasBudget) {
      if (progress >= 1.0) {
        progressColor = theme.colorScheme.error;
      } else if (progress >= 0.75) {
        progressColor = Colors.orange;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Spent',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  if (hasBudget)
                    Text(
                      'Budget: ${formatCurrency(budget!)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatCurrency(totalSpent),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hasBudget) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}% of budget used',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'No budget set for this month',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseList extends ConsumerWidget {
  final List<Expense> expenses;
  final List<Category> categories;

  const _ExpenseList({required this.expenses, required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryById = <String, Category>{
      for (final c in categories) c.id: c,
    };

    // Group by date
    final Map<String, List<Expense>> grouped = {};
    for (final e in expenses) {
      final key = formatDayHeader(e.date);
      grouped.putIfAbsent(key, () => []).add(e);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final dateKey = grouped.keys.elementAt(index);
        final dayExpenses = grouped[dateKey]!;
        final dayTotal = dayExpenses.fold(0.0, (sum, e) => sum + e.amount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateKey,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Text(
                    formatCurrency(dayTotal),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            ...dayExpenses.map((expense) {
              final category = categoryById[expense.categoryId];
              return _ExpenseTile(
                expense: expense,
                category: category,
                ref: ref,
              );
            }),
          ],
        );
      },
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final Category? category;
  final WidgetRef ref;

  const _ExpenseTile({
    required this.expense,
    required this.category,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _safeCategoryColor(theme);

    return Dismissible(
      key: Key(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Expense'),
            content: Text('Delete "${expense.title}"? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref.read(expenseProvider.notifier).deleteExpense(expense.id);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"${expense.title}" deleted')));
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(
            iconFromName(category?.iconName ?? 'more_horiz'),
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          expense.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: category != null
            ? Text(
                category!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            : null,
        trailing: SizedBox(
          width: 110,
          child: Text(
            formatCurrency(expense.amount),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddEditExpenseScreen(expense: expense),
          ),
        ),
      ),
    );
  }

  Color _safeCategoryColor(ThemeData theme) {
    if (category == null) return theme.colorScheme.primary;
    final parsed = int.tryParse(
      category!.colorHex.replaceAll('#', ''),
      radix: 16,
    );
    if (parsed == null) return theme.colorScheme.primary;
    return Color(parsed + 0xFF000000);
  }
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
