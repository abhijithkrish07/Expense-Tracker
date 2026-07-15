import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/providers/analytics_provider.dart';
import 'package:expense_tracker/utils/backup_utils.dart';

void main() {
  group('Expense.fromJson / toJson', () {
    test('round-trips a fully-populated expense', () {
      final original = Expense(
        id: 'e1',
        title: 'Coffee',
        amount: 3.5,
        date: DateTime(2026, 7, 15),
        categoryId: 'c1',
        tags: const ['morning', 'cafe'],
        note: 'oat milk',
      );

      final restored = Expense.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.amount, original.amount);
      expect(restored.date, original.date);
      expect(restored.categoryId, original.categoryId);
      expect(restored.tags, original.tags);
      expect(restored.note, original.note);
    });

    test('defaults tags to empty when absent', () {
      final restored = Expense.fromJson({
        'id': 'e2',
        'title': 'Bus',
        'amount': 2,
        'date': DateTime(2026, 7, 15).toIso8601String(),
        'categoryId': 'c2',
      });

      expect(restored.tags, isEmpty);
      expect(restored.note, isNull);
      expect(restored.amount, 2.0);
    });
  });

  group('AnalyticsSummary.compute', () {
    Expense expense(String id, double amount, DateTime date, String cat) =>
        Expense(id: id, title: id, amount: amount, date: date, categoryId: cat);

    test('aggregates category totals and counts for the selected month', () {
      final expenses = [
        expense('1', 10, DateTime(2026, 7, 1), 'food'),
        expense('2', 15, DateTime(2026, 7, 5), 'food'),
        expense('3', 40, DateTime(2026, 7, 8), 'rent'),
        // Different month — must be excluded.
        expense('4', 99, DateTime(2026, 6, 30), 'food'),
      ];

      final summary = AnalyticsSummary.compute(expenses, 2026, 7);

      expect(summary.totalSpent, 65);
      // Sorted descending by total: rent (40) before food (25).
      expect(summary.categoryTotals.first.categoryId, 'rent');
      expect(summary.categoryTotals.first.total, 40);
      final food = summary.categoryTotals
          .firstWhere((c) => c.categoryId == 'food');
      expect(food.total, 25);
      expect(food.count, 2);
    });

    test('builds exactly 6 trailing months ending on the selected month', () {
      final expenses = [
        expense('1', 20, DateTime(2026, 7, 2), 'x'),
        expense('2', 30, DateTime(2026, 5, 2), 'x'),
      ];

      final summary = AnalyticsSummary.compute(expenses, 2026, 7);

      expect(summary.last6Months, hasLength(6));
      expect(summary.last6Months.last.month, 7);
      expect(summary.last6Months.last.total, 20);
      final may = summary.last6Months
          .firstWhere((m) => m.year == 2026 && m.month == 5);
      expect(may.total, 30);
    });

    test('handles an empty expense list without dividing by zero', () {
      final summary = AnalyticsSummary.compute(const [], 2026, 3);

      expect(summary.totalSpent, 0);
      expect(summary.categoryTotals, isEmpty);
      expect(summary.avgPerDay, 0);
      expect(summary.daysInPeriod, greaterThan(0));
    });
  });

  group('computeCollectionDelta', () {
    test('detects upserts for new and changed rows', () {
      final previous = [
        {'id': 'a', 'v': 1},
        {'id': 'b', 'v': 2},
      ];
      final current = [
        {'id': 'a', 'v': 1}, // unchanged
        {'id': 'b', 'v': 99}, // changed
        {'id': 'c', 'v': 3}, // new
      ];

      final delta = computeCollectionDelta(previous, current);

      final upsertIds = delta.upsert.map((r) => r['id']).toSet();
      expect(upsertIds, {'b', 'c'});
      expect(delta.delete, isEmpty);
    });

    test('detects deletes for rows removed from current', () {
      final previous = [
        {'id': 'a', 'v': 1},
        {'id': 'b', 'v': 2},
      ];
      final current = [
        {'id': 'a', 'v': 1},
      ];

      final delta = computeCollectionDelta(previous, current);

      expect(delta.upsert, isEmpty);
      expect(delta.delete, ['b']);
    });

    test('ignores rows without a valid id', () {
      final previous = <Map<String, dynamic>>[];
      final current = [
        {'id': '', 'v': 1},
        {'v': 2},
        {'id': 'ok', 'v': 3},
      ];

      final delta = computeCollectionDelta(previous, current);

      expect(delta.upsert.map((r) => r['id']), ['ok']);
    });
  });
}
