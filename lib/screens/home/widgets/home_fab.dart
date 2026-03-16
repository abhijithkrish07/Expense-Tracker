// Home floating action menu: exposes grouped quick actions and danger actions.
// Caveat: labels are constrained for smaller screens and may ellipsize.
import 'package:flutter/material.dart';

class ExpandableHomeFab extends StatefulWidget {
  final Future<void> Function() onAddExpense;
  final Future<void> Function() onImportExpenses;
  final Future<void> Function() onExportExpenses;
  final Future<void> Function() onDeleteMonthlyExpenses;
  final Future<void> Function() onDeleteAllYearsExpenses;
  final bool canDeleteMonthlyExpenses;
  final bool canDeleteAllYearsExpenses;

  const ExpandableHomeFab({
    super.key,
    required this.onAddExpense,
    required this.onImportExpenses,
    required this.onExportExpenses,
    required this.onDeleteMonthlyExpenses,
    required this.onDeleteAllYearsExpenses,
    required this.canDeleteMonthlyExpenses,
    required this.canDeleteAllYearsExpenses,
  });

  @override
  State<ExpandableHomeFab> createState() => _ExpandableHomeFabState();
}

class _ExpandableHomeFabState extends State<ExpandableHomeFab> {
  var _isExpanded = false;

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _isExpanded = false);
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _isExpanded
              ? Column(
                  key: const ValueKey('expanded-actions'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _FabActionRow(
                      label: 'Add Expense',
                      icon: Icons.add,
                      heroTag: 'home-fab-add-expense',
                      onPressed: () => _runAction(widget.onAddExpense),
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Import from Excel',
                      icon: Icons.file_upload_outlined,
                      heroTag: 'home-fab-import-expenses',
                      onPressed: () => _runAction(widget.onImportExpenses),
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Export to Excel',
                      icon: Icons.file_download_outlined,
                      heroTag: 'home-fab-export-expenses',
                      onPressed: () => _runAction(widget.onExportExpenses),
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Delete Monthly Expense',
                      icon: Icons.delete_sweep_outlined,
                      heroTag: 'home-fab-delete-monthly',
                      backgroundColor: widget.canDeleteMonthlyExpenses
                          ? theme.colorScheme.errorContainer
                          : theme.disabledColor.withAlpha(40),
                      foregroundColor: widget.canDeleteMonthlyExpenses
                          ? theme.colorScheme.onErrorContainer
                          : theme.disabledColor,
                      onPressed: widget.canDeleteMonthlyExpenses
                          ? () => _runAction(widget.onDeleteMonthlyExpenses)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _FabActionRow(
                      label: 'Delete All Years Expenses',
                      icon: Icons.delete_forever_outlined,
                      heroTag: 'home-fab-delete-all-years',
                      backgroundColor: widget.canDeleteAllYearsExpenses
                          ? theme.colorScheme.error
                          : theme.disabledColor.withAlpha(40),
                      foregroundColor: widget.canDeleteAllYearsExpenses
                          ? theme.colorScheme.onError
                          : theme.disabledColor,
                      onPressed: widget.canDeleteAllYearsExpenses
                          ? () => _runAction(widget.onDeleteAllYearsExpenses)
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        FloatingActionButton(
          heroTag: 'home-fab-menu-toggle',
          onPressed: _toggle,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 180),
            turns: _isExpanded ? 0.125 : 0,
            child: Icon(_isExpanded ? Icons.close : Icons.menu),
          ),
        ),
      ],
    );
  }
}

class _FabActionRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Object heroTag;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const _FabActionRow({
    required this.label,
    required this.icon,
    required this.heroTag,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = onPressed != null;
    final maxLabelWidth = MediaQuery.sizeOf(context).width * 0.62;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLabelWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isEnabled ? null : theme.disabledColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: heroTag,
          onPressed: onPressed,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          child: Icon(icon),
        ),
      ],
    );
  }
}
