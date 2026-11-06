import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/plans.dart';
import '../core/store.dart';
import 'theme.dart';
import 'widgets.dart';

/// Only shown while something is left to pay; there is nothing to set up here
/// because installments are entered like any other purchase.
class PlansSection extends StatelessWidget {
  const PlansSection({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final plans = activePlans(store.transactions, store.today);
    if (plans.isEmpty) return const SizedBox.shrink();

    final nextMonth = addMonths(monthOf(store.today), 1);
    final dueNextMonth = plans
        .expand((p) => p.ahead)
        .where((t) => monthOf(t.date) == nextMonth)
        .fold(0, (sum, t) => sum + t.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Taksitler'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dueNextMonth > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '${formatMonth(nextMonth)} taksitleri: ${formatMoney(dueNextMonth)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              for (final plan in plans) _PlanRow(plan),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(this.plan);

  final InstallmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openPlan(context, store, plan),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${formatMoney(plan.remaining)} kaldı',
                  style: const TextStyle(fontFeatures: tabular),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: plan.done / plan.count,
                minHeight: 7,
                color: colors.primary,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${plan.done}/${plan.count} · Sıradaki ${relativeDay(plan.next.date, store.today)}, '
              '${formatMoney(plan.next.amount)}',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openPlan(
  BuildContext context,
  Store store,
  InstallmentPlan plan,
) {
  // Deleting removes the row this context belongs to, while the sheet is still
  // closing and may rebuild, so nothing inside the builder may look it up.
  final danger = context.keseColors.danger;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) {
      void remove({required bool onlyFuture}) {
        final undo = store.deletePlan(plan.id, onlyFuture: onlyFuture);
        Navigator.pop(sheet);
        showUndo(context, undo);
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              plan.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheet).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${plan.ahead.length} taksit kaldı, toplam ${formatMoney(plan.remaining)}.',
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => remove(onlyFuture: true),
              child: const Text('Kalan taksitleri sil'),
            ),
            TextButton.icon(
              onPressed: () => remove(onlyFuture: false),
              icon: Icon(Icons.delete_outline, color: danger),
              label: Text('Tümünü sil', style: TextStyle(color: danger)),
            ),
          ],
        ),
      );
    },
  );
}

class DebtsSection extends StatelessWidget {
  const DebtsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    int total(DebtKind kind) => store.data.debts
        .where((d) => d.kind == kind)
        .fold(0, (sum, d) => sum + d.remaining);
    final owe = total(DebtKind.owe);
    final owed = total(DebtKind.owed);

    // Open debts first, the soonest due on top; those without a date follow.
    int rank(Debt d) => d.settled ? 2 : (d.due == null ? 1 : 0);
    final debts = [...store.data.debts]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : (a.due ?? '').compareTo(b.due ?? '');
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Borç ve alacak',
          trailing: IconButton(
            tooltip: 'Yeni borç veya alacak',
            icon: const Icon(Icons.add),
            onPressed: () => _editDebt(context, store),
          ),
        ),
        if (debts.isEmpty)
          const Card(
            child: EmptyNote(
              'Verdiğin ve aldığın borçlar burada durur, bütçeni etkilemez.',
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (owe > 0 || owed > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(
                      'Borcun ${formatMoney(owe)} · Alacağın ${formatMoney(owed)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
                for (final debt in debts) _DebtRow(debt),
              ],
            ),
          ),
      ],
    );
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow(this.debt);

  final Debt debt;

  String _status(String today) {
    if (debt.settled) return 'Kapandı';
    final parts = [
      debt.kind.label,
      if (debt.paid > 0) '${formatMoney(debt.paid)} ödendi',
      if (debt.due != null) 'Günü ${relativeDay(debt.due!, today)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kese = context.keseColors;
    final colors = Theme.of(context).colorScheme;
    final late =
        !debt.settled &&
        debt.due != null &&
        debt.due!.compareTo(store.today) < 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(debt.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _status(store.today),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: late ? kese.danger : colors.onSurfaceVariant),
      ),
      trailing: Text(
        formatMoney(debt.settled ? debt.amount : debt.remaining),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          fontFeatures: tabular,
          color: debt.settled
              ? colors.onSurfaceVariant
              : debt.kind == DebtKind.owed
              ? kese.good
              : colors.onSurface,
        ),
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => StoreScope(
          store: store,
          child: _DebtSheet(debtId: debt.id, pageContext: context),
        ),
      ),
    );
  }
}

