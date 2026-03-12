import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../models/category.dart';
import '../../providers/category_provider.dart';
import '../../providers/expense_provider.dart';
import '../../utils/category_icons.dart';
import '../../widgets/empty_state_widget.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryProvider);
    final expenses = ref.watch(expenseProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categories) {
          if (categories.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.category,
              title: 'No categories',
              subtitle: 'Tap + to add a category',
            );
          }
          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final count = expenses
                  .where((e) => e.categoryId == cat.id)
                  .length;
              final color = Color(
                int.parse(cat.colorHex.replaceAll('#', ''), radix: 16) +
                    0xFF000000,
              );
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withAlpha(30),
                  child: Icon(
                    iconFromName(cat.iconName),
                    color: color,
                    size: 20,
                  ),
                ),
                title: Text(cat.name),
                subtitle: Text('$count expense${count == 1 ? '' : 's'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      _showCategorySheet(context, ref, category: cat),
                ),
                onTap: () => _showCategorySheet(context, ref, category: cat),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategorySheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCategorySheet(
    BuildContext context,
    WidgetRef ref, {
    Category? category,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategorySheet(category: category, ref: ref),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  final Category? category;
  final WidgetRef ref;

  const _CategorySheet({this.category, required this.ref});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _nameController = TextEditingController();
  Color _selectedColor = Colors.blue;
  String _selectedIcon = 'more_horiz';

  @override
  void initState() {
    super.initState();
    if (widget.category != null) {
      final cat = widget.category!;
      _nameController.text = cat.name;
      _selectedColor = Color(
        int.parse(cat.colorHex.replaceAll('#', ''), radix: 16) + 0xFF000000,
      );
      _selectedIcon = cat.iconName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a name')));
      return;
    }
    final notifier = widget.ref.read(categoryProvider.notifier);
    if (widget.category != null) {
      await notifier.updateCategory(
        widget.category!.copyWith(
          name: name,
          colorHex: _colorToHex(_selectedColor),
          iconName: _selectedIcon,
        ),
      );
    } else {
      await notifier.addCategory(
        name: name,
        colorHex: _colorToHex(_selectedColor),
        iconName: _selectedIcon,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final expenses = widget.ref.read(expenseProvider).valueOrNull ?? [];
    final count = expenses
        .where((e) => e.categoryId == widget.category!.id)
        .length;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete: $count expense${count == 1 ? '' : 's'} use this category',
          ),
        ),
      );
      return;
    }
    await widget.ref
        .read(categoryProvider.notifier)
        .deleteCategory(widget.category!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.category != null ? 'Edit Category' : 'Add Category',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          Text('Color', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          BlockPicker(
            pickerColor: _selectedColor,
            onColorChanged: (c) => setState(() => _selectedColor = c),
          ),
          const SizedBox(height: 16),
          Text('Icon', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: reservedCategoryIcons.map((name) {
              final selected = _selectedIcon == name;
              return GestureDetector(
                onTap: () => setState(() => _selectedIcon = name),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? _selectedColor.withAlpha(50)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: selected
                        ? Border.all(color: _selectedColor, width: 2)
                        : null,
                  ),
                  child: Icon(
                    iconFromName(name),
                    color: selected ? _selectedColor : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (widget.category != null)
                TextButton.icon(
                  onPressed: _delete,
                  icon: Icon(Icons.delete, color: theme.colorScheme.error),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
