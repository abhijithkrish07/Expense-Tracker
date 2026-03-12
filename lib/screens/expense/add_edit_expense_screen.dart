import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../models/category.dart';
import '../../models/expense.dart';
import '../../providers/expense_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/category_icons.dart';

class AddEditExpenseScreen extends ConsumerStatefulWidget {
  final Expense? expense;

  const AddEditExpenseScreen({super.key, this.expense});

  @override
  ConsumerState<AddEditExpenseScreen> createState() =>
      _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends ConsumerState<AddEditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _tagController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedCategoryId;
  List<String> _tags = [];
  bool _saving = false;

  bool get _isEditing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final e = widget.expense!;
      _titleController.text = e.title;
      _amountController.text = e.amount.toStringAsFixed(2);
      _noteController.text = e.note ?? '';
      _selectedDate = e.date;
      _selectedCategoryId = e.categoryId;
      _tags = List.from(e.tags);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _addTag(String tag) {
    final t = tag.trim().toLowerCase();
    if (t.isNotEmpty && !_tags.contains(t)) {
      setState(() => _tags.add(t));
    }
    _tagController.clear();
  }

  Future<void> _showCreateCategoryDialog() async {
    final nameController = TextEditingController();
    Color selectedColor = Colors.blue;
    String selectedIcon = 'more_horiz';
    String? newCategoryId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Category'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Category name'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Text('Pick a color', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                BlockPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (c) =>
                      setDialogState(() => selectedColor = c),
                ),
                const SizedBox(height: 16),
                Text('Pick an icon', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reservedCategoryIcons.map((iconName) {
                    final selected = selectedIcon == iconName;
                    return GestureDetector(
                      onTap: () =>
                          setDialogState(() => selectedIcon = iconName),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected
                              ? selectedColor.withAlpha(50)
                              : Theme.of(
                                  ctx,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(color: selectedColor, width: 2)
                              : null,
                        ),
                        child: Icon(
                          iconFromName(iconName),
                          color: selected ? selectedColor : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final hex =
                    '#${selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                final newCat = await ref
                    .read(categoryProvider.notifier)
                    .addCategory(
                      name: name,
                      colorHex: hex,
                      iconName: selectedIcon,
                    );
                newCategoryId = newCat.id;
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (newCategoryId != null && mounted) {
      setState(() => _selectedCategoryId = newCategoryId);
    }
  }

  Future<void> _showEditCategoryDialog(Category category) async {
    final nameController = TextEditingController(text: category.name);
    Color selectedColor = Color(
      int.parse(category.colorHex.replaceAll('#', ''), radix: 16) + 0xFF000000,
    );
    String selectedIcon = category.iconName;
    final iconOptions = reservedCategoryIcons.contains(selectedIcon)
        ? reservedCategoryIcons
        : [...reservedCategoryIcons, selectedIcon];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Category'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Category name'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Text('Pick a color', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                BlockPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (c) =>
                      setDialogState(() => selectedColor = c),
                ),
                const SizedBox(height: 16),
                Text('Pick an icon', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: iconOptions.map((iconName) {
                    final selected = selectedIcon == iconName;
                    return GestureDetector(
                      onTap: () =>
                          setDialogState(() => selectedIcon = iconName),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected
                              ? selectedColor.withAlpha(50)
                              : Theme.of(
                                  ctx,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(color: selectedColor, width: 2)
                              : null,
                        ),
                        child: Icon(
                          iconFromName(iconName),
                          color: selected ? selectedColor : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final hex =
                    '#${selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                await ref
                    .read(categoryProvider.notifier)
                    .updateCategory(
                      category.copyWith(
                        name: name,
                        colorHex: hex,
                        iconName: selectedIcon,
                      ),
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }

    setState(() => _saving = true);
    final amount = double.parse(_amountController.text.replaceAll(',', ''));

    if (_isEditing) {
      await ref
          .read(expenseProvider.notifier)
          .updateExpense(
            widget.expense!.copyWith(
              title: _titleController.text.trim(),
              amount: amount,
              date: _selectedDate,
              categoryId: _selectedCategoryId!,
              tags: _tags,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
            ),
          );
    } else {
      await ref
          .read(expenseProvider.notifier)
          .addExpense(
            title: _titleController.text.trim(),
            amount: amount,
            date: _selectedDate,
            categoryId: _selectedCategoryId!,
            tags: _tags,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(expenseProvider.notifier)
          .deleteExpense(widget.expense!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryProvider);
    final categories = categoriesAsync.valueOrNull ?? [];
    Category? selectedCategory;
    if (_selectedCategoryId != null) {
      for (final cat in categories) {
        if (cat.id == _selectedCategoryId) {
          selectedCategory = cat;
          break;
        }
      }
    }
    final theme = Theme.of(context);

    // Autocomplete suggestions
    final allTags = ref.read(expenseProvider.notifier).allUsedTags.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Expense' : 'Add Expense'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Amount
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter an amount';
                final n = double.tryParse(v.replaceAll(',', ''));
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Title
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 16),

            // Date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Category picker
            Text(
              'Category',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            categories.isEmpty
                ? const CircularProgressIndicator()
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...categories.map((cat) {
                        final color = Color(
                          int.parse(
                                cat.colorHex.replaceAll('#', ''),
                                radix: 16,
                              ) +
                              0xFF000000,
                        );
                        final isSelected = _selectedCategoryId == cat.id;
                        return FilterChip(
                          avatar: Icon(
                            iconFromName(cat.iconName),
                            size: 16,
                            color: isSelected ? Colors.white : color,
                          ),
                          label: Text(cat.name),
                          selected: isSelected,
                          selectedColor: color,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                          ),
                          onSelected: (_) {
                            setState(() {
                              // Toggle: unselect if already selected
                              _selectedCategoryId = isSelected ? null : cat.id;
                            });
                          },
                        );
                      }),
                      // Show "+ New Category" chip only when "Other" is selected
                      if (_selectedCategoryId == 'cat-other')
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: const Text('New Category'),
                          onPressed: _showCreateCategoryDialog,
                        ),
                      if (selectedCategory != null)
                        (() {
                          final categoryToEdit = selectedCategory!;
                          return ActionChip(
                            avatar: const Icon(Icons.edit, size: 16),
                            label: const Text('Edit Category'),
                            onPressed: () =>
                                _showEditCategoryDialog(categoryToEdit),
                          );
                        })(),
                    ],
                  ),
            const SizedBox(height: 16),

            // Tags
            Text(
              'Tags',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            if (_tags.isNotEmpty)
              Wrap(
                spacing: 8,
                children: _tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                      ),
                    )
                    .toList(),
              ),
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return [];
                return allTags.where(
                  (t) => t.contains(textEditingValue.text.toLowerCase()),
                );
              },
              onSelected: _addTag,
              fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
                _tagController.text = controller.text;
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Add tag',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _addTag(controller.text),
                    ),
                  ),
                  onFieldSubmitted: _addTag,
                );
              },
            ),
            const SizedBox(height: 16),

            // Note
            TextFormField(
              controller: _noteController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            // Delete button (edit mode only)
            if (_isEditing)
              OutlinedButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete, color: theme.colorScheme.error),
                label: Text(
                  'Delete Expense',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
