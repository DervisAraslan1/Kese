import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/insights.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/store.dart';
import 'theme.dart';
import 'widgets.dart';

class GoalsSection extends StatelessWidget {
  const GoalsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final goals = store.data.goals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Birikim hedefleri',
          trailing: IconButton(
            tooltip: 'Yeni hedef',
            icon: const Icon(Icons.add),
            onPressed: () => _editGoal(context, store),
          ),
        ),
        if (goals.isEmpty)
          const Card(
            child: EmptyNote('Tatil, telefon, acil durum... Bir hedef koy, Kese ne zaman ulaşacağını hesaplasın.'),
          )
        else
          for (final goal in goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GoalCard(goal),
            ),
      ],
    );
  }
}

Future<void> _editGoal(BuildContext context, Store store, [SavingsGoal? goal]) async {
  final result = await showDialog<_GoalDraft>(
    context: context,
    builder: (_) => _GoalDialog(goal: goal),
  );
  if (result == null) return;
  if (goal == null) {
    store.addGoal(result.title, result.target);
  } else {
    store.updateGoal(goal.id, title: result.title, target: result.target);
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard(this.goal);

  final SavingsGoal goal;

  String _status(Store store) {
    if (goal.reached) return 'Hedefe ulaştın.';
    final estimate = estimateGoal(goal, store.transactions, store.today);
    final left = '${formatMoney(goal.remaining)} kaldı';
    if (estimate == null) return left;
    return '$left. Ayda ${formatMoney(estimate.monthlySaving)} artıyor, '
        'bu gidişle ${formatMonth(estimate.month)}.';
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final kese = context.keseColors;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => StoreScope(
            store: store,
            child: _GoalSheet(goalId: goal.id, pageContext: context),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${formatMoney(goal.saved)} / ${formatMoney(goal.target)}',
                    style: const TextStyle(fontFeatures: tabular),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (goal.saved / goal.target).clamp(0.0, 1.0),
                  minHeight: 8,
                  color: goal.reached ? kese.good : colors.primary,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _status(store),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.goalId, required this.pageContext});

  final String goalId;
  final BuildContext pageContext;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
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
    final undo = StoreScope.of(context).addToGoal(widget.goalId, sign * amount);
    Navigator.pop(context);
    showUndo(widget.pageContext, undo);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final goal = store.data.goals.where((g) => g.id == widget.goalId).firstOrNull;
    if (goal == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            goal.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
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
                  child: const Text('Çıkar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _apply(1),
                  child: const Text('Ekle'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _editGoal(widget.pageContext, store, goal);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Düzenle'),
              ),
              TextButton.icon(
                onPressed: () {
                  final undo = store.deleteGoal(goal.id);
                  Navigator.pop(context);
                  showUndo(widget.pageContext, undo);
                },
                icon: Icon(Icons.delete_outline, color: context.keseColors.danger),
                label: Text('Sil', style: TextStyle(color: context.keseColors.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalDraft {
  const _GoalDraft(this.title, this.target);
  final String title;
  final int target;
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.goal});

  final SavingsGoal? goal;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _title = TextEditingController(text: widget.goal?.title ?? '');
  late final _target = TextEditingController(
    text: widget.goal == null ? '' : amountForInput(widget.goal!.target),
  );
  String? _titleError;
  String? _targetError;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final target = parseAmount(_target.text);
    if (title.isEmpty || target == null || target == 0) {
      setState(() {
        _titleError = title.isEmpty ? 'Hedefe bir ad ver.' : null;
        _targetError =
            target == null || target == 0 ? 'Geçerli bir tutar yaz. Örnek: 30.000' : null;
      });
      return;
    }
    Navigator.pop(context, _GoalDraft(title, target));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.goal == null ? 'Yeni hedef' : 'Hedefi düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Hedef adı', errorText: _titleError),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Hedef tutar',
                suffixText: '₺',
                errorText: _targetError,
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          TextButton(onPressed: _save, child: const Text('Kaydet')),
        ],
      );
}
