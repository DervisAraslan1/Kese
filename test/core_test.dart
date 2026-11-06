import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/date.dart';
import 'package:kese/core/insights.dart';
import 'package:kese/core/models.dart';
import 'package:kese/core/money.dart';
import 'package:kese/core/parse.dart';
import 'package:kese/core/seed.dart';
import 'package:kese/core/store.dart';

const today = '2026-11-18'; // Wednesday

class MemoryPersistence implements Persistence {
  MemoryPersistence([this.contents]);

  String? contents;
  String? quarantined;
  bool failWrites = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw Exception('disk full');
    contents = value;
  }

  @override
  Future<void> quarantine(String value) async => quarantined = value;
}

var _serial = 0;

Transaction tx(
  String date,
  String title,
  int lira, {
  Category category = Category.diger,
  TxType type = TxType.expense,
}) =>
    Transaction(
      id: 't${++_serial}',
      type: type,
      amount: lira * 100,
      title: title,
      category: category,
      date: date,
      createdAt: '${date}T10:00:00.000',
    );

/// One payment a month, for [count] months up to and including [lastMonth].
List<Transaction> monthly(
  String title,
  int lira,
  int day,
  int count, {
  String lastMonth = '2026-11',
  Category category = Category.diger,
  TxType type = TxType.expense,
}) =>
    [
      for (var i = 0; i < count; i++)
        tx(dayInMonth(addMonths(lastMonth, -i), day), title, lira,
            category: category, type: type),
    ];

Store storeWith(List<Transaction> transactions, [MemoryPersistence? persistence]) {
  final store = Store(
    persistence ?? MemoryPersistence(),
    clock: () => DateTime(2026, 11, 18, 12),
  );
  store.data.transactions = transactions;
  store.data.onboarded = true;
  return store;
}

ParsedEntry entry(String input, [List<Transaction> history = const []]) =>
    parseEntry(input, today, history).entry!;

