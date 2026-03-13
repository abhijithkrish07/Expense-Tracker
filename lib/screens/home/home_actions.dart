// Home actions: encapsulates import/export/delete flows to keep HomeScreen focused on UI composition.
// Caveat: this file handles platform-specific export paths and Excel parsing assumptions.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:uuid/uuid.dart';

import '../../models/category.dart';
import '../../models/expense.dart';
import '../../providers/category_provider.dart';
import '../../providers/expense_provider.dart';
import '../expense/add_edit_expense_screen.dart';

class HomeActions {
  const HomeActions();

  static const _uuid = Uuid();

  Future<void> openAddExpense(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEditExpenseScreen()),
    );
  }

  Future<void> importExpensesFromExcel(
    BuildContext context,
    WidgetRef ref,
  ) async {
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

    if (context.mounted) {
      final imported = expensesToImport.length;
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

  Future<void> deleteMonthlyExpenses(
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

  Future<void> deleteAllYearsExpenses(BuildContext context, WidgetRef ref) async {
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

    final deleted = await ref.read(expenseProvider.notifier).deleteAllExpenses();

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

  Future<void> exportExpensesToExcel(BuildContext context, WidgetRef ref) async {
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
    final categoryById = <String, Category>{for (final c in categories) c.id: c};

    final monthGroups = <DateTime, List<Expense>>{};
    for (final expense in allExpenses) {
      final monthKey = DateTime(expense.date.year, expense.date.month);
      monthGroups.putIfAbsent(monthKey, () => []).add(expense);
    }

    final sortedMonths = monthGroups.keys.toList()..sort();

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    for (final monthKey in sortedMonths) {
      final expenses = monthGroups[monthKey]!;
      final monthLabel = DateFormat('MMM yyyy').format(monthKey).toUpperCase();
      final sheet = excel[monthLabel];

      final categoryGroups = <String, List<Expense>>{};
      for (final expense in expenses) {
        final category = categoryById[expense.categoryId];
        final categoryName = category?.name ?? 'Uncategorized';
        categoryGroups.putIfAbsent(categoryName, () => []).add(expense);
      }

      final sortedCategories = categoryGroups.keys.toList()..sort();

      const headers = ['Category', 'Date', 'Expense', 'Amount'];
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          ..value = TextCellValue(headers[i])
          ..cellStyle = CellStyle(bold: true);
      }

      var rowIndex = 1;
      for (final categoryName in sortedCategories) {
        final categoryExpenses = categoryGroups[categoryName]!
          ..sort((a, b) => b.date.compareTo(a.date));

        var categoryTotal = 0.0;
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

        final subtotalRow = [
          TextCellValue('$categoryName - Subtotal'),
          TextCellValue(''),
          TextCellValue(''),
          DoubleCellValue(categoryTotal),
        ];
        sheet.appendRow(subtotalRow);
        final subtotalRowIndex = rowIndex;
        for (var i = 0; i < 4; i++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: i,
              rowIndex: subtotalRowIndex,
            ),
          );
          cell.cellStyle = CellStyle(bold: true);
        }
        rowIndex++;
      }

      final monthTotal = expenses.fold(0.0, (sum, e) => sum + e.amount);
      final totalRow = [
        TextCellValue('TOTAL FOR $monthLabel'),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(monthTotal),
      ];
      sheet.appendRow(totalRow);
      final totalRowIndex = rowIndex;
      for (var i = 0; i < 4; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: totalRowIndex),
        );
        cell.cellStyle = CellStyle(bold: true);
      }

      sheet.setColumnWidth(0, 20);
      sheet.setColumnWidth(1, 15);
      sheet.setColumnWidth(2, 25);
      sheet.setColumnWidth(3, 12);
    }

    try {
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
      if (fileBytes == null) return;

      final file = io.File(filePath);
      await file.writeAsBytes(fileBytes);

      if (!context.mounted) return;
      final openFile = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('File saved to:\n$fileName\n\nWould you like to open it now?'),
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
            await OpenFile.open(
              filePath,
              type:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File not found. Please check your Downloads folder.'),
              ),
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
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

    if (raw.startsWith('=')) {
      raw = raw.substring(1);
    }

    final hasArithmeticOperator = RegExp(r'[+\-*/]').hasMatch(raw);
    if (hasArithmeticOperator) {
      return _evaluateSimpleExpression(raw);
    }

    final normalizedNumeric = raw
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(normalizedNumeric);
  }

  double? _evaluateSimpleExpression(String input) {
    var expression = input.replaceAll(' ', '').replaceAll(',', '');
    expression = expression.replaceAll(RegExp(r'[^0-9.+\-*/]'), '');
    if (expression.isEmpty) return null;

    if (expression.startsWith('-')) {
      expression = '0$expression';
    }

    final tokens = RegExp(
      r'(\d+(?:\.\d+)?)|[+\-*/]',
    ).allMatches(expression).map((m) => m.group(0)!).toList();

    if (tokens.isEmpty || tokens.join() != expression) return null;
    if (tokens.first.length == 1 && '+-*/'.contains(tokens.first)) {
      return null;
    }

    final first = double.tryParse(tokens.first);
    if (first == null) return null;

    final values = <double>[];
    final addSubOps = <String>[];
    var current = first;

    var i = 1;
    while (i + 1 < tokens.length) {
      final op = tokens[i];
      final next = double.tryParse(tokens[i + 1]);
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

    if (i != tokens.length) return null;

    values.add(current);
    var result = values.first;
    for (var j = 0; j < addSubOps.length; j++) {
      result =
          addSubOps[j] == '+' ? result + values[j + 1] : result - values[j + 1];
    }

    return result;
  }

  DateTime? _inferMonthDateFromSheetName(String sheetName) {
    var normalized = sheetName.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    normalized = normalized
        .replaceAll(RegExp(r'[^A-Z0-9]'), ' ')
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

    final year = rawYear.length == 2 ? 2000 + parsed : parsed;
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
}

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
