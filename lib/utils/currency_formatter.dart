import 'package:intl/intl.dart';

final _formatter = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
final _compact = NumberFormat.compact();

String formatCurrency(double amount) => _formatter.format(amount);
String formatCurrencyCompact(double amount) => '₹${_compact.format(amount)}';
