import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/insights.dart';
import '../core/kese.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/store.dart';
import 'ambient.dart';
import 'debts.dart';
import 'goals.dart';
import 'pouch.dart';
import 'theme.dart';
import 'widgets.dart';

int sumOf(Iterable<Transaction> items) => items.fold(0, (sum, t) => sum + t.amount);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final today = store.today;
    final month = monthOf(today);
    final monthly = store.transactions.where((t) => monthOf(t.date) == month).toList();
    final forecast = forecastMonth(store.transactions, today);
    final insights = buildInsights(store.data, today);
    // Installments ahead are commitments, not things that happened.
    final recent = store.transactions
        .where((t) => !t.isInstallment || t.date.compareTo(today) <= 0)
        .toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });

    var order = 0;
    Widget reveal(Widget child) => Reveal(index: order++, child: child);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, pageBottomInset(context)),
      children: [
        if (store.recovered)
          const _Notice(
            text: 'Kayıtlı veri okunamadı. Dosya silinmedi, kenara alındı ve yeni bir başlangıç yapıldı.',
          ),
        if (store.data.demo) const _DemoNotice(),
        _KeseSwitch(month: month),
        const SizedBox(height: 6),
        _Hero(forecast: forecast),
        if (insights.isNotEmpty) ...[
          reveal(const SectionTitle('Sana özel öneriler')),
          for (final insight in insights)
            reveal(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InsightCard(insight),
            )),
        ],
        if (store.data.limits.isNotEmpty) ...[
          const SectionTitle('Limitler'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  for (final entry in store.data.limits.entries)
                    _LimitRow(
                      category: entry.key,
                      limit: entry.value,
                      spent: sumOf(monthly.where(
                        (t) => t.isExpense && t.category == entry.key,
                      )),
                    ),
                ],
              ),
            ),
          ),
        ],
        const PlansSection(),
        const GoalsSection(),
        const SectionTitle('Son işlemler'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: recent.isEmpty
              ? const EmptyNote('Henüz işlem yok. Aşağıdaki + ile ilkini ekle: “market 340 tl”.')
              : Column(
                  children: [
                    for (final tx in recent.take(6)) DismissibleTransaction(tx),
                  ],
                ),
        ),
        const DebtsSection(),
      ],
    );
  }
}

/// "Bu ay" or "Genel" on top of the kese.
class _KeseSwitch extends StatelessWidget {
  const _KeseSwitch({required this.month});

