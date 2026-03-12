import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/expense.dart';
import 'storage_provider.dart';

final expenseProvider = AsyncNotifierProvider<ExpenseNotifier, List<Expense>>(
  ExpenseNotifier.new,
);

class ExpenseNotifier extends AsyncNotifier<List<Expense>> {
  static const _uuid = Uuid();

  @override
  Future<List<Expense>> build() =>
      ref.read(storageServiceProvider).loadExpenses();

  Future<void> addExpense({
    required String title,
    required double amount,
    required DateTime date,
    required String categoryId,
    List<String> tags = const [],
    String? note,
  }) async {
    final expense = Expense(
      id: _uuid.v4(),
      title: title,
      amount: amount,
      date: date,
      categoryId: categoryId,
      tags: tags,
      note: note,
    );
    final current = state.valueOrNull ?? [];
    final updated = [...current, expense];
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveExpenses(updated);
  }

  Future<void> addExpensesBulk(List<Expense> expenses) async {
    if (expenses.isEmpty) return;
    final current = state.valueOrNull ?? [];
    final updated = [...current, ...expenses];
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveExpenses(updated);
  }

  Future<void> updateExpense(Expense expense) async {
    final current = state.valueOrNull ?? [];
    final updated = current
        .map((e) => e.id == expense.id ? expense : e)
        .toList();
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveExpenses(updated);
  }

  Future<void> deleteExpense(String id) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((e) => e.id != id).toList();
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveExpenses(updated);
  }

  Future<int> deleteExpensesForMonth(int year, int month) async {
    final current = state.valueOrNull ?? [];
    final updated = current
        .where((e) => e.date.year != year || e.date.month != month)
        .toList();

    final deletedCount = current.length - updated.length;
    if (deletedCount == 0) return 0;

    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveExpenses(updated);
    return deletedCount;
  }

  Future<int> deleteAllExpenses() async {
    final current = state.valueOrNull ?? [];
    if (current.isEmpty) return 0;

    state = const AsyncData([]);
    await ref.read(storageServiceProvider).saveExpenses(const []);
    return current.length;
  }

  Set<String> get allUsedTags {
    final expenses = state.valueOrNull ?? [];
    return expenses.expand((e) => e.tags).toSet();
  }
}
