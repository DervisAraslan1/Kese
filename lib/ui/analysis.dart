import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/insights.dart';
import '../core/models.dart';
import '../core/money.dart';
import 'home.dart';
import 'theme.dart';
import 'widgets.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  String? _month;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final today = store.today;
    final current = monthOf(today);
    final month = _month ?? current;
    final transactions = store.transactions;

    final byCategory = <Category, int>{};
    for (final tx in transactions) {
      if (tx.isExpense && monthOf(tx.date) == month) {
        byCategory[tx.category] = (byCategory[tx.category] ?? 0) + tx.amount;
      }
    }
    final ranked = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = ranked.fold(0, (sum, e) => sum + e.value);

    final bars = [
      for (var i = 5; i >= 0; i--)
        () {
          final m = addMonths(current, -i);
          final items = transactions.where((t) => monthOf(t.date) == m);
          return _MonthBar(
            month: m,
            spent: sumOf(items.where((t) => t.isExpense)),
            earned: sumOf(items.where((t) => !t.isExpense)),
          );
        }(),
    ];

    final subscriptions = detectRecurring(transactions, today, TxType.expense);
    final subscriptionTotal = subscriptions.fold(0, (sum, r) => sum + r.amount);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, pageBottomInset(context)),
      children: [
        MonthPicker(
          month: month,
          current: current,
          onChanged: (value) => setState(() => _month = value),
        ),
        const SectionTitle('Kategori dağılımı'),
        Card(
          child: ranked.isEmpty
              ? const EmptyNote('Bu ay harcama yok.')
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _Donut(ranked, total),
                      const SizedBox(height: 12),
                      for (final entry in ranked)
                        _CategoryRow(entry.key, entry.value, total),
                    ],
                  ),
                ),
        ),
        const SectionTitle('Son 6 ay'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: _MonthChart(bars),
          ),
        ),
        SectionTitle(
          'Düzenli ödemeler',
          trailing: subscriptions.isEmpty
              ? null
              : Text(
                  '${formatMoney(subscriptionTotal)} / ay',
                  style: const TextStyle(fontFeatures: tabular),
                ),
        ),
        Card(
          child: subscriptions.isEmpty
              ? const EmptyNote('En az 3 ay üst üste ödenen tutarlar burada görünür.')
              : Column(
                  children: [
                    for (final item in subscriptions)
                      ListTile(
                        leading: CategoryBadge(item.category),
                        title: Text(item.title),
                        subtitle: Text('Sıradaki: ${relativeDay(item.nextDate, today)}'),
                        trailing: Text(
                          formatMoney(item.amount),
                          style: const TextStyle(fontFeatures: tabular),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Sweeps open when the page appears, with the month's total in the middle.
class _Donut extends StatelessWidget {
  const _Donut(this.ranked, this.total);

  final List<MapEntry<Category, int>> ranked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Toplam ${formatMoney(total)}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 190,
          child: TweenAnimationBuilder<double>(
            // Keyed so that changing month sweeps again.
            key: ValueKey(total),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, sweep, child) => CustomPaint(
              painter: _DonutPainter(ranked, total, sweep, colors.surfaceContainerHighest),
              child: child,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Toplam',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12.5),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 90),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatMoney(total),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          fontFeatures: tabular,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.ranked, this.total, this.sweep, this.track);

  final List<MapEntry<Category, int>> ranked;
  final int total;
  final double sweep;
  final Color track;

  static const _stroke = 20.0;
  static const _gap = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 - _stroke / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(rect.center, radius, paint..color = track.withValues(alpha: 0.5));

    final gap = ranked.length > 1 ? _gap + _stroke / radius : 0.0;
    var start = -math.pi / 2;
    for (final entry in ranked) {
      final full = entry.value / total * math.pi * 2 * sweep;
      paint.color = categoryColor(entry.key);
      if (full > gap) {
        canvas.drawArc(rect, start + gap / 2, full - gap, false, paint..strokeCap = StrokeCap.round);
      } else {
        // Too thin for round ends, which would swallow its neighbors.
        canvas.drawArc(rect, start, full, false, paint..strokeCap = StrokeCap.butt);
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.sweep != sweep || old.total != total || old.track != track;
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow(this.category, this.amount, this.total);

  final Category category;
  final int amount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final percent = (amount * 100 / total).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: [
          Row(
            children: [
              Icon(categoryIcon(category), size: 17, color: categoryColor(category)),
              const SizedBox(width: 8),
              Expanded(child: Text(category.label)),
              Text(
                '${formatMoney(amount)} · %$percent',
                style: const TextStyle(fontFeatures: tabular),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: amount / total,
              minHeight: 7,
              color: categoryColor(category),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar {
  const _MonthBar({required this.month, required this.spent, required this.earned});

  final String month;
  final int spent;
  final int earned;
}

class _MonthChart extends StatelessWidget {
  const _MonthChart(this.bars);

  final List<_MonthBar> bars;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kese = context.keseColors;
    final highest = bars.fold(1, (top, b) {
      final larger = b.spent > b.earned ? b.spent : b.earned;
      return larger > top ? larger : top;
    });

    Widget legend(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12.5)),
          ],
        );

    return Semantics(
      label: bars
          .map((b) =>
              '${formatMonth(b.month)}: gelir ${formatMoney(b.earned)}, gider ${formatMoney(b.spent)}')
          .join('. '),
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final bar in bars)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _Bar(bar.earned / highest, kese.good),
                          const SizedBox(width: 3),
                          _Bar(bar.spent / highest, colors.primary.withValues(alpha: 0.55)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final bar in bars)
                  Expanded(
                    child: Text(
                      formatMonthShort(bar.month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              children: [
                legend(kese.good, 'Gelir'),
                legend(colors.primary.withValues(alpha: 0.55), 'Gider'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.ratio, this.color);

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: ratio),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Container(
          width: 11,
          height: 150 * value,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, color.withValues(alpha: 0.35)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
      );
}
