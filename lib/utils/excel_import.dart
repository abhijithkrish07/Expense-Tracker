import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

/// A single expense row parsed from an exported Excel workbook.
class ParsedExpenseRow {
  final String categoryName;
  final DateTime date;
  final String title;
  final double amount;

  const ParsedExpenseRow({
    required this.categoryName,
    required this.date,
    required this.title,
    required this.amount,
  });
}

/// Result of parsing a workbook: the usable rows and how many rows were
/// ignored (aggregate/subtotal/blank/malformed).
typedef ParseResult = ({List<ParsedExpenseRow> rows, int skipped});

final _exportDateFormat = DateFormat('dd MMM yyyy');

/// Parses an Excel workbook produced by the app's "Export to Excel" feature.
///
/// The export writes one sheet per month with header
/// `Category | Date | Expense | Amount`, plus per-category subtotal rows and a
/// monthly total row. This reverses that layout back into expense rows,
/// skipping the header and aggregate rows.
///
/// Throws [FormatException] if the bytes are not a readable workbook.
ParseResult parseExpenseWorkbook(Uint8List bytes) {
  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (e) {
    throw FormatException('Not a readable Excel file: $e');
  }

  final rows = <ParsedExpenseRow>[];
  var skipped = 0;

  for (final sheet in excel.tables.values) {
    for (final cells in sheet.rows) {
      if (cells.isEmpty) {
        skipped++;
        continue;
      }

      final category = _cellToString(cells, 0);
      final dateStr = _cellToString(cells, 1);
      final title = _cellToString(cells, 2);
      final amount = _cellToDouble(cells, 3);
      final dateCell = _cellToDate(cells, 1);

      if (_isSkippableRow(category, dateStr, title)) {
        skipped++;
        continue;
      }

      final date = dateCell ?? _parseDate(dateStr);
      if (date == null || amount == null) {
        skipped++;
        continue;
      }

      rows.add(
        ParsedExpenseRow(
          categoryName: category.trim(),
          date: date,
          title: title.trim(),
          amount: amount,
        ),
      );
    }
  }

  return (rows: rows, skipped: skipped);
}

/// Header, aggregate (subtotal/total), and blank rows are not real expenses.
bool _isSkippableRow(String category, String dateStr, String title) {
  final c = category.trim();
  if (c.isEmpty) return true;
  if (c == 'Category') return true; // header
  if (c.contains('- Subtotal')) return true; // per-category subtotal
  if (c.startsWith('TOTAL FOR')) return true; // monthly total
  // A genuine expense row always has a date and title.
  if (dateStr.trim().isEmpty || title.trim().isEmpty) return true;
  return false;
}

DateTime? _parseDate(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  try {
    return _exportDateFormat.parseStrict(value);
  } catch (_) {
    return DateTime.tryParse(value);
  }
}

/// Handles the case where the date column decoded as a native date cell
/// rather than the `dd MMM yyyy` string the app writes.
DateTime? _cellToDate(List<Data?> cells, int index) {
  if (index >= cells.length) return null;
  final value = cells[index]?.value;
  if (value is DateCellValue) return value.asDateTimeLocal();
  return null;
}

String _cellToString(List<Data?> cells, int index) {
  if (index >= cells.length) return '';
  final value = cells[index]?.value;
  if (value == null) return '';
  if (value is TextCellValue) {
    return value.value.text ?? '';
  }
  if (value is IntCellValue) return value.value.toString();
  if (value is DoubleCellValue) return value.value.toString();
  return value.toString();
}

double? _cellToDouble(List<Data?> cells, int index) {  if (index >= cells.length) return null;
  final value = cells[index]?.value;
  if (value == null) return null;
  if (value is DoubleCellValue) return value.value;
  if (value is IntCellValue) return value.value.toDouble();
  if (value is TextCellValue) {
    return double.tryParse(value.value.text?.trim() ?? '');
  }
  return double.tryParse(value.toString().trim());
}
