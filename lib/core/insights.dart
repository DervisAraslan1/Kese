import 'date.dart';
import 'models.dart';
import 'money.dart';
import 'parse.dart';

const _maxVisible = 4;

/// One noisy month must not fill every slot with the same kind of card.
const _maxPerKind = 2;

enum InsightKind { subscription, forecast, increase, limit, unusual, upcoming }

sealed class InsightAction {
  const InsightAction();
}

/// Moves every expense with this title into a category.
class CategorizeAction extends InsightAction {
  const CategorizeAction(this.normTitle, this.category);
  final String normTitle;
  final Category category;
}

/// Records a known monthly payment without retyping it.
class PayAction extends InsightAction {
  const PayAction(this.title, this.amount, this.category);
  final String title;
  final int amount;
  final Category category;
}

class SetLimitAction extends InsightAction {
  const SetLimitAction(this.category, this.amount);
  final Category category;
  final int amount;
}

class Insight {
  const Insight({
    required this.key,
    required this.kind,
    required this.title,
    required this.reason,
    required this.score,
    required this.snoozeDays,
    this.actionLabel,
    this.action,
  });

  /// Stable key used to remember dismissals.
  final String key;
  final InsightKind kind;
  final String title;

  /// The evidence, in the user's own numbers.
  final String reason;
  final double score;

  /// How many days a dismissal hides this insight.
  final int snoozeDays;
  final String? actionLabel;
  final InsightAction? action;
}

/// A payment or income that repeats monthly.
class Recurring {
  const Recurring({
    required this.title,
    required this.normTitle,
    required this.amount,
    required this.day,
    required this.months,
    required this.category,
    required this.nextDate,
    required this.paidThisMonth,
  });

  final String title;
  final String normTitle;
  final int amount;
  final int day;
  final int months;
  final Category category;
  final String nextDate;
  final bool paidThisMonth;
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Finds titles paid exactly once a month for at least three months in a row,
/// with a similar amount on a similar day. The run must reach the current or
/// previous month: an older run is a cancelled subscription.
List<Recurring> detectRecurring(
  List<Transaction> transactions,
  String today,
  TxType type,
) {
  final month = monthOf(today);
  final byTitle = <String, List<Transaction>>{};
  for (final tx in transactions) {
    if (tx.type != type || tx.date.compareTo(today) > 0) continue;
    byTitle.putIfAbsent(normalizeTitle(tx.title), () => []).add(tx);
  }

  final found = <Recurring>[];
  byTitle.forEach((norm, group) {
    final byMonth = <String, List<Transaction>>{};
    for (final tx in group) {
      byMonth.putIfAbsent(monthOf(tx.date), () => []).add(tx);
    }

    final start = byMonth.containsKey(month) ? month : addMonths(month, -1);
    final run = <Transaction>[];
    for (var m = start;; m = addMonths(m, -1)) {
      final items = byMonth[m];
      if (items == null || items.length != 1) break;
      run.add(items.single);
    }
    if (run.length < 3) return;

    final amounts = run.map((t) => t.amount).toList();
    final amount = _median(amounts);
    if (amounts.any((a) => (a - amount).abs() * 10 > amount)) return;

    final days = run.map((t) => dayOf(t.date)).toList();
    final spread = days.reduce((a, b) => a > b ? a : b) -
        days.reduce((a, b) => a < b ? a : b);
    if (spread > 6) return;

    final day = _median(days);
    final paid = byMonth.containsKey(month);
    final due = dayInMonth(paid ? addMonths(month, 1) : month, day);
    final latest = run.first;
    found.add(Recurring(
      title: latest.title,
      normTitle: norm,
      amount: latest.amount,
      day: day,
      months: run.length,
      category: latest.category,
      nextDate: due.compareTo(today) < 0 ? today : due,
      paidThisMonth: paid,
    ));
  });
  found.sort((a, b) => a.nextDate.compareTo(b.nextDate));
  return found;
}

class Forecast {
  const Forecast({
    required this.spent,
    required this.projected,
    required this.income,
    required this.balance,
    required this.basisDays,
  });

  /// Spent so far this month.
  final int spent;

  /// Expected total spending by month end.
  final int projected;

