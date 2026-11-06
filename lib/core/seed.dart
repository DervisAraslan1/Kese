import 'date.dart';
import 'models.dart';

/// Small deterministic generator: the demo looks the same on every start.
class _Rng {
  _Rng(this._state);
  int _state;

  int next(int bound) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return (_state >> 8) % bound;
  }

  int between(int low, int high) => low + next(high - low + 1);
}

/// Six months of made-up history ending today, shaped so that every kind of
/// insight has something to say.
List<Transaction> buildDemoTransactions(String today) {
  final rng = _Rng(20261106);
  final month = monthOf(today);
  final out = <Transaction>[];
  var serial = 0;

  void add(
    String date,
    String title,
    int lira,
    Category category, [
    TxType type = TxType.expense,
  ]) {
    if (date.compareTo(today) > 0) return;
    out.add(Transaction(
      id: 'demo-${++serial}',
      type: type,
      amount: lira * 100,
      title: title,
      category: category,
      date: date,
      createdAt: '${date}T12:00:00.000',
    ));
  }

  for (var back = 6; back >= 0; back--) {
    final m = addMonths(month, -back);
    final isCurrent = back == 0;

    add(dayInMonth(m, 1), 'Maaş', 62000, Category.gelir, TxType.income);
    add(dayInMonth(m, 3), 'Kira', 21000, Category.ev);
    add(dayInMonth(m, 4), 'Aidat', 1800, Category.ev);
    add(dayInMonth(m, 8), 'Netflix', 230, Category.diger);
    add(dayInMonth(m, 12), 'Spotify', 100, Category.diger);
    add(dayInMonth(m, 15), 'Elektrik faturası', rng.between(780, 900), Category.fatura);
    add(dayInMonth(m, 20), 'İnternet faturası', 650, Category.fatura);
    add(dayInMonth(m, 26), 'Telefon faturası', 520, Category.fatura);

    final days = daysInMonth(m);
    for (var day = 1; day <= days; day++) {
      final date = dayInMonth(m, day);
      if (rng.next(3) == 0) {
        add(date, rng.next(2) == 0 ? 'Market' : 'Migros', rng.between(300, 950), Category.market);
      }
      if (rng.next(isCurrent ? 2 : 4) == 0) {
        add(
          date,
          rng.next(2) == 0 ? 'Öğle yemeği' : 'Kahve',
          isCurrent ? rng.between(260, 520) : rng.between(120, 320),
          Category.yemek,
        );
      }
      if (rng.next(4) == 0) {
        add(date, rng.next(2) == 0 ? 'Metro kart' : 'Taksi', rng.between(80, 260), Category.ulasim);
      }
      if (rng.next(12) == 0) {
        add(date, 'Sinema', rng.between(220, 480), Category.eglence);
      }
      if (rng.next(20) == 0) {
        add(date, 'Eczane', rng.between(150, 420), Category.saglik);
      }
    }
  }

  add(addDays(today, -2), 'Kulaklık', 4800, Category.eglence);
  return out;
}