  final String month;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final view = store.data.keseView;
    return Row(
      children: [
        Expanded(
          child: Text(
            view == KeseView.month ? formatMonth(month) : 'Bugüne kadar',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        SegmentedButton<KeseView>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(value: KeseView.month, label: Text('Bu ay')),
            ButtonSegment(value: KeseView.overall, label: Text('Genel')),
          ],
          selected: {view},
          onSelectionChanged: (s) => store.setKeseView(s.first),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.forecast});

  final Forecast? forecast;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final kese = context.keseColors;
    final overall = store.data.keseView == KeseView.overall;
    final month = monthKese(store.data, store.today);
    final shown = overall ? overallKese(store.data, store.today) : month;
    final debts = openDebts(store.data);
    final debtFlow = month.debtIn - month.debtOut;
    final forecast = this.forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LivePouch(
          // The pouch always follows the month: how much of what came in is left.
          level: pouchLevel(
            spent: month.spent + month.debtOut,
            earned: month.earned + month.debtIn,
          ),
          amount: shown.kese,
          blend: store.data.pouchTextBlend,
          // The mask paints the text, so only its shape matters here.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                overall ? 'Kesede' : 'Bu ay kalan',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TweenAnimationBuilder<int>(
                  tween: IntTween(end: shown.kese),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    formatMoney(value),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          fontFeatures: tabular,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!overall) ...[
                  Row(
                    children: [
                      Expanded(child: _Stat('Gelir', month.earned, kese.good)),
                      Expanded(child: _Stat('Gider', month.spent, colors.onSurface)),
                    ],
                  ),
                  if (debtFlow != 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Borç ve alacak hareketleri: ${debtFlow > 0 ? '+' : '−'}${formatMoney(debtFlow.abs())}',
                      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
                    ),
                  ],
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(child: _Stat('Alacaklar', debts.owed, kese.good, small: !overall)),
                    Expanded(
                      child: _Stat('Borçlar', debts.owe, colors.onSurface, small: !overall),
                    ),
                    if (overall)
                      Expanded(
                        child: _Stat(
                          'Net durum',
                          shown.kese + debts.owed - debts.owe,
                          colors.primary,
                        ),
                      ),
                  ],
                ),
                if (overall) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Net durum = Kese + Alacaklar − Borçlar',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => _adjustKese(context, store, shown.kese),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Keseyi düzelt'),
                    ),
                  ),
                ] else if (forecast != null) ...[
                  const Divider(height: 24),
                  Text(
                    'Ay sonu tahmini: ${formatMoney(forecast.projected)} harcama, '
                    '${forecast.balance < 0 ? '${formatMoney(-forecast.balance)} eksi' : '${formatMoney(forecast.balance)} artı'}.',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Son ${forecast.basisDays} günün verisine dayanıyor.',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Asks for the money really on hand; the overall kese then shows it.
Future<void> _adjustKese(BuildContext context, Store store, int current) async {
  final actual = await showDialog<int>(
    context: context,
    builder: (_) => _AdjustDialog(current: current),
  );
  if (actual == null || !context.mounted) return;
  showUndo(context, store.adjustKese(actual));
}

/// Owns its field, which must outlive the dialog's closing animation.
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.current});

  final int current;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  late final _controller = TextEditingController(
    text: widget.current > 0 ? amountForInput(widget.current) : '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    final value = text == '0' ? 0 : parseAmount(text);
    if (value == null) {
      setState(() => _error = 'Geçerli bir tutar yaz. Örnek: 12.500');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Keseyi düzelt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Şu an elinde ne kadar para var? Kese bu tutarı gösterir. '
              'Gelir ve gider istatistikleri değişmez.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Elindeki para',
                suffixText: '₺',
                errorText: _error,
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

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.amount, this.color, {this.small = false});

  final String label;
  final int amount;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
          Text(
            formatMoney(amount),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: small ? 14 : 16,
              fontFeatures: tabular,
            ),
          ),
        ],
      );
}

const _insightLabels = {
  InsightKind.subscription: ('Abonelik', Icons.autorenew),
  InsightKind.forecast: ('Ay sonu', Icons.insights_outlined),
  InsightKind.increase: ('Artış', Icons.trending_up),
  InsightKind.limit: ('Limit', Icons.speed_outlined),
  InsightKind.unusual: ('Olağandışı', Icons.priority_high),
  InsightKind.upcoming: ('Yaklaşan', Icons.event_outlined),
  InsightKind.debt: ('Borç', Icons.handshake_outlined),
};

class _InsightCard extends StatelessWidget {
  const _InsightCard(this.insight);

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final (label, icon) = _insightLabels[insight.kind]!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: colors.primary, fontSize: 12.5),
                  ),
                ),
                IconButton(
                  tooltip: 'Öneriyi kapat: ${insight.title}',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => store.dismissInsight(insight),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(insight.reason, style: TextStyle(color: colors.onSurfaceVariant)),
                  if (insight.actionLabel != null) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => showUndo(context, store.acceptInsight(insight)),
                      child: Text(insight.actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.category, required this.limit, required this.spent});

  final Category category;
  final int limit;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final kese = context.keseColors;
    final colors = Theme.of(context).colorScheme;
    final over = spent >= limit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(category.label)),
              Text(
                '${formatMoney(spent)} / ${formatMoney(limit)}',
                style: const TextStyle(fontFeatures: tabular),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (spent / limit).clamp(0.0, 1.0),
              minHeight: 7,
              color: over ? kese.danger : colors.primary,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
        color: context.keseColors.danger.withValues(alpha: 0.16),
        child: Padding(padding: const EdgeInsets.all(14), child: Text(text)),
      );
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    final Store store = StoreScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              const Expanded(child: Text('Örnek verilerle geziyorsun.')),
              TextButton(onPressed: store.startEmpty, child: const Text('Temizle ve başla')),
            ],
          ),
        ),
      ),
    );
  }
}