  /// Income so far plus income still expected this month.
  final int income;

  /// Expected income minus expected spending.
  final int balance;

  /// Days of history behind the daily average.
  final int basisDays;
}

const _forecastWindow = 90;
const _forecastMinDays = 14;

/// Returns null until there are two weeks of history to base an average on.
Forecast? forecastMonth(List<Transaction> transactions, String today) {
  final past = transactions.where((t) => t.date.compareTo(today) <= 0).toList();
  if (past.isEmpty) return null;
  final first = past.map((t) => t.date).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  final basisDays = daysBetween(first, today).clamp(0, _forecastWindow);
  if (basisDays < _forecastMinDays) return null;

  final month = monthOf(today);
  final recurringOut = detectRecurring(past, today, TxType.expense);
  final recurringIn = detectRecurring(past, today, TxType.income);
  final fixed = recurringOut.map((r) => r.normTitle).toSet();

  final thisMonth = past.where((t) => monthOf(t.date) == month);
  final spent = thisMonth.where((t) => t.isExpense).fold(0, (sum, t) => sum + t.amount);
  final earned = thisMonth.where((t) => !t.isExpense).fold(0, (sum, t) => sum + t.amount);

  final windowStart = addDays(today, -basisDays);
  final variable = past
      .where((t) =>
          t.isExpense &&
          t.date.compareTo(windowStart) >= 0 &&
          t.date.compareTo(today) < 0 &&
          !fixed.contains(normalizeTitle(t.title)))
      .fold(0, (sum, t) => sum + t.amount);
  final remainingDays = daysInMonth(month) - dayOf(today);
  final expectedVariable = variable * remainingDays ~/ basisDays;

  int pending(List<Recurring> items) => items
      .where((r) => !r.paidThisMonth && monthOf(r.nextDate) == month)
      .fold(0, (sum, r) => sum + r.amount);

  final projected = spent + pending(recurringOut) + expectedVariable;
  final income = earned + pending(recurringIn);
  return Forecast(
    spent: spent,
    projected: projected,
    income: income,
    balance: income - projected,
    basisDays: basisDays,
  );
}

/// When a goal will be reached at the recent saving rate.
class GoalEstimate {
  const GoalEstimate({required this.month, required this.monthlySaving});

  /// YYYY-MM.
  final String month;
  final int monthlySaving;
}

/// Averages income minus spending over the last three finished months that
/// have data. Returns null when there is no history or nothing is left over.
GoalEstimate? estimateGoal(
  SavingsGoal goal,
  List<Transaction> transactions,
  String today,
) {
  if (goal.reached) return null;
  final month = monthOf(today);
  final nets = <int>[];
  for (var i = 1; i <= 3; i++) {
    final items = transactions.where((t) => monthOf(t.date) == addMonths(month, -i));
    if (items.isEmpty) continue;
    nets.add(items.fold(0, (sum, t) => sum + (t.isExpense ? -t.amount : t.amount)));
  }
  if (nets.isEmpty) return null;
  final monthly = nets.reduce((a, b) => a + b) ~/ nets.length;
  if (monthly <= 0) return null;
  final months = (goal.remaining + monthly - 1) ~/ monthly;
  if (months > 600) return null;
  return GoalEstimate(month: addMonths(month, months), monthlySaving: monthly);
}

class _Context {
  _Context(this.data, this.today)
      : transactions = data.transactions,
        month = monthOf(today),
        recurring = detectRecurring(data.transactions, today, TxType.expense);

  final AppData data;
  final List<Transaction> transactions;
  final String today;
  final String month;
  final List<Recurring> recurring;

