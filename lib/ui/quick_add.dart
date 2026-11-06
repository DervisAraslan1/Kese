import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/money.dart';
import '../core/parse.dart';
import '../core/plans.dart';
import '../core/store.dart';
import 'editor.dart';
import 'widgets.dart';

Future<void> showQuickAdd(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => StoreScope(
        store: StoreScope.of(context),
        child: _QuickAdd(pageContext: context),
      ),
    );

const _examples = [
  'market 340 tl',
  'dün kira 12.500 #ev',
  'maaş +45.000',
  'telefon 30.000 6 taksit',
  'ali 500 #alacak',
];

class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.pageContext});

  final BuildContext pageContext;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final store = StoreScope.of(context);
    final result = parseEntry(_controller.text, store.today, store.transactions);
    final entry = result.entry;
    if (entry == null) {
      setState(() => _error = result.error);
      return;
    }
    final page = widget.pageContext;
    final Undo undo;
    if (entry.debt != null) {
      final debt = store.addDebt(entry.debt!, entry.title, entry.amount);
      undo = Undo('“${debt.title}” eklendi', () => store.deleteDebt(debt.id));
    } else if (entry.installments > 1) {
      undo = store.addInstallments(entry);
    } else {
      final saved = store.add(entry);
      undo = Undo('“${saved.title}” eklendi', () => store.delete(saved.id));
    }
    Navigator.pop(context);
    showUndo(page, undo);
  }

  String _describe(ParsedEntry entry, String today) {
    if (entry.debt != null) return entry.debt!.label;
    final base = '${entry.category.label} · ${relativeDay(entry.date, today)}';
    if (entry.installments == 1) return base;
    final first = splitInstallments(entry).first.amount;
    return '$base · ${entry.installments} × ${formatMoney(first)}';
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final text = _controller.text;
    final preview = text.trim().isEmpty
        ? null
        : parseEntry(text, store.today, store.transactions).entry;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'market 340 tl',
              errorText: _error,
              errorMaxLines: 2,
              suffixIcon: IconButton(
                tooltip: 'Kaydet',
                icon: const Icon(Icons.check),
                onPressed: _submit,
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          if (preview != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CategoryBadge(preview.category),
              title: Text(preview.title),
              subtitle: Text(_describe(preview, store.today)),
              trailing: Text(
                formatMoney(preview.amount),
                style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
            )
          else if (text.trim().isEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final example in _examples)
                  ActionChip(
                    label: Text(example),
                    onPressed: () => setState(() {
                      _controller.text = example;
                      _controller.selection =
                          TextSelection.collapsed(offset: example.length);
                    }),
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                final page = widget.pageContext;
                Navigator.pop(context);
                showTransactionEditor(page);
              },
              child: const Text('Form ile ekle'),
            ),
          ),
        ],
      ),
    );
  }
}
