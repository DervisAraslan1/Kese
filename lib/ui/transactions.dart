import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/models.dart';
import '../core/money.dart';
import 'editor.dart';
import 'home.dart';
import 'theme.dart';
import 'widgets.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String? _month;
  String _query = '';
  Category? _category;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final current = monthOf(store.today);
    final month = _month ?? current;
    final searching = _query.trim().isNotEmpty;

    // A search covers every month: that is why people search.
    final items = store.transactions
        .where((t) =>
            (searching || monthOf(t.date) == month) &&
            (_category == null || t.category == _category) &&
            (!searching || titleMatches(t.title, _query)))
        .toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });

    final rows = <Object>[];
    String? day;
    for (final tx in items) {
      if (tx.date != day) rows.add(day = tx.date);
      rows.add(tx);
    }
    final spent = sumOf(items.where((t) => t.isExpense));
    final earned = sumOf(items.where((t) => !t.isExpense));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'İşlem ara',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (!searching)
          MonthPicker(
            month: month,
            current: current,
            onChanged: (value) => setState(() => _month = value),
          ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final category in Category.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(categoryIcon(category), size: 16),
                    showCheckmark: false,
                    label: Text(category.label),
                    selected: _category == category,
                    onSelected: (on) => setState(() => _category = on ? category : null),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${items.length} işlem'),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Gider ${formatMoney(spent)} · Gelir ${formatMoney(earned)}',
                    style: const TextStyle(fontFeatures: tabular),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyNote('Bu seçimde işlem yok.')
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: Text(
                          relativeDay(row, store.today),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    final tx = row as Transaction;
                    return DismissibleTransaction(tx, key: ValueKey(tx.id), showDate: false);
                  },
                ),
        ),
      ],
    );
  }
}