void main() {
  group('date', () {
    test('validates real calendar days', () {
      expect(isDateKey('2026-02-28'), isTrue);
      expect(isDateKey('2026-02-31'), isFalse);
      expect(isDateKey('2026-2-3'), isFalse);
    });

    test('moves a day past the end of a short month back', () {
      expect(dayInMonth('2026-02', 31), '2026-02-28');
      expect(dayInMonth('2028-02', 31), '2028-02-29');
    });

    test('crosses year boundaries', () {
      expect(addMonths('2026-01', -1), '2025-12');
      expect(addDays('2026-12-31', 1), '2027-01-01');
    });

    test('counts days across a daylight saving change', () {
      expect(daysBetween('2026-03-01', '2026-04-01'), 31);
    });
  });

  group('money', () {
    test('reads Turkish formats into kuruş', () {
      expect(parseAmount('340'), 34000);
      expect(parseAmount('12.500'), 1250000);
      expect(parseAmount('12,5'), 1250);
      expect(parseAmount('229,99'), 22999);
      expect(parseAmount('1.250,75'), 125075);
      expect(parseAmount('1.000.000'), 100000000);
      expect(parseAmount('12.5'), 1250);
    });

    test('refuses to guess at ambiguous or malformed input', () {
      for (final input in ['1,250', '12.34.56', '1.25.000', ',5', 'abc', '', '1,2,3']) {
        expect(parseAmount(input), isNull, reason: input);
      }
    });

    test('refuses amounts too large to be real', () {
      expect(parseAmount('999999999999'), isNull);
    });

    test('does not lose kuruş to floating point', () {
      expect(parseAmount('0,07'), 7);
      expect(parseAmount('1,10'), 110);
      expect(parseAmount('19,99')! * 3, 5997);
    });

    test('formats with Turkish separators', () {
      expect(formatMoney(125075), '1.250,75 ₺');
      expect(formatMoney(125000), '1.250 ₺');
      expect(formatMoney(5), '0,05 ₺');
      expect(formatMoney(-34000), '-340 ₺');
      expect(formatMoney(100000000), '1.000.000 ₺');
    });

    test('round-trips through the edit field', () {
      for (final amount in [1, 110, 125075, 100000]) {
        expect(parseAmount(amountForInput(amount)), amount);
      }
    });
  });

  group('parse', () {
    test('reads the documented examples', () {
      final market = entry('market 340 tl');
      expect(market.title, 'market');
      expect(market.amount, 34000);
      expect(market.category, Category.market);
      expect(market.type, TxType.expense);
      expect(market.date, today);

      final rent = entry('dün kira 12.500 #ev');
      expect(rent.title, 'kira');
      expect(rent.amount, 1250000);
      expect(rent.category, Category.ev);
      expect(rent.date, '2026-11-17');

      final salary = entry('maaş +45.000');
      expect(salary.type, TxType.income);
      expect(salary.category, Category.gelir);
      expect(salary.amount, 4500000);

      final netflix = entry('netflix 229,99');
      expect(netflix.category, Category.abonelik);
      expect(netflix.amount, 22999);
    });

    test('accepts currency written in different ways', () {
      expect(entry('kahve 85tl').amount, 8500);
      expect(entry('kahve 85₺').amount, 8500);
      expect(entry('kahve ₺85').amount, 8500);
      expect(entry('kahve 85 lira').amount, 8500);
      expect(entry('kahve 85 lira').title, 'kahve');
    });

    test('prefers the amount with a currency over other numbers', () {
      final apples = entry('3 kg elma 120 tl');
      expect(apples.amount, 12000);
      expect(apples.title, '3 kg elma');
    });

    test('uses the last number when none has a currency', () {
      final apples = entry('3 kg elma 120');
      expect(apples.amount, 12000);
      expect(apples.title, '3 kg elma');
    });

    test('does not mistake digits inside a word for an amount', () {
      final shop = entry('a101 250');
      expect(shop.title, 'a101');
      expect(shop.amount, 25000);
      expect(shop.category, Category.market);
    });

    test('resolves weekdays to the most recent past one', () {
      expect(entry('pazartesi market 100').date, '2026-11-16');
      expect(entry('cuma günü market 100').date, '2026-11-13');
      expect(entry('cumartesi market 100').date, '2026-11-14');
      expect(entry('pazar market 100').date, '2026-11-15');
      // Today is Wednesday, so "çarşamba" is last week's.
      expect(entry('çarşamba market 100').date, '2026-11-11');
      expect(entry('evvelsi gün market 100').date, '2026-11-16');
    });

    test('matches suffixed words', () {
      expect(entry('marketten alışveriş 200').category, Category.market);
      expect(entry('kiranın kalanı 2000').category, Category.ev);
    });

    test('specific categories win over general ones', () {
      expect(entry('netflix faturası 230').category, Category.abonelik);
      expect(entry('fatura öde 500').category, Category.fatura);
    });

    test('handles Turkish capitals', () {
      expect(normalizeTitle('  KIRA  İade '), 'kıra iade');
      expect(entry('MARKET 100').category, Category.market);
      expect(entry('İADE 100').type, TxType.income);
    });

    test('prefers the user history over keywords', () {
      final history = [tx('2026-11-01', 'Market', 100, category: Category.ev)];
      expect(entry('market 340', history).category, Category.ev);
    });

    test('a tag beats history', () {
      final history = [tx('2026-11-01', 'Market', 100, category: Category.ev)];
      expect(entry('market 340 #yemek', history).category, Category.yemek);
    });

    test('leaves unknown tags in the title', () {
      expect(entry('kahve #sabah 50').title, 'kahve #sabah');
    });

    test('explains failures instead of saving something wrong', () {
      expect(parseEntry('market', today).error, contains('Tutarı'));
      expect(parseEntry('', today).error, isNotNull);
      expect(parseEntry('340 tl', today).error, contains('Ne için'));
      expect(parseEntry('market 0', today).error, contains('sıfır'));
      expect(parseEntry('market 1,250', today).error, contains('anlayamadım'));
    });
  });

  group('recurring detection', () {
    test('finds a monthly payment and its next date', () {
      final found = detectRecurring(monthly('Netflix', 230, 8, 4), today, TxType.expense);
      expect(found.single.title, 'Netflix');
      expect(found.single.months, 4);
      expect(found.single.paidThisMonth, isTrue);
      expect(found.single.nextDate, '2026-12-08');
    });

    test('expects an unpaid one later this month', () {
      final found = detectRecurring(
        monthly('Kira', 21000, 25, 3, lastMonth: '2026-10'),
        today,
        TxType.expense,
      );
      expect(found.single.paidThisMonth, isFalse);
      expect(found.single.nextDate, '2026-11-25');
    });

    test('never places the next date in the past', () {
      final found = detectRecurring(
        monthly('Kira', 21000, 5, 3, lastMonth: '2026-10'),
        today,
        TxType.expense,
      );
      expect(found.single.nextDate, today);
    });

    test('needs three months', () {
      expect(detectRecurring(monthly('Netflix', 230, 8, 2), today, TxType.expense), isEmpty);
    });

    test('ignores cancelled subscriptions', () {
      final old = monthly('Netflix', 230, 8, 5, lastMonth: '2026-08');
      expect(detectRecurring(old, today, TxType.expense), isEmpty);
    });

    test('ignores a gap in the run', () {
      final items = [
        tx('2026-11-08', 'Netflix', 230),
        tx('2026-10-08', 'Netflix', 230),
        tx('2026-08-08', 'Netflix', 230),
      ];
      expect(detectRecurring(items, today, TxType.expense), isEmpty);
    });

    test('ignores titles paid many times a month', () {
      final items = [
        ...monthly('Market', 400, 8, 4),
        ...monthly('Market', 400, 20, 4, lastMonth: '2026-10'),
      ];
      expect(detectRecurring(items, today, TxType.expense), isEmpty);
    });

    test('ignores amounts that vary too much', () {
      final items = [
        tx('2026-11-08', 'Hediye', 100),
        tx('2026-10-08', 'Hediye', 500),
        tx('2026-09-08', 'Hediye', 900),
      ];
      expect(detectRecurring(items, today, TxType.expense), isEmpty);
    });

    test('ignores future entries', () {
      final items = monthly('Netflix', 230, 8, 3, lastMonth: '2027-01');
      expect(detectRecurring(items, today, TxType.expense), isEmpty);
    });
  });

  group('forecast', () {
    test('needs two weeks of history', () {
      expect(forecastMonth([tx('2026-11-10', 'Kahve', 50)], today), isNull);
      expect(forecastMonth([], today), isNull);
    });

    test('adds variable spending and pending payments', () {
      final items = [
        tx('2026-09-19', 'Eski', 1),
        for (var i = 1; i <= 30; i++) tx(addDays(today, -i), 'Kahve $i', 10),
        ...monthly('Kira', 1000, 25, 3, lastMonth: '2026-10', category: Category.ev),
      ];
      final forecast = forecastMonth(items, today)!;
      final spent = items
          .where((t) => monthOf(t.date) == '2026-11')
          .fold(0, (sum, t) => sum + t.amount);
      expect(forecast.spent, spent);
      expect(forecast.basisDays, 85);
      // 301 TL of variable spending over 85 days, projected over 12 days, plus rent.
      expect(forecast.projected, spent + 100000 + 30100 * 12 ~/ 85);
    });

    test('counts income that is still expected', () {
      final items = monthly('Maaş', 50000, 25, 4,
          lastMonth: '2026-10', category: Category.gelir, type: TxType.income);
      expect(forecastMonth(items, today)!.income, 5000000);
    });
  });

  group('insights', () {
    Insight? find(Store store, InsightKind kind) {
      final found = buildInsights(store.data, store.today).where((i) => i.kind == kind);
      return found.isEmpty ? null : found.first;
    }

    test('stays quiet with no data', () {
      expect(buildInsights(AppData(), today), isEmpty);
    });

    test('marks a repeating payment as a subscription', () {
      final store = storeWith(monthly('Netflix', 230, 8, 4));
      final insight = find(store, InsightKind.subscription)!;
      expect(insight.reason, contains('230 ₺'));
    });

    test('rent and bills are not called subscriptions', () {
      final store = storeWith(monthly('Kira', 21000, 3, 4, category: Category.ev));
      expect(find(store, InsightKind.subscription), isNull);
    });

    test('regression: an accepted subscription does not come back', () {
      final store = storeWith(monthly('Netflix', 230, 8, 4));
      store.acceptInsight(find(store, InsightKind.subscription)!);
      expect(find(store, InsightKind.subscription), isNull);
      expect(store.transactions.every((t) => t.category == Category.abonelik), isTrue);
    });

    test('regression: an accepted limit does not stack', () {
      final items = [
        for (final m in ['2026-08', '2026-09', '2026-10'])
          tx('$m-05', 'Öğle $m', 1000, category: Category.yemek),
        tx('2026-11-05', 'Öğle', 3000, category: Category.yemek),
      ];
      final store = storeWith(items);
      final first = find(store, InsightKind.increase)!;
      expect(first.action, isA<SetLimitAction>());
      store.acceptInsight(first);
      expect(store.data.limits[Category.yemek], 100000);

      final again = find(store, InsightKind.increase)!;
      expect(again.action, isNull, reason: 'the limit already exists');
      expect(again.actionLabel, isNull);
    });

    test('compares the same part of each month', () {
      final items = [
        for (final m in ['2026-08', '2026-09', '2026-10']) ...[
          tx('$m-05', 'A', 1000, category: Category.yemek),
          // Late-month spending must not count against mid-November.
          tx('$m-28', 'B', 9000, category: Category.yemek),
        ],
        tx('2026-11-05', 'C', 2000, category: Category.yemek),
      ];
      final insight = find(storeWith(items), InsightKind.increase)!;
      expect(insight.title, contains('%100'));
    });

    test('ignores increases too small to matter', () {
      final items = [
        for (final m in ['2026-08', '2026-09', '2026-10'])
          tx('$m-05', 'A', 100, category: Category.yemek),
        tx('2026-11-05', 'C', 200, category: Category.yemek),
      ];
      expect(find(storeWith(items), InsightKind.increase), isNull);
    });

    test('warns near and over a limit', () {
      final store = storeWith([tx('2026-11-05', 'A', 850, category: Category.yemek)]);
      store.data.limits[Category.yemek] = 100000;
      expect(find(store, InsightKind.limit)!.title, contains('yaklaştın'));
      // 150 TL left over the 13 days remaining, today included.
      expect(find(store, InsightKind.limit)!.reason, contains('11,53 ₺'));

      store.data.limits[Category.yemek] = 80000;
      expect(find(store, InsightKind.limit)!.title, contains('aştın'));
    });

    test('flags an unusually large expense', () {
      final items = [
        for (var i = 10; i < 16; i++)
          tx(addDays(today, -i), 'Bilet $i', 200, category: Category.eglence),
        tx(addDays(today, -1), 'Konser', 900, category: Category.eglence),
      ];
      expect(find(storeWith(items), InsightKind.unusual)!.title, contains('Konser'));
    });

    test('needs enough samples before calling anything unusual', () {
      final items = [
        tx(addDays(today, -10), 'Bilet', 200, category: Category.eglence),
        tx(addDays(today, -1), 'Konser', 900, category: Category.eglence),
      ];
      expect(find(storeWith(items), InsightKind.unusual), isNull);
    });

    test('announces a payment due within a week', () {
      final soon = storeWith(monthly('Kira', 21000, 22, 3, lastMonth: '2026-10', category: Category.ev));
      expect(find(soon, InsightKind.upcoming), isNotNull);

      final later = storeWith(monthly('Kira', 21000, 28, 3, lastMonth: '2026-10', category: Category.ev));
      expect(find(later, InsightKind.upcoming), isNull);
    });

    test('warns when the month will end negative', () {
      final items = [
        tx(addDays(today, -30), 'Maaş', 1000, category: Category.gelir, type: TxType.income),
        tx('2026-11-02', 'Tatil', 9000),
      ];
      expect(find(storeWith(items), InsightKind.forecast), isNotNull);
    });

    test('a dismissal lasts its snooze and counts as feedback', () {
      final store = storeWith(monthly('Netflix', 230, 8, 4));
      final insight = find(store, InsightKind.subscription)!;
      store.dismissInsight(insight);
      expect(find(store, InsightKind.subscription), isNull);
      expect(store.data.feedback['subscription']!.dismissed, 1);
      expect(buildInsights(store.data, addDays(today, 29)).map((i) => i.key),
          isNot(contains(insight.key)));
      expect(buildInsights(store.data, addDays(today, 30)).map((i) => i.key),
          contains(insight.key));
    });

    test('rejected kinds sink below accepted ones', () {
      final store = storeWith([
        ...monthly('Netflix', 230, 8, 4),
        tx('2026-11-01', 'Maaş', 90000, category: Category.gelir, type: TxType.income),
        for (final m in ['2026-08', '2026-09', '2026-10'])
          tx('$m-05', 'Öğle $m', 1000, category: Category.yemek),
        tx('2026-11-05', 'Öğle', 3000, category: Category.yemek),
      ]);
      expect(buildInsights(store.data, today).first.kind, InsightKind.increase);
      store.data.feedback = {
        'increase': const FeedbackCount(dismissed: 20),
        'subscription': const FeedbackCount(accepted: 20),
      };
      expect(buildInsights(store.data, today).first.kind, InsightKind.subscription);
    });

    test('one kind cannot fill every slot', () {
      final store = storeWith(buildDemoTransactions(today));
      final kinds = buildInsights(store.data, today).map((i) => i.kind).toList();
      for (final kind in kinds) {
        expect(kinds.where((k) => k == kind).length, lessThanOrEqualTo(2));
      }
    });

    test('shows at most four', () {
      final store = storeWith(buildDemoTransactions(today));
      expect(buildInsights(store.data, today).length, lessThanOrEqualTo(4));
    });

    test('the demo produces several kinds', () {
      final store = storeWith(buildDemoTransactions(today));
      final kinds = buildInsights(store.data, today).map((i) => i.kind).toSet();
      expect(kinds.length, greaterThanOrEqualTo(3));
    });

    test('the demo works on every day of a year', () {
      for (var day = '2026-01-01'; day.compareTo('2027-01-01') < 0; day = addDays(day, 1)) {
        final data = AppData(transactions: buildDemoTransactions(day));
        expect(() => buildInsights(data, day), returnsNormally, reason: day);
        expect(data.transactions.every((t) => t.date.compareTo(day) <= 0), isTrue);
      }
    });
  });

  group('store', () {
    test('saves and reloads', () async {
      final disk = MemoryPersistence();
      final store = storeWith([], disk);
      store.add(entry('market 340 tl'));
      store.setLimit(Category.market, 500000);
      await store.flush();

      final reloaded = Store(disk);
      await reloaded.load();
      expect(reloaded.transactions.single.title, 'market');
      expect(reloaded.data.limits[Category.market], 500000);
      expect(reloaded.data.onboarded, isTrue);
    });

    test('keeps unreadable data aside', () async {
      final disk = MemoryPersistence('{bozuk');
      final store = Store(disk);
      await store.load();
      expect(store.recovered, isTrue);
      expect(disk.quarantined, '{bozuk');
      expect(store.transactions, isEmpty);
    });

    test('reports a failed save', () async {
      final disk = MemoryPersistence()..failWrites = true;
      final store = storeWith([], disk);
      store.add(entry('market 340 tl'));
      await store.flush();
      expect(store.saveError.value, isNotNull);
    });

    test('writes saves in order', () async {
      final disk = MemoryPersistence();
      final store = storeWith([], disk);
      for (var i = 1; i <= 20; i++) {
        store.add(entry('kahve $i'));
      }
      await store.flush();
      final saved = jsonDecode(disk.contents!) as Map;
      expect((saved['transactions'] as List).length, 20);
    });

    test('forgets expired dismissals on load', () async {
      final disk = MemoryPersistence();
      final store = storeWith([], disk);
      store.data.dismissed = {'old': '2026-01-01', 'live': '2027-01-01'};
      store.add(entry('kahve 10'));
      await store.flush();

      final reloaded = Store(disk, clock: () => DateTime(2026, 11, 18));
      await reloaded.load();
      expect(reloaded.data.dismissed.keys, ['live']);
    });

    test('regression: undoing a delete keeps later changes', () {
      final store = storeWith([]);
      final first = store.add(entry('market 100'));
      final undo = store.delete(first.id)!;
      final second = store.add(entry('kahve 50'));
      undo.revert();
      expect(store.transactions.map((t) => t.id), containsAll([first.id, second.id]));
    });

    test('regression: undoing an edit keeps later changes', () {
      final store = storeWith([]);
      final first = store.add(entry('market 100'));
      final undo = store.update(first.copyWith(amount: 99900))!;
      final second = store.add(entry('kahve 50'));
      undo.revert();
      expect(store.transactions.firstWhere((t) => t.id == first.id).amount, 10000);
      expect(store.transactions.any((t) => t.id == second.id), isTrue);
    });

    test('undoing twice does not duplicate', () {
      final store = storeWith([]);
      final first = store.add(entry('market 100'));
      final undo = store.delete(first.id)!;
      undo.revert();
      undo.revert();
      expect(store.transactions.length, 1);
    });

    test('regression: undoing an insight also undoes its feedback', () {
      final store = storeWith(monthly('Netflix', 230, 8, 4));
      final insight = buildInsights(store.data, store.today)
          .firstWhere((i) => i.kind == InsightKind.subscription);
      final undo = store.acceptInsight(insight);
      undo.revert();
      expect(store.data.feedback['subscription']!.accepted, 0);
      expect(store.transactions.every((t) => t.category == Category.diger), isTrue);
    });

    test('undoing a limit restores the previous value', () {
      final store = storeWith([])..setLimit(Category.yemek, 5000);
      const insight = Insight(
        key: 'k',
        kind: InsightKind.increase,
        title: '',
        reason: '',
        score: 1,
        snoozeDays: 1,
        action: SetLimitAction(Category.yemek, 9000),
      );
      final undo = store.acceptInsight(insight);
      expect(store.data.limits[Category.yemek], 9000);
      undo.revert();
      expect(store.data.limits[Category.yemek], 5000);
    });

    test('startEmpty clears everything but the theme', () {
      final store = storeWith([tx(today, 'A', 1)])
        ..setTheme('kum')
        ..setLimit(Category.yemek, 100);
      store.startEmpty();
      expect(store.transactions, isEmpty);
      expect(store.data.limits, isEmpty);
      expect(store.data.theme, 'kum');
    });
  });

  group('backup', () {
    String backupWith(void Function(Map<String, dynamic>) change) {
      final store = storeWith([tx(today, 'Kahve', 50)]);
      final json = jsonDecode(store.exportBackup()) as Map<String, dynamic>;
      change(json);
      return jsonEncode(json);
    }

    void removeField(Map<String, dynamic> json, String field) =>
        (json['transactions'] as List).first.remove(field);

    void setField(Map<String, dynamic> json, String field, Object? value) =>
        (json['transactions'] as List).first[field] = value;

    test('round-trips everything', () {
      final source = storeWith([tx(today, 'Kahve', 50, category: Category.yemek)])
        ..setLimit(Category.yemek, 100000);
      final target = storeWith([]);
      target.importBackup(source.exportBackup());
      expect(target.transactions.single.title, 'Kahve');
      expect(target.transactions.single.category, Category.yemek);
      expect(target.data.limits[Category.yemek], 100000);
    });

    test('regression: rejects every incomplete or invalid record', () {
      final bad = <String, String>{
        'not json': 'merhaba',
        'not an object': '[]',
        'no version': backupWith((j) => j.remove('version')),
        'future version': backupWith((j) => j['version'] = 99),
        'no list': backupWith((j) => j.remove('transactions')),
        'missing id': backupWith((j) => removeField(j, 'id')),
        'missing type': backupWith((j) => removeField(j, 'type')),
        'missing category': backupWith((j) => removeField(j, 'category')),
        'missing date': backupWith((j) => removeField(j, 'date')),
        'unknown category': backupWith((j) => setField(j, 'category', 'yok')),
        'fractional amount': backupWith((j) => setField(j, 'amount', 12.5)),
        'negative amount': backupWith((j) => setField(j, 'amount', -5)),
        'zero amount': backupWith((j) => setField(j, 'amount', 0)),
        'impossible date': backupWith((j) => setField(j, 'date', '2026-02-31')),
        'blank title': backupWith((j) => setField(j, 'title', '  ')),
        'bad limit': backupWith((j) => j['limits'] = {'yemek': -1}),
        'unknown limit': backupWith((j) => j['limits'] = {'yok': 100}),
        'bad feedback': backupWith((j) => j['feedback'] = {'x': 'y'}),
        'bad dismissal': backupWith((j) => j['dismissed'] = {'x': 'dün'}),
        'duplicate ids': backupWith((j) {
          final list = j['transactions'] as List;
          list.add(list.first);
        }),
      };

      bad.forEach((name, contents) {
        final store = storeWith([tx(today, 'Mevcut', 10)]);
        expect(() => store.importBackup(contents), throwsFormatException, reason: name);
        expect(store.transactions.single.title, 'Mevcut', reason: name);
      });
    });

    test('import can be undone', () {
      final store = storeWith([tx(today, 'Mevcut', 10)]);
      final undo = store.importBackup(storeWith([tx(today, 'Yeni', 20)]).exportBackup());
      expect(store.transactions.single.title, 'Yeni');
      undo.revert();
      expect(store.transactions.single.title, 'Mevcut');
    });

    test('an import ends demo mode', () {
      final store = storeWith([])..startWithDemo();
      store.importBackup(storeWith([tx(today, 'Yeni', 20)]).exportBackup());
      expect(store.data.demo, isFalse);
    });
  });
}