class _DebtSheet extends StatefulWidget {
  const _DebtSheet({required this.debtId, required this.pageContext});

  final String debtId;
  final BuildContext pageContext;

  @override
  State<_DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends State<_DebtSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(int sign) {
    final amount = parseAmount(_controller.text);
    if (amount == null || amount == 0) {
      setState(() => _error = 'Geçerli bir tutar yaz. Örnek: 500');
      return;
    }
    final undo = StoreScope.of(context).payDebt(widget.debtId, sign * amount);
    Navigator.pop(context);
    showUndo(widget.pageContext, undo);
  }

  void _settle(Debt debt) {
    final undo = StoreScope.of(context).payDebt(debt.id, debt.remaining);
    Navigator.pop(context);
    showUndo(widget.pageContext, undo);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final debt = store.data.debts
        .where((d) => d.id == widget.debtId)
        .firstOrNull;
    if (debt == null) return const SizedBox.shrink();
    final danger = context.keseColors.danger;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            debt.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('${debt.kind.label} · ${formatMoney(debt.remaining)} kaldı'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Tutar',
              suffixText: '₺',
              errorText: _error,
            ),
            onSubmitted: (_) => _apply(1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _apply(-1),
                  child: const Text('Düzelt (azalt)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _apply(1),
                  child: const Text('Ödeme ekle'),
                ),
              ),
            ],
          ),
          if (!debt.settled)
            TextButton(
              onPressed: () => _settle(debt),
              child: const Text('Tamamını kapat'),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _editDebt(widget.pageContext, store, debt);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Düzenle'),
              ),
              TextButton.icon(
                onPressed: () {
                  final undo = store.deleteDebt(debt.id);
                  Navigator.pop(context);
                  showUndo(widget.pageContext, undo);
                },
                icon: Icon(Icons.delete_outline, color: danger),
                label: Text('Sil', style: TextStyle(color: danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtDraft {
  const _DebtDraft(this.kind, this.title, this.amount, this.due);
  final DebtKind kind;
  final String title;
  final int amount;
  final String? due;
}

Future<void> _editDebt(BuildContext context, Store store, [Debt? debt]) async {
  final result = await showDialog<_DebtDraft>(
    context: context,
    builder: (_) => _DebtDialog(debt: debt, today: store.today),
  );
  if (result == null) return;
  if (debt == null) {
    store.addDebt(result.kind, result.title, result.amount, due: result.due);
  } else {
    store.updateDebt(
      debt.id,
      kind: result.kind,
      title: result.title,
      amount: result.amount,
      due: result.due,
    );
  }
}

class _DebtDialog extends StatefulWidget {
  const _DebtDialog({required this.debt, required this.today});

  final Debt? debt;
  final String today;

  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  late final _title = TextEditingController(text: widget.debt?.title ?? '');
  late final _amount = TextEditingController(
    text: widget.debt == null ? '' : amountForInput(widget.debt!.amount),
  );
  late DebtKind _kind = widget.debt?.kind ?? DebtKind.owed;
  late String? _due = widget.debt?.due;
  String? _titleError;
  String? _amountError;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final today = fromKey(widget.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: _due == null ? today : fromKey(_due!),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 10),
    );
    if (picked != null) setState(() => _due = toKey(picked));
  }

  void _save() {
    final title = _title.text.trim();
    final amount = parseAmount(_amount.text);
    if (title.isEmpty || amount == null || amount == 0) {
      setState(() {
        _titleError = title.isEmpty ? 'Kimle olduğunu yaz.' : null;
        _amountError = amount == null || amount == 0
            ? 'Geçerli bir tutar yaz. Örnek: 1.500'
            : null;
      });
      return;
    }
    Navigator.pop(context, _DebtDraft(_kind, title, amount, _due));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.debt == null ? 'Yeni kayıt' : 'Kaydı düzenle'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<DebtKind>(
            segments: [
              for (final kind in DebtKind.values)
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: widget.debt == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Kişi veya açıklama',
              errorText: _titleError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Tutar',
              suffixText: '₺',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Ödeme günü'),
            trailing: Text(
              _due == null ? 'Yok' : relativeDay(_due!, widget.today),
            ),
            onTap: _pickDue,
          ),
          if (_due != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _due = null),
                child: const Text('Günü kaldır'),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      TextButton(onPressed: _save, child: const Text('Kaydet')),
    ],
  );
}
