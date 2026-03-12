import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/budget.dart';
import 'storage_provider.dart';

final budgetProvider =
    AsyncNotifierProvider<BudgetNotifier, List<Budget>>(BudgetNotifier.new);

class BudgetNotifier extends AsyncNotifier<List<Budget>> {
  static const _uuid = Uuid();

  @override
  Future<List<Budget>> build() =>
      ref.read(storageServiceProvider).loadBudgets();

  /// Upsert: replaces existing budget for same (year, month, categoryId) or adds new.
  Future<void> setBudget({
    required int year,
    required int month,
    required double limitAmount,
    String? categoryId,
  }) async {
    final current = state.valueOrNull ?? [];
    final existing = current.indexWhere((b) =>
        b.year == year && b.month == month && b.categoryId == categoryId);

    List<Budget> updated;
    if (existing >= 0) {
      updated = List.from(current);
      updated[existing] = current[existing].copyWith(limitAmount: limitAmount);
    } else {
      final newBudget = Budget(
        id: _uuid.v4(),
        year: year,
        month: month,
        limitAmount: limitAmount,
        categoryId: categoryId,
      );
      updated = [...current, newBudget];
    }
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveBudgets(updated);
  }

  Future<void> deleteBudget(String id) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((b) => b.id != id).toList();
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveBudgets(updated);
  }

  Budget? budgetFor(int year, int month, {String? categoryId}) {
    return (state.valueOrNull ?? [])
        .cast<Budget?>()
        .firstWhere(
            (b) =>
                b?.year == year &&
                b?.month == month &&
                b?.categoryId == categoryId,
            orElse: () => null);
  }
}
