import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/insights.dart';
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
    final spent = sumOf(monthly.where((t) => t.isExpense));
    final earned = sumOf(monthly.where((t) => !t.isExpense));
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
        Text(
          formatMonth(month),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        _Hero(spent: spent, earned: earned, forecast: forecast),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.spent, required this.earned, required this.forecast});

  final int spent;
  final int earned;
  final Forecast? forecast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kese = context.keseColors;
    final left = earned - spent;
    final forecast = this.forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LivePouch(
          level: pouchLevel(spent: spent, earned: earned),
          amount: left,
          // The mask paints the text, so only its shape matters here.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bu ay kalan',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TweenAnimationBuilder<int>(
                  tween: IntTween(end: left),
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
                Row(
                  children: [
                    Expanded(child: _Stat('Gelir', earned, kese.good)),
                    Expanded(child: _Stat('Gider', spent, colors.onSurface)),
                  ],
                ),
                if (forecast != null) ...[
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

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;

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
              fontSize: 16,
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
