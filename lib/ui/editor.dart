import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/parse.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the form for a new or an existing transaction.
Future<void> showTransactionEditor(BuildContext context, {Transaction? transaction}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => StoreScope(
        store: StoreScope.of(context),
        child: _Editor(transaction: transaction, messengerContext: context),
      ),
    );

class _Editor extends StatefulWidget {
  const _Editor({required this.transaction, required this.messengerContext});

  final Transaction? transaction;

  /// The page behind the sheet, which outlives it and can show the undo bar.
  final BuildContext messengerContext;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late TxType _type;
  late Category _category;
  String? _date;
  int _installments = 1;

  static const _installmentChoices = [1, 2, 3, 4, 5, 6, 9, 12, 18, 24, 36];

  Transaction? get _existing => widget.transaction;

  @override
  void initState() {
    super.initState();
    final tx = _existing;
    _title = TextEditingController(text: tx?.title);
    _amount = TextEditingController(text: tx == null ? '' : amountForInput(tx.amount));
    _type = tx?.type ?? TxType.expense;
    _category = tx?.category ?? Category.diger;
    _date = tx?.date;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _setType(TxType type) => setState(() {
        _type = type;
        _category = type == TxType.income ? Category.gelir : Category.diger;
        if (type == TxType.income) _installments = 1;
      });

  Future<void> _pickDate(String today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fromKey(_date ?? today),
      firstDate: DateTime(2000),
      lastDate: fromKey(addDays(today, 365)),
    );
    if (picked != null) setState(() => _date = toKey(picked));
  }

  void _save(String today) {
    if (!_form.currentState!.validate()) return;
    final store = StoreScope.of(context);
    final entry = ParsedEntry(
      type: _type,
      amount: parseAmount(_amount.text)!,
      title: _title.text.trim(),
      category: _category,
      date: _date ?? today,
      installments: _installments,
    );
    final existing = _existing;
    final messenger = widget.messengerContext;
    Navigator.pop(context);
    if (existing == null) {
      if (_installments > 1) {
        showUndo(messenger, store.addInstallments(entry));
      } else {
        store.add(entry);
      }
      return;
    }
    showUndo(
      messenger,
      store.update(existing.copyWith(
        type: entry.type,
        amount: entry.amount,
        title: entry.title,
        category: entry.category,
        date: entry.date,
      )),
    );
  }

  void _delete() {
    final store = StoreScope.of(context);
    final messenger = widget.messengerContext;
    final id = _existing!.id;
    Navigator.pop(context);
    showUndo(messenger, store.delete(id));
  }

  String? _validateAmount(String? value) {
    final amount = parseAmount(value ?? '');
    if (amount == null) return 'Geçerli bir tutar yaz. Örnek: 1.250,75';
    if (amount == 0) return 'Tutar sıfır olamaz.';
    return amount < _installments ? 'Tutar bu kadar taksite bölünemez.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final today = StoreScope.of(context).today;
    final categories =
        _type == TxType.income ? const [Category.gelir] : Category.expenses;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _existing == null ? 'Yeni işlem' : 'İşlemi düzenle',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<TxType>(
                segments: const [
                  ButtonSegment(value: TxType.expense, label: Text('Gider')),
                  ButtonSegment(value: TxType.income, label: Text('Gelir')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => _setType(s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Başlık'),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Başlık boş olamaz.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Tutar', suffixText: '₺'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _validateAmount,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Tarih'),
                trailing: Text(relativeDay(_date ?? today, today)),
                onTap: () => _pickDate(today),
              ),
              if (_existing == null && _type == TxType.expense)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.credit_card_outlined),
                  title: const Text('Taksit'),
                  trailing: DropdownButton<int>(
                    value: _installments,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final count in _installmentChoices)
                        DropdownMenuItem(
                          value: count,
                          child: Text(count == 1 ? 'Peşin' : '$count taksit'),
                        ),
                    ],
                    onChanged: (value) => setState(() => _installments = value ?? 1),
                  ),
                ),
              if (_existing?.isInstallment ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Bu, ${_existing!.planCount} taksitin ${_existing!.planIndex}. taksiti. '
                    'Değişiklik yalnızca bunu etkiler.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final category in categories)
                    ChoiceChip(
                      avatar: Icon(
                        categoryIcon(category),
                        size: 17,
                        color: categoryColor(category),
                      ),
                      showCheckmark: false,
                      label: Text(category.label),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => _save(today),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text('Kaydet'),
                ),
              ),
              if (_existing != null)
                TextButton.icon(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: context.keseColors.danger),
                  label: Text('Sil', style: TextStyle(color: context.keseColors.danger)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same title normalization the rest of the app uses, for search.
bool titleMatches(String title, String query) =>
    normalizeTitle(title).contains(normalizeTitle(query));
