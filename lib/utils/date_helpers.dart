import 'package:intl/intl.dart';

String formatMonth(int year, int month) =>
    DateFormat('MMMM yyyy').format(DateTime(year, month));

String formatDate(DateTime date) =>
    DateFormat('MMM d, yyyy').format(date);

String formatDateShort(DateTime date) =>
    DateFormat('MMM d').format(date);

String formatDayHeader(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('EEEE, MMM d').format(date);
}

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

String monthKey(int year, int month) => '$year-${month.toString().padLeft(2, '0')}';
