import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});
