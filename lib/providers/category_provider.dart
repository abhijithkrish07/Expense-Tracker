import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/category.dart';
import 'storage_provider.dart';

final categoryProvider =
    AsyncNotifierProvider<CategoryNotifier, List<Category>>(
        CategoryNotifier.new);

class CategoryNotifier extends AsyncNotifier<List<Category>> {
  static const _uuid = Uuid();

  @override
  Future<List<Category>> build() async {
    final storage = ref.read(storageServiceProvider);
    final saved = await storage.loadCategories();
    if (saved.isNotEmpty) return saved;
    // First launch: seed defaults from asset
    final jsonStr = await rootBundle
        .loadString('assets/default_categories.json');
    final list = List<Map<String, dynamic>>.from(jsonDecode(jsonStr) as List);
    final defaults = list.map(Category.fromJson).toList();
    await storage.saveCategories(defaults);
    return defaults;
  }

  Future<Category> addCategory({
    required String name,
    required String colorHex,
    required String iconName,
  }) async {
    final cat = Category(
      id: _uuid.v4(),
      name: name,
      colorHex: colorHex,
      iconName: iconName,
    );
    final current = state.valueOrNull ?? [];
    final updated = [...current, cat];
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveCategories(updated);
    return cat;
  }

  Future<void> updateCategory(Category category) async {
    final current = state.valueOrNull ?? [];
    final updated =
        current.map((c) => c.id == category.id ? category : c).toList();
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveCategories(updated);
  }

  Future<void> deleteCategory(String id) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((c) => c.id != id).toList();
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveCategories(updated);
  }

  Future<void> reorderCategories(int oldIndex, int newIndex) async {
    final current = List<Category>.from(
      state.valueOrNull ?? const <Category>[],
    );
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex < 0 || newIndex > current.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final moved = current.removeAt(oldIndex);
    current.insert(newIndex, moved);

    state = AsyncData(current);
    await ref.read(storageServiceProvider).saveCategories(current);
  }

  Category? findById(String id) {
    return (state.valueOrNull ?? [])
        .cast<Category?>()
        .firstWhere((c) => c?.id == id, orElse: () => null);
  }
}
