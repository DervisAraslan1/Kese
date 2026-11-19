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

/// "Alacaklarım" and "Borçlarım": each list adds its own kind.
class DebtsSection extends StatelessWidget {
  const DebtsSection({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DebtList(DebtKind.owed),
          _DebtList(DebtKind.owe),
        ],
      );
}

String _listTitle(DebtKind kind) => kind == DebtKind.owed ? 'Alacaklarım' : 'Borçlarım';
String _addTooltip(DebtKind kind) => kind == DebtKind.owed ? 'Yeni alacak' : 'Yeni borç';
String _payLabel(DebtKind kind) => kind == DebtKind.owed ? 'tahsil edildi' : 'ödendi';
String _keseTick(DebtKind kind) => kind == DebtKind.owed ? 'Keseden düş' : 'Keseye ekle';
String _paymentTick(DebtKind kind) =>
    kind == DebtKind.owed ? 'Keseye eklensin' : 'Keseden düşülsün';

class _DebtList extends StatelessWidget {
  const _DebtList(this.kind);

  final DebtKind kind;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final mine = store.data.debts.where((d) => d.kind == kind).toList();
    final open = mine.fold(0, (sum, d) => sum + d.remaining);

    // Open debts first, the soonest due on top; those without a date follow.
    int rank(Debt d) => d.settled ? 2 : (d.due == null ? 1 : 0);
    mine.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byDue = (a.due ?? '').compareTo(b.due ?? '');
      return byDue != 0 ? byDue : b.date.compareTo(a.date);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          _listTitle(kind),
          trailing: IconButton(
            tooltip: _addTooltip(kind),
            icon: const Icon(Icons.add),
            onPressed: () => _editDebt(context, store, kind: kind),
          ),
        ),
        if (mine.isEmpty)
          Card(
            child: EmptyNote(
              kind == DebtKind.owed
                  ? 'Birine verdiğin para burada durur. Gelir-gider istatistiklerine girmez.'
                  : 'Birinden aldığın borç burada durur. Gelir-gider istatistiklerine girmez.',
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (open > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(
                      'Toplam ${formatMoney(open)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular),
                    ),
                  ),
                for (final debt in mine) _DebtRow(debt),
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
    final verb = debt.kind == DebtKind.owed ? 'verildi' : 'alındı';
    final parts = [
      '${relativeDay(debt.date, today)} $verb',
      if (debt.paid > 0) '${formatMoney(debt.paid)} ${_payLabel(debt.kind)}',
      if (debt.due != null) 'Günü ${relativeDay(debt.due!, today)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kese = context.keseColors;
    final colors = Theme.of(context).colorScheme;
    final late = !debt.settled && debt.due != null && debt.due!.compareTo(store.today) < 0;
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
  bool _kese = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// An empty field means all that is left.
  void _pay(Debt debt) {
    final text = _controller.text.trim();
    final amount = text.isEmpty ? debt.remaining : parseAmount(text);
    if (amount == null || amount == 0) {
      setState(() => _error = 'Geçerli bir tutar yaz. Örnek: 500');
      return;
    }
    if (amount > debt.remaining) {
      setState(() => _error = 'Kalan ${formatMoney(debt.remaining)}, fazlası yazılamaz.');
      return;
    }
    final undo = StoreScope.of(context).payDebt(debt.id, amount, kese: _kese);
    Navigator.pop(context);
    showUndo(widget.pageContext, undo);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final debt = store.data.debts.where((d) => d.id == widget.debtId).firstOrNull;
    if (debt == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final danger = context.keseColors.danger;
    final typed = parseAmount(_controller.text.trim());
    final payLabel = _payLabel(debt.kind);
    final verb = debt.kind == DebtKind.owed ? 'verildi' : 'alındı';
    final keseNote = debt.kese
        ? (debt.kind == DebtKind.owed ? 'keseden düştü' : 'keseye girdi')
        : 'keseyi etkilemedi';
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              debt.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              debt.settled
                  ? '${debt.kind.label} · ${formatMoney(debt.amount)} · Kapandı'
                  : '${debt.kind.label} · ${formatMoney(debt.remaining)} kaldı',
            ),
            Text(
              '${relativeDay(debt.date, store.today)} $verb, $keseNote',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
            if (debt.note != null) ...[
              const SizedBox(height: 6),
              Text(debt.note!, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
            if (!debt.settled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Tutar',
                  helperText: 'Boş bırakırsan tamamı: ${formatMoney(debt.remaining)}',
                  suffixText: '₺',
                  errorText: _error,
                ),
                onSubmitted: (_) => _pay(debt),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _kese,
                onChanged: (v) => setState(() => _kese = v ?? true),
                title: Text(_paymentTick(debt.kind)),
              ),
              FilledButton(
                onPressed: () => _pay(debt),
                child: Text(
                  typed == null || typed == 0
                      ? 'Tamamı $payLabel'
                      : '${formatMoney(typed)} $payLabel',
                ),
              ),
            ],
            if (debt.payments.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Hareketler', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
              for (final p in debt.payments.reversed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${formatMoney(p.amount)} $payLabel',
                    style: const TextStyle(fontFeatures: tabular),
                  ),
                  subtitle: Text(
                    '${relativeDay(p.date, store.today)} · ${p.kese ? 'kesede' : 'kese dışı'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Ödemeyi sil',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => showUndo(
                      widget.pageContext,
                      store.removePayment(debt.id, p.id),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _editDebt(widget.pageContext, store, debt: debt);
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
      ),
    );
  }
}

class _DebtDraft {
  const _DebtDraft({
    required this.kind,
    required this.title,
    required this.amount,
    required this.date,
    required this.due,
    required this.note,
    required this.kese,
  });
  final DebtKind kind;
  final String title;
  final int amount;
  final String date;
  final String? due;
  final String note;
  final bool kese;
}

Future<void> _editDebt(
  BuildContext context,
  Store store, {
  Debt? debt,
  DebtKind kind = DebtKind.owed,
}) async {
  final result = await showDialog<_DebtDraft>(
    context: context,
    builder: (_) => _DebtDialog(debt: debt, kind: kind, today: store.today),
  );
  if (result == null) return;
  if (debt == null) {
    store.addDebt(
      result.kind,
      result.title,
      result.amount,
      due: result.due,
      date: result.date,
      note: result.note,
      kese: result.kese,
    );
  } else {
    store.updateDebt(
      debt.id,
      kind: result.kind,
      title: result.title,
      amount: result.amount,
      due: result.due,
      date: result.date,
      note: result.note,
      kese: result.kese,
    );
  }
}

class _DebtDialog extends StatefulWidget {
  const _DebtDialog({required this.debt, required this.kind, required this.today});

  final Debt? debt;
  final DebtKind kind;
  final String today;

  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  late final _title = TextEditingController(text: widget.debt?.title ?? '');
  late final _amount = TextEditingController(
    text: widget.debt == null ? '' : amountForInput(widget.debt!.amount),
  );
  late final _note = TextEditingController(text: widget.debt?.note ?? '');
  late DebtKind _kind = widget.debt?.kind ?? widget.kind;
  late String _date = widget.debt?.date ?? widget.today;
  late String? _due = widget.debt?.due;

  /// A new loan given leaves the kese, a new loan taken does not: old debts
  /// entered after the fact are already in the kese.
  late bool _kese = widget.debt?.kese ?? _kind == DebtKind.owed;
  bool _keseTouched = false;
  String? _titleError;
  String? _amountError;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<String?> _pick(String? current) async {
    final today = fromKey(widget.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? today : fromKey(current),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 10),
    );
    return picked == null ? null : toKey(picked);
  }

  void _save() {
    final title = _title.text.trim();
    final amount = parseAmount(_amount.text);
    final paid = widget.debt?.paid ?? 0;
    final amountError = amount == null || amount == 0
        ? 'Geçerli bir tutar yaz. Örnek: 1.500'
        : amount < paid
            ? '${formatMoney(paid)} ödenmiş, daha az olamaz.'
            : null;
    if (title.isEmpty || amountError != null) {
      setState(() {
        _titleError = title.isEmpty ? 'Kimle olduğunu yaz.' : null;
        _amountError = amountError;
      });
      return;
    }
    Navigator.pop(
      context,
      _DebtDraft(
        kind: _kind,
        title: title,
        amount: amount!,
        date: _date,
        due: _due,
        note: _note.text,
        kese: _kese,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final owed = _kind == DebtKind.owed;
    return AlertDialog(
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
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                if (widget.debt == null && !_keseTouched) _kese = _kind == DebtKind.owed;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: widget.debt == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Kişi', errorText: _titleError),
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
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _kese,
              onChanged: (v) => setState(() {
                _kese = v ?? false;
                _keseTouched = true;
              }),
              title: Text(_keseTick(_kind)),
              subtitle: Text(
                owed
                    ? 'Eskiden verdiğin bir paraysa işaretleme.'
                    : 'Eskiden kalan bir borçsa işaretleme.',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.today_outlined),
              title: Text(owed ? 'Veriliş tarihi' : 'Alış tarihi'),
              trailing: Text(relativeDay(_date, widget.today)),
              onTap: () async {
                final picked = await _pick(_date);
                if (picked != null) setState(() => _date = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(owed ? 'Geri ödeme günü' : 'Vade'),
              trailing: Text(_due == null ? 'Yok' : relativeDay(_due!, widget.today)),
              onTap: () async {
                final picked = await _pick(_due);
                if (picked != null) setState(() => _due = picked);
              },
            ),
            if (_due != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _due = null),
                  child: const Text('Günü kaldır'),
                ),
              ),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        TextButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