  int spentIn(Category category, String month, {int? throughDay}) => transactions
      .where((t) =>
          t.isExpense &&
          t.category == category &&
          monthOf(t.date) == month &&
          (throughDay == null || dayOf(t.date) <= throughDay))
      .fold(0, (sum, t) => sum + t.amount);
}

typedef _Rule = List<Insight> Function(_Context ctx);

List<Insight> _subscriptions(_Context ctx) => [
      for (final r in ctx.recurring)
        // Accepting recategorizes the title, which is what silences this rule.
        if (!const {Category.abonelik, Category.ev, Category.fatura}.contains(r.category))
          Insight(
            key: 'subscription:${r.normTitle}',
            kind: InsightKind.subscription,
            title: '“${r.title}” abonelik gibi görünüyor',
            reason:
                '${r.months} aydır her ayın ${r.day}. günü civarında ${formatMoney(r.amount)} ödüyorsun.',
            actionLabel: 'Abonelik olarak işaretle',
            action: CategorizeAction(r.normTitle, Category.abonelik),
            score: 60,
            snoozeDays: 30,
          ),
    ];

List<Insight> _forecast(_Context ctx) {
  final forecast = forecastMonth(ctx.transactions, ctx.today);
  if (forecast == null || forecast.balance >= 0) return [];
  return [
    Insight(
      key: 'forecast:${ctx.month}',
      kind: InsightKind.forecast,
      title: 'Ay sonunda eksiye düşebilirsin',
      reason:
          'Bu gidişle ${formatMoney(forecast.projected)} harcayacaksın, beklenen gelirin ${formatMoney(forecast.income)}. Tahmin son ${forecast.basisDays} güne dayanıyor.',
      score: 90,
      snoozeDays: 7,
    ),
  ];
}

const _increaseMinDay = 5;
const _increaseMinAmount = 50000;

int _roundUpToHundredLira(int amount) => ((amount + 9999) ~/ 10000) * 10000;

List<Insight> _increase(_Context ctx) {
  final day = dayOf(ctx.today);
  if (day < _increaseMinDay) return [];
  final previous = [for (var i = 1; i <= 3; i++) addMonths(ctx.month, -i)];

  final insights = <Insight>[];
  for (final category in Category.expenses) {
    final current = ctx.spentIn(category, ctx.month, throughDay: day);
    final earlier = [
      for (final m in previous) ctx.spentIn(category, m, throughDay: day),
    ];
    if (earlier.any((amount) => amount == 0)) continue;
    final average = earlier.reduce((a, b) => a + b) ~/ earlier.length;
    final grewEnough = current * 100 >= average * 125 &&
        current - average >= _increaseMinAmount;
    if (!grewEnough) continue;

    final hasLimit = ctx.data.limits.containsKey(category);
    final fullMonths = previous.map((m) => ctx.spentIn(category, m)).toList();
    final suggested = _roundUpToHundredLira(
      fullMonths.reduce((a, b) => a + b) ~/ fullMonths.length,
    );
    final percent = ((current - average) * 100 / average).round();
    insights.add(Insight(
      key: 'increase:${category.name}:${ctx.month}',
      kind: InsightKind.increase,
      title: '${category.label} harcaman %$percent arttı',
      reason:
          'Ayın ilk $day gününde ${formatMoney(current)} harcadın. Önceki 3 ayın aynı döneminde ortalama ${formatMoney(average)} idi.',
      actionLabel: hasLimit ? null : '${formatMoney(suggested)} limit koy',
      action: hasLimit ? null : SetLimitAction(category, suggested),
      score: 70 + (percent > 100 ? 15 : percent * 0.15),
      snoozeDays: 7,
    ));
  }
  return insights;
}

List<Insight> _limits(_Context ctx) {
  final insights = <Insight>[];
  final daysLeft = daysInMonth(ctx.month) - dayOf(ctx.today) + 1;
  ctx.data.limits.forEach((category, limit) {
    final spent = ctx.spentIn(category, ctx.month);
    if (spent >= limit) {
      insights.add(Insight(
        key: 'limit:${category.name}:${ctx.month}:over',
        kind: InsightKind.limit,
        title: '${category.label} limitini aştın',
        reason:
            '${formatMoney(limit)} limitin var, bu ay ${formatMoney(spent)} harcadın.',
        score: 95,
        snoozeDays: 30,
      ));
    } else if (spent * 100 >= limit * 80) {
      final left = limit - spent;
      insights.add(Insight(
        key: 'limit:${category.name}:${ctx.month}:near',
        kind: InsightKind.limit,
        title: '${category.label} limitine yaklaştın',
        reason:
            'Kalan ${formatMoney(left)}. Ay sonuna kadar günde ${formatMoney(left ~/ daysLeft)} harcayabilirsin.',
        score: 85,
        snoozeDays: 30,
      ));
    }
  });
  return insights;
}

List<Insight> _unusual(_Context ctx) {
  final recent = addDays(ctx.today, -7);
  final since = addDays(ctx.today, -90);
  final fixed = ctx.recurring.map((r) => r.normTitle).toSet();

  final insights = <Insight>[];
  for (final tx in ctx.transactions) {
    if (!tx.isExpense ||
        tx.date.compareTo(recent) < 0 ||
        tx.date.compareTo(ctx.today) > 0 ||
        fixed.contains(normalizeTitle(tx.title))) {
      continue;
    }
    final samples = ctx.transactions
        .where((t) =>
            t.isExpense &&
            t.id != tx.id &&
            t.category == tx.category &&
            t.date.compareTo(since) >= 0 &&
            t.date.compareTo(ctx.today) <= 0)
        .map((t) => t.amount)
        .toList();
    if (samples.length < 5) continue;
    final median = _median(samples);
    if (tx.amount <= median * 3) continue;
    insights.add(Insight(
      key: 'unusual:${tx.id}',
      kind: InsightKind.unusual,
      title: '“${tx.title}” alışılmışın dışında',
      reason:
          '${tx.category.label} harcamaların genelde ${formatMoney(median)} civarında, bu ${formatMoney(tx.amount)}.',
      score: 55,
      snoozeDays: 30,
    ));
  }
  return insights;
}

List<Insight> _upcoming(_Context ctx) {
  final horizon = addDays(ctx.today, 7);
  // Paying next month's bill now would put two payments in this month and
  // break the one-a-month pattern, so the button waits for the right month.
  bool payable(Recurring r) => !r.paidThisMonth && monthOf(r.nextDate) == ctx.month;
  return [
    for (final r in ctx.recurring)
      if (r.nextDate.compareTo(horizon) <= 0)
        Insight(
          key: 'upcoming:${r.normTitle}:${r.nextDate}',
          kind: InsightKind.upcoming,
          title: '“${r.title}” ödemesi yaklaşıyor',
          reason:
              '${relativeDay(r.nextDate, ctx.today)} yaklaşık ${formatMoney(r.amount)} çıkacak. ${r.months} aydır düzenli ödüyorsun.',
          actionLabel: payable(r) ? 'Ödedim' : null,
          action: payable(r) ? PayAction(r.title, r.amount, r.category) : null,
          score: 50,
          snoozeDays: 8,
        ),
  ];
}

const List<_Rule> _rules = [
  _limits,
  _forecast,
  _increase,
  _subscriptions,
  _unusual,
  _upcoming,
];

/// 0.5 for a kind the user always rejects, 1.5 for one they always accept.
double _feedbackWeight(InsightKind kind, Map<String, FeedbackCount> feedback) {
  final count = feedback[kind.name] ?? const FeedbackCount();
  return 0.5 + (count.accepted + 1) / (count.accepted + count.dismissed + 2);
}

List<Insight> buildInsights(AppData data, String today) {
  final ctx = _Context(data, today);
  final scored = [
    for (final rule in _rules)
      for (final insight in rule(ctx))
        if ((data.dismissed[insight.key] ?? '').compareTo(today) <= 0)
          (insight, insight.score * _feedbackWeight(insight.kind, data.feedback)),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  final ranked = scored.map((e) => e.$1).toList();

  // The best card of each kind goes first, so one kind cannot crowd out the
  // others. Remaining slots then go to the highest scores.
  final picked = <Insight>[];
  final perKind = <InsightKind, int>{};
  void pick(Insight insight) {
    if (picked.length >= _maxVisible || picked.contains(insight)) return;
    if ((perKind[insight.kind] ?? 0) >= _maxPerKind) return;
    perKind[insight.kind] = (perKind[insight.kind] ?? 0) + 1;
    picked.add(insight);
  }

  for (final insight in ranked) {
    if (!perKind.containsKey(insight.kind)) pick(insight);
  }
  ranked.forEach(pick);
  picked.sort((a, b) => ranked.indexOf(a).compareTo(ranked.indexOf(b)));
  return picked;
}
