import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/date.dart';
import 'package:kese/core/insights.dart';
import 'package:kese/core/kese.dart';
import 'package:kese/core/models.dart';
import 'package:kese/core/parse.dart';
import 'package:kese/core/plans.dart';
import 'package:kese/core/reminders.dart';
import 'package:kese/core/store.dart';

import 'core_test.dart' show documentOf, monthly, storeWith, today, tx;

ParsedEntry _parse(String line) => parseEntry(line, today).entry!;
String? _error(String line) => parseEntry(line, today).error;

ParsedEntry _phone({int amount = 3000000, int count = 6, String date = today}) => ParsedEntry(
      type: TxType.expense,
      amount: amount,
      title: 'Telefon',
      category: Category.diger,
      date: date,
      installments: count,
    );

void main() {
  group('taksit yazımı', () {
    test('reads the total, not the installment count', () {
      final entry = _parse('telefon 30.000 6 taksit');
      expect(entry.amount, 3000000);
      expect(entry.installments, 6);
      expect(entry.title, 'telefon');
    });

    test('works in any order and joined', () {
      expect(_parse('6 taksit telefon 30.000 tl').installments, 6);
      expect(_parse('telefon 30.000 6taksit').installments, 6);
      expect(_parse('telefon 30.000 6 taksitle').installments, 6);
    });

    test('keeps day words and tags working', () {
      final entry = _parse('dün telefon 30.000 6 taksit #eğlence');
      expect(entry.date, addDays(today, -1));
      expect(entry.category, Category.eglence);
    });

    test('regression: a phone bought in installments is not a bill', () {
      expect(_parse('telefon 30.000 6 taksit').category, Category.diger);
      expect(_parse('telefon 30.000 6 taksit #fatura').category, Category.fatura);
      expect(_parse('telefon faturası 500').category, Category.fatura);
    });

    test('regression: a loan payment is one payment', () {
      final entry = _parse('araba taksiti 8.000');
      expect(entry.installments, 1);
      expect(entry.amount, 800000);
      expect(entry.title, 'araba taksiti');
    });

    test('refuses what cannot be a plan', () {
      expect(_error('telefon 30.000 1 taksit'), contains('arasında'));
      expect(_error('telefon 30.000 37 taksit'), contains('arasında'));
      expect(_error('maaş +45.000 3 taksit'), 'Gelir taksitlendirilemez.');
      expect(_error('sakız 0,01 3 taksit'), contains('bölünemez'));
      expect(_error('telefon 6 taksit'), contains('Tutarı bulamadım'));
    });
  });

  group('taksit bölme', () {
    test('parts always add up to the exact total', () {
      final parts = splitInstallments(_phone(amount: 1000000, count: 3));
      expect(parts.map((p) => p.amount), [333334, 333333, 333333]);
      expect(parts.fold(0, (sum, p) => sum + p.amount), 1000000);
    });

    test('a short month moves the day back and later months recover it', () {
      final parts = splitInstallments(_phone(count: 3, date: '2027-01-31'));
      expect(parts.map((p) => p.date), ['2027-01-31', '2027-02-28', '2027-03-31']);
    });

    test('runs across the new year', () {
      final parts = splitInstallments(_phone(count: 3, date: '2026-11-18'));
      expect(parts.last.date, '2027-01-18');
    });
  });

  group('taksit planı', () {
    test('counts each month in that month only', () {
      final store = storeWith([])..addInstallments(_phone());
      int spentIn(String month) => store.transactions
          .where((t) => monthOf(t.date) == month)
          .fold(0, (sum, t) => sum + t.amount);
      expect(store.transactions.length, 6);
      expect(spentIn('2026-11'), 500000);
      expect(spentIn('2027-04'), 500000);
    });

    test('undo removes every installment', () {
      final store = storeWith([tx(today, 'Market', 100)]);
      store.addInstallments(_phone()).revert();
      expect(store.transactions.single.title, 'Market');
    });

    test('tracks what is left', () {
      final store = storeWith([])..addInstallments(_phone(date: addDays(today, -35)));
      final plan = activePlans(store.transactions, today).single;
      expect(plan.done, 2);
      expect(plan.remaining, 2000000);
      expect(plan.next.date, '2026-12-14');
    });

    test('a finished plan leaves the active list', () {
      final store = storeWith([])..addInstallments(_phone(count: 2, date: '2026-01-05'));
      expect(activePlans(store.transactions, today), isEmpty);
    });

    test('deleting the rest keeps what was already due, and undo restores it', () {
      final store = storeWith([])..addInstallments(_phone(date: addDays(today, -35)));
      final id = store.transactions.first.planId!;
      final undo = store.deletePlan(id, onlyFuture: true)!;
      expect(store.transactions.length, 2);
      undo.revert();
      expect(store.transactions.length, 6);
    });

    test('deleting all removes the whole plan', () {
      final store = storeWith([])..addInstallments(_phone());
      store.deletePlan(store.transactions.first.planId!);
      expect(store.transactions, isEmpty);
    });
  });

  group('taksit ve öneriler', () {
    test('regression: installments are not a subscription', () {
      final store = storeWith([])..addInstallments(_phone(date: '2026-07-10'));
      expect(detectRecurring(store.transactions, today, TxType.expense), isEmpty);
    });

    test('regression: an installment is not unusual spending', () {
      final store = storeWith([
        for (var i = 1; i <= 8; i++) tx(addDays(today, -i * 3), 'Çay', 100),
      ])
        ..addInstallments(_phone());
      final kinds = buildInsights(store.data, today).map((i) => i.kind);
      expect(kinds, isNot(contains(InsightKind.unusual)));
    });

    test('forecast adds installments still due this month, once', () {
      final base = [
        for (var i = 1; i <= 30; i++) tx(addDays(today, -i), 'Yemek', 100),
      ];
      final without = forecastMonth(base, today)!;
      final store = storeWith(base)
        ..addInstallments(_phone(amount: 600000, count: 2, date: '2026-10-25'));
      final withPlan = forecastMonth(store.transactions, today)!;
      expect(withPlan.projected - without.projected, 300000);
    });

    test('a limit feels the installment', () {
      final store = storeWith([])
        ..setLimit(Category.diger, 400000)
        ..addInstallments(_phone());
      final limit = buildInsights(store.data, today)
          .firstWhere((i) => i.kind == InsightKind.limit);
      expect(limit.key, contains('over'));
    });
  });

  group('borç yazımı', () {
    test('a debt tag records a debt, never income', () {
      expect(_parse('ali 500 #alacak').debt, DebtKind.owed);
      expect(_parse('ayşe +500 #borç').debt, DebtKind.owe);
      expect(_parse('maaş 500 #borc').type, TxType.expense);
    });

    test('a debt cannot have installments', () {
      expect(_error('ali 600 3 taksit #borç'), contains('taksitlendirilemez'));
    });
  });

  group('borç', () {
    test('stays out of the budget', () {
      final store = storeWith([])..addDebt(DebtKind.owe, 'Ali', 100000);
      store.payDebt(store.data.debts.single.id, 40000);
      expect(store.transactions, isEmpty);
      expect(store.data.debts.single.remaining, 60000);
    });

    test('payments stay within the debt', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000).id;
      store.payDebt(id, 500000);
      expect(store.data.debts.single.settled, isTrue);
      expect(store.data.debts.single.paid, 100000);
      expect(store.payDebt(id, 100), isNull, reason: 'nothing left to pay');
      expect(store.payDebt(id, -5000), isNull);
    });

    test('a payment entered by mistake can be removed and brought back', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000).id;
      store.payDebt(id, 30000);
      final payment = store.data.debts.single.payments.single;
      final undo = store.removePayment(id, payment.id)!;
      expect(store.data.debts.single.paid, 0);
      undo.revert();
      expect(store.data.debts.single.paid, 30000);
    });

    test('undo reverts only the change it made', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000).id;
      final first = store.payDebt(id, 30000)!;
      store.payDebt(id, 20000);
      first.revert();
      expect(store.data.debts.single.paid, 20000);
    });

    test('the amount never drops below what was paid', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000).id;
      store.payDebt(id, 80000);
      store.updateDebt(id, kind: DebtKind.owed, title: 'Ali', amount: 50000, due: null);
      expect(store.data.debts.single.amount, 80000);
      expect(store.data.debts.single.settled, isTrue);
    });

    test('delete can be undone', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owe, 'Ali', 100000).id;
      store.deleteDebt(id)!.revert();
      expect(store.data.debts.length, 1);
    });

    test('warns near the due day and after it, not once settled', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owe, 'Ali', 100000, due: addDays(today, 3)).id;
      store.addDebt(DebtKind.owed, 'Veli', 100000, due: addDays(today, -2));
      store.addDebt(DebtKind.owe, 'Uzak', 100000, due: addDays(today, 30));
      Iterable<String> titles() => buildInsights(store.data, today)
          .where((i) => i.kind == InsightKind.debt)
          .map((i) => i.title);
      expect(titles(), ['“Veli” alacağı gecikti', '“Ali” borcu yaklaşıyor']);
      store.payDebt(id, 100000);
      expect(titles(), ['“Veli” alacağı gecikti']);
    });
  });

  group('kese', () {
    int month(Store s) => monthKese(s.data, today).kese;
    int overall(Store s) => overallKese(s.data, today).kese;

    test('a loan given leaves the kese and comes back when collected', () {
      final store = storeWith([tx(today, 'Maaş', 30000, type: TxType.income)]);
      expect(month(store), 3000000);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000).id;
      expect(month(store), 2900000);
      store.payDebt(id, 40000);
      expect(month(store), 2940000);
      store.payDebt(id, 60000);
      expect(month(store), 3000000);
    });

    test('a loan taken enters the kese only when ticked', () {
      final store = storeWith([]);
      store.addDebt(DebtKind.owe, 'Eski', 50000);
      expect(month(store), 0, reason: 'an old debt is already in the kese');
      final id = store.addDebt(DebtKind.owe, 'Veli', 100000, kese: true).id;
      expect(month(store), 100000);
      store.payDebt(id, 30000);
      expect(month(store), 70000);
    });

    test('an unticked payment is recorded but leaves the kese alone', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000, kese: false).id;
      store.payDebt(id, 100000, kese: false);
      expect(store.data.debts.single.settled, isTrue);
      expect(month(store), 0);
    });

    test('debts stay out of income, spending, categories and limits', () {
      final store = storeWith([tx(today, 'Market', 200, category: Category.market)])
        ..setLimit(Category.market, 100000);
      final id = store.addDebt(DebtKind.owed, 'Ali', 500000).id;
      store.payDebt(id, 100000);
      store.addDebt(DebtKind.owe, 'Veli', 500000, kese: true);
      final totals = monthKese(store.data, today);
      expect(totals.spent, 20000);
      expect(totals.earned, 0);
      expect(store.transactions.length, 1);
      expect(
        buildInsights(store.data, today).where((i) => i.kind == InsightKind.limit),
        isEmpty,
        reason: 'market spending is still under its limit',
      );
    });

    test('a loan counts in the month it happened', () {
      final store = storeWith([]);
      final id = store
          .addDebt(DebtKind.owed, 'Ali', 100000, date: addDays(today, -40))
          .id;
      expect(month(store), 0, reason: 'lent last month');
      expect(overall(store), -100000);
      store.payDebt(id, 60000);
      expect(month(store), 60000, reason: 'collected this month');
      expect(overall(store), -40000);
    });

    test('the overall kese adds up everything and can be corrected', () {
      final store = storeWith([
        tx(addDays(today, -40), 'Maaş', 30000, type: TxType.income),
        tx(today, 'Market', 1000),
      ]);
      expect(overall(store), 2900000);
      final undo = store.adjustKese(5000000);
      expect(overall(store), 5000000);
      expect(monthKese(store.data, today).spent, 100000, reason: 'statistics stay');
      store.addDebt(DebtKind.owed, 'Ali', 100000);
      expect(overall(store), 4900000, reason: 'the correction keeps up with new entries');
      undo.revert();
      expect(overall(store), 2800000);
    });

    test('open loans are totalled whatever the tick', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000, kese: false).id;
      store.payDebt(id, 25000);
      store.addDebt(DebtKind.owe, 'Veli', 40000);
      final open = openDebts(store.data);
      expect(open.owed, 75000);
      expect(open.owe, 40000);
    });

    test('removing a payment puts its money back where it was', () {
      final store = storeWith([]);
      final id = store.addDebt(DebtKind.owed, 'Ali', 100000).id;
      store.payDebt(id, 100000);
      expect(month(store), 0);
      store.removePayment(id, store.data.debts.single.payments.single.id);
      expect(month(store), -100000);
    });
  });

  group('eski borç kaydı', () {
    Map<String, Object?> v2(Map<String, Object?> debt) => {
          'version': 2,
          'transactions': [tx(today, 'Maaş', 30000, type: TxType.income).toJson()],
          'debts': [debt],
        };

    test('comes in unticked, so the kese does not move', () {
      final data = AppData.fromJson(jsonDecode(jsonEncode(v2({
        'id': 'd1',
        'kind': 'owed',
        'title': 'Ali',
        'amount': 150000,
        'paid': 50000,
        'due': null,
        'createdAt': '2026-10-02T10:00:00.000',
      }))));
      final debt = data.debts.single;
      expect(debt.kese, isFalse);
      expect(debt.date, '2026-10-02');
      expect(debt.paid, 50000);
      expect(debt.payments.single.kese, isFalse);
      expect(debt.remaining, 100000);
      expect(monthKese(data, today).kese, 3000000);
      expect(overallKese(data, today).kese, 3000000);
    });

    test('is written in the new shape and reads back the same', () {
      final store = storeWith([]);
      final old = AppData.fromJson(jsonDecode(jsonEncode(v2({
        'id': 'd1',
        'kind': 'owe',
        'title': 'Veli',
        'amount': 100000,
        'paid': 0,
        'createdAt': '2026-09-15T08:00:00.000',
      }))));
      store.data.debts = old.debts;
      final again = AppData.fromJson(documentOf(store));
      expect(documentOf(store)['version'], 3);
      expect(again.debts.single.date, '2026-09-15');
      expect(again.debts.single.payments, isEmpty);
      expect(again.debts.single.kese, isFalse);
    });

    test('a broken old record is still rejected', () {
      expect(
        () => AppData.fromJson(v2({
          'id': 'd1',
          'kind': 'owe',
          'title': 'Veli',
          'amount': 100000,
          'paid': 200000,
          'createdAt': '2026-09-15T08:00:00.000',
        })),
        throwsFormatException,
      );
    });
  });

  group('bildirim', () {
    final now = fromKey(today);

    test('installments and debts remind the day before, without amounts', () {
      final store = storeWith([])
        ..setNotifications(payments: true)
        ..addInstallments(_phone())
        ..addDebt(DebtKind.owe, 'Ali', 100000, due: addDays(today, 5));
      final plan = planNotifications(store.data, now);
      expect(plan.first.title, 'Yarın taksit var');
      expect(toKey(plan.first.at), '2026-12-17');
      expect(plan.map((p) => p.title), contains('Yarın borç günü'));
      expect(plan.map((p) => p.id).toSet().length, plan.length);
      expect(plan.any((p) => p.body.contains('₺')), isFalse);
    });

    test('stay quiet when payment reminders are off', () {
      final store = storeWith([])..addInstallments(_phone());
      expect(planNotifications(store.data, now), isEmpty);
    });

    test('a long plan does not fill the alarm slots', () {
      final store = storeWith([])
        ..setNotifications(payments: true)
        ..addInstallments(_phone(count: 36));
      expect(planNotifications(store.data, now).length, 8);
    });
  });

  group('kayıt', () {
    Store filled() => storeWith([])
      ..addInstallments(_phone())
      ..addDebt(DebtKind.owed, 'Ali', 100000, due: '2026-12-01');

    test('plans and debts survive saving', () {
      final data = AppData.fromJson(documentOf(filled()));
      expect(data.transactions.length, 6);
      expect(data.transactions.first.planCount, 6);
      expect(data.debts.single.due, '2026-12-01');
    });

    test('data from the previous version still loads', () {
      final old = {
        'version': 1,
        'transactions': [tx(today, 'Market', 100).toJson()],
      };
      final data = AppData.fromJson(jsonDecode(jsonEncode(old)));
      expect(data.transactions.single.isInstallment, isFalse);
      expect(data.debts, isEmpty);
    });

    test('rejects a broken plan or debt', () {
      final good = documentOf(filled());
      void expectRejected(void Function(Map<String, dynamic>) change) {
        final copy = jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
        change(copy);
        expect(() => AppData.fromJson(copy), throwsFormatException);
      }

      Map<String, dynamic> first(Map<String, dynamic> j) =>
          (j['transactions'] as List).first as Map<String, dynamic>;
      Map<String, dynamic> debt(Map<String, dynamic> j) =>
          (j['debts'] as List).first as Map<String, dynamic>;

      expectRejected((j) => first(j)['planIndex'] = 7);
      expectRejected((j) => first(j)['planCount'] = 99);
      expectRejected((j) => first(j).remove('planIndex'));
      expectRejected((j) => first(j)['type'] = 'income');
      expectRejected((j) => debt(j)['payments'] = [
            {'id': 'p', 'amount': 200000, 'date': today, 'kese': true},
          ]);
      expectRejected((j) => debt(j)['kese'] = 'evet');
      expectRejected((j) => debt(j)['date'] = '2026-13-01');
      expectRejected((j) => debt(j)['kind'] = 'yok');
      expectRejected((j) => debt(j)['due'] = '2026-02-31');
    });
  });

  test('the demo shows both features', () {
    final store = storeWith([])..startWithDemo();
    expect(activePlans(store.transactions, today).length, 1);
    expect(store.data.debts.length, 1);
  });

  test('monthly payments are still found alongside a plan', () {
    final store = storeWith(monthly('Kira', 21000, 22, 3, lastMonth: '2026-10', category: Category.ev))
      ..addInstallments(_phone());
    expect(detectRecurring(store.transactions, today, TxType.expense).single.title, 'Kira');
  });
}
