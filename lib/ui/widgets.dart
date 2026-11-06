import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/phone.dart';
import '../core/store.dart';
import 'editor.dart';
import 'theme.dart';

class StoreScope extends InheritedNotifier<Store> {
  const StoreScope({super.key, required Store store, required super.child})
      : super(notifier: store);

  static Store of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

class PhoneScope extends InheritedWidget {
  const PhoneScope({super.key, required this.phone, required super.child});

  final Phone phone;

  static Phone of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PhoneScope>()!.phone;

  @override
  bool updateShouldNotify(PhoneScope oldWidget) => phone != oldWidget.phone;
}

const tabular = [FontFeature.tabularFigures()];

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showUndo(BuildContext context, Undo? undo) {
  if (undo == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(undo.message),
      // A snack bar with an action otherwise stays up until something replaces
      // it, covering the rows beneath.
      persist: false,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'Geri al', onPressed: undo.revert),
    ));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.size = 42});

  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(categoryIcon(category), color: color, size: size * 0.52),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile(this.transaction, {super.key, this.showDate = true});

  final Transaction transaction;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tx = transaction;
    final subtitle = showDate
        ? '${tx.category.label} · ${relativeDay(tx.date, store.today)}'
        : tx.category.label;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: CategoryBadge(tx.category),
      title: Text(tx.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${tx.isExpense ? '-' : '+'}${formatMoney(tx.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          fontFeatures: tabular,
          color: tx.isExpense
              ? Theme.of(context).colorScheme.onSurface
              : context.keseColors.good,
        ),
      ),
      onTap: () => showTransactionEditor(context, transaction: tx),
    );
  }
}

/// Swipe left to delete. Undo lives in the snack bar.
class DismissibleTransaction extends StatelessWidget {
  const DismissibleTransaction(this.transaction, {super.key, this.showDate = true});

  final Transaction transaction;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final danger = context.keseColors.danger;
    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: danger.withValues(alpha: 0.2),
        child: Icon(Icons.delete_outline, color: danger),
      ),
      onDismissed: (_) => showUndo(context, StoreScope.of(context).delete(transaction.id)),
      child: TransactionTile(transaction, showDate: showDate),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

class MonthPicker extends StatelessWidget {
  const MonthPicker({
    super.key,
    required this.month,
    required this.current,
    required this.onChanged,
  });

  final String month;
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Önceki ay',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onChanged(addMonths(month, -1)),
          ),
          SizedBox(
            width: 150,
            child: Text(
              formatMonth(month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Sonraki ay',
            icon: const Icon(Icons.chevron_right),
            onPressed: month == current ? null : () => onChanged(addMonths(month, 1)),
          ),
        ],
      );
}
