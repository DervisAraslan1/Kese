import 'dart:convert';

import 'package:flutter/material.dart' show Color, Colors, Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/insights.dart';
import 'package:kese/core/models.dart';
import 'package:kese/core/reminders.dart';
import 'package:kese/core/store.dart';
import 'package:kese/ui/theme.dart';

import 'core_test.dart' show MemoryPersistence, monthly, storeWith, today, tx;

void main() {
  group('Ödedim', () {
    Insight upcoming(Store store) => buildInsights(store.data, store.today)
        .firstWhere((i) => i.kind == InsightKind.upcoming);

    List<Transaction> rent() =>
        monthly('Kira', 21000, 22, 3, lastMonth: '2026-10', category: Category.ev);

    test('records the payment for today', () {
      final store = storeWith(rent());
      store.acceptInsight(upcoming(store));
      expect(store.transactions.length, 4);
      final paid = store.transactions.last;
      expect(paid.title, 'Kira');
      expect(paid.amount, 2100000);
      expect(paid.date, today);
      expect(paid.category, Category.ev);
    });

    test('regression: a paid bill stops being offered', () {
      final store = storeWith(rent());
      store.acceptInsight(upcoming(store));
      final after = buildInsights(store.data, store.today);
      expect(after.where((i) => i.kind == InsightKind.upcoming), isEmpty);
      final next = detectRecurring(store.transactions, today, TxType.expense).single;
      expect(next.paidThisMonth, isTrue);
      expect(next.nextDate, '2026-12-22');
    });

    test('undo removes the payment and restores the card', () {
      final store = storeWith(rent());
      final undo = store.acceptInsight(upcoming(store));
      undo.revert();
      expect(store.transactions.length, 3);
      expect(upcoming(store).actionLabel, 'Ödedim');
    });

    test('regression: next month\'s bill has no button yet', () {
      final items = monthly('Kira', 21000, 3, 4, category: Category.ev);
      final card = buildInsights(AppData(transactions: items), '2026-11-28')
          .firstWhere((i) => i.kind == InsightKind.upcoming);
      expect(card.action, isNull);
      expect(card.actionLabel, isNull);
    });
  });

  group('goals', () {
    test('tracks progress and clamps at zero', () {
      final store = storeWith([]);
      final goal = store.addGoal('Tatil', 3000000);
      store.addToGoal(goal.id, 1000000);
      expect(store.data.goals.single.remaining, 2000000);
      store.addToGoal(goal.id, -5000000);
      expect(store.data.goals.single.saved, 0);
    });

    test('undo reverses exactly what changed', () {
      final store = storeWith([]);
      final goal = store.addGoal('Tatil', 3000000);
      store.addToGoal(goal.id, 100000);
      final undo = store.addToGoal(goal.id, -500000)!;
      undo.revert();
      expect(store.data.goals.single.saved, 100000);
    });

    test('a deleted goal can be restored', () {
      final store = storeWith([]);
      final goal = store.addGoal('Tatil', 3000000);
      final undo = store.deleteGoal(goal.id)!;
      expect(store.data.goals, isEmpty);
      undo.revert();
      undo.revert();
      expect(store.data.goals.length, 1);
    });

    SavingsGoal goalOf(int target, {int saved = 0}) => SavingsGoal(
          id: 'g',
          title: 'T',
          target: target,
          saved: saved,
          createdAt: '${today}T10:00:00.000',
        );

    test('estimates from the saving rate of finished months', () {
      final items = [
        for (final m in ['2026-08', '2026-09', '2026-10']) ...[
          tx('$m-01', 'Maaş', 10000, category: Category.gelir, type: TxType.income),
          tx('$m-05', 'Kira', 7000),
        ],
        // The unfinished month must not skew the rate.
        tx('2026-11-02', 'Tatil', 50000),
      ];
      final estimate = estimateGoal(goalOf(1000000), items, today)!;
      expect(estimate.monthlySaving, 300000);
      expect(estimate.month, '2027-03');
    });

    test('gives no estimate without savings', () {
      expect(estimateGoal(goalOf(1000000), [], today), isNull);
      expect(estimateGoal(goalOf(1000000), [tx('2026-10-05', 'Kira', 7000)], today), isNull);
    });

    test('gives no estimate for a reached goal', () {
      expect(estimateGoal(goalOf(100, saved: 100), [], today), isNull);
    });

    test('rejects invalid goals in a backup', () {
      final store = storeWith([]);
      final good = jsonDecode(store.exportBackup()) as Map<String, dynamic>;
      for (final bad in [
        {'id': 'a', 'title': 'x', 'target': 0, 'saved': 0, 'createdAt': '2026-01-01'},
        {'id': 'a', 'title': ' ', 'target': 5, 'saved': 0, 'createdAt': '2026-01-01'},
        {'id': 'a', 'title': 'x', 'target': 5, 'saved': -1, 'createdAt': '2026-01-01'},
      ]) {
        good['goals'] = [bad];
        expect(() => store.importBackup(jsonEncode(good)), throwsFormatException);
      }
    });
  });

  group('backup compatibility', () {
    test('old backups without the new fields still load', () {
      final old = jsonEncode({
        'version': 1,
        'transactions': [],
        'limits': {},
        'feedback': {},
        'dismissed': {},
        'theme': 'zumrut',
        'onboarded': true,
        'demo': false,
      });
      final store = storeWith([]);
      store.importBackup(old);
      expect(store.data.goals, isEmpty);
    });

    test('regression: a backup cannot change the lock', () {
      final source = storeWith([])..setLock(true);
      final target = storeWith([]);
      target.importBackup(source.exportBackup());
      expect(target.data.lockEnabled, isFalse);

      final locked = storeWith([])..setLock(true);
      locked.importBackup(storeWith([]).exportBackup());
      expect(locked.data.lockEnabled, isTrue);
    });

    test('goals and colors survive a save and reload', () async {
      final disk = MemoryPersistence();
      final store = storeWith([], disk)
        ..addGoal('Tatil', 100)
        ..setCustomColors(const CustomColors(accent: 0xFF112233, background: 0xFF000000));
      await store.flush();
      final data = AppData.fromJson(jsonDecode(disk.contents!));
      expect(data.goals.single.title, 'Tatil');
      expect(data.customColors!.accent, 0xFF112233);
      expect(data.theme, customThemeId);
    });

    test('rejects invalid custom colors', () {
      for (final bad in [
        {'accent': 5, 'background': 0xFF000000},
        {'accent': 0xFF000000},
        'kırmızı',
      ]) {
        expect(() => CustomColors.fromJson(bad), throwsFormatException);
      }
    });

    test('a fresh start keeps phone settings', () {
      final store = storeWith([tx(today, 'A', 1)])
        ..setLock(true)
        ..setNotifications(evening: true)
        ..addGoal('Tatil', 100);
      store.startEmpty();
      expect(store.data.lockEnabled, isTrue);
      expect(store.data.notifyEvening, isTrue);
      expect(store.data.goals, isEmpty);
    });
  });

  group('notification plan', () {
    final now = DateTime(2026, 11, 18, 12);
    List<Transaction> rent() =>
        monthly('Kira', 21000, 25, 3, lastMonth: '2026-10', category: Category.ev);

    test('plans nothing unless asked', () {
      expect(planNotifications(AppData(transactions: rent()), now), isEmpty);
    });

    test('warns the morning before a payment', () {
      final data = AppData(transactions: rent(), notifyPayments: true);
      final plan = planNotifications(data, now).single;
      expect(plan.at, DateTime(2026, 11, 24, 10));
      expect(plan.body, contains('Kira'));
    });

    test('skips a warning whose time has passed', () {
      final data = AppData(transactions: rent(), notifyPayments: true);
      expect(planNotifications(data, DateTime(2026, 11, 24, 11)), isEmpty);
    });

    test('never puts an amount in a notification', () {
      final data = AppData(transactions: rent(), notifyPayments: true, notifyEvening: true);
      for (final item in planNotifications(data, now)) {
        expect('${item.title} ${item.body}', isNot(contains('₺')));
      }
    });

    test('skips tonight once something was entered today', () {
      final quiet = AppData(notifyEvening: true);
      expect(planNotifications(quiet, now).first.at, DateTime(2026, 11, 18, 21));

      final entered = AppData(notifyEvening: true, transactions: [tx(today, 'Kahve', 50)]);
      expect(planNotifications(entered, now).first.at, DateTime(2026, 11, 19, 21));
    });

    test('ids never collide', () {
      final data = AppData(transactions: rent(), notifyPayments: true, notifyEvening: true);
      final ids = planNotifications(data, now).map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('limit alerts', () {
    AppData data(int lira) => AppData(
          notifyLimits: true,
          limits: {Category.yemek: 100000},
          transactions: [tx('2026-11-05', 'A', lira, category: Category.yemek)],
        );

    test('stays quiet below 80%', () {
      expect(pendingLimitAlerts(data(700), today), isEmpty);
    });

    test('fires near the limit, once', () {
      final d = data(850);
      final alert = pendingLimitAlerts(d, today).single;
      expect(alert.title, contains('yaklaştın'));
      d.notified.add(alert.key);
      expect(pendingLimitAlerts(d, today), isEmpty);
    });

    test('jumping past the limit sends only the over alert', () {
      final alert = pendingLimitAlerts(data(1500), today).single;
      expect(alert.title, contains('aştın'));
    });

    test('a near alert does not block the over alert', () {
      final d = data(1500)..notified.add('limit:yemek:2026-11:near');
      expect(pendingLimitAlerts(d, today).single.title, contains('aştın'));
    });

    test('is off unless enabled', () {
      final d = data(1500)..notifyLimits = false;
      expect(pendingLimitAlerts(d, today), isEmpty);
    });

    test('each month starts over', () {
      final d = data(1500)..notified.add('limit:yemek:2026-11:over');
      d.transactions = [tx('2026-12-05', 'A', 1500, category: Category.yemek)];
      expect(pendingLimitAlerts(d, '2026-12-10'), isNotEmpty);
    });
  });

  group('custom theme', () {
    test('a dark background gives a dark theme with light text', () {
      final t = deriveTheme(const CustomColors(accent: 0xFFFF7A00, background: 0xFF101018));
      expect(t.brightness, Brightness.dark);
      expect(contrastRatio(t.ink, t.background), greaterThan(7));
    });

    test('a light background gives a light theme with dark text', () {
      final t = deriveTheme(const CustomColors(accent: 0xFF0044CC, background: 0xFFF5F0E0));
      expect(t.brightness, Brightness.light);
      expect(contrastRatio(t.ink, t.background), greaterThan(7));
    });

    test('text on the accent stays readable for any accent', () {
      for (final accent in [0xFF000000, 0xFFFFFFFF, 0xFFFFFF00, 0xFF0000FF, 0xFF808080, 0xFFFF0000]) {
        final t = deriveTheme(CustomColors(accent: accent, background: 0xFF101018));
        expect(contrastRatio(t.onAccent, t.accent), greaterThanOrEqualTo(4.5), reason: '$accent');
      }
    });

    test('text stays readable on any background', () {
      for (final bg in [0xFF000000, 0xFFFFFFFF, 0xFF808080, 0xFF7F1D1D, 0xFFFFE066, 0xFF1E3A8A]) {
        final t = deriveTheme(CustomColors(accent: 0xFFFF7A00, background: bg));
        expect(contrastRatio(t.inkSoft, t.background), greaterThanOrEqualTo(4.5), reason: '$bg');
        expect(contrastRatio(t.ink, t.surface), greaterThanOrEqualTo(4.5), reason: '$bg');
      }
    });

    test('flags an accent that disappears into the background', () {
      expect(accentIsLegible(const CustomColors(accent: 0xFF111111, background: 0xFF101010)), isFalse);
      expect(accentIsLegible(const CustomColors(accent: 0xFFFFD27A, background: 0xFF101010)), isTrue);
    });

    test('the contrast formula matches known values', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(const Color(0xFF777777), Colors.white), closeTo(4.48, 0.02));
    });

    test('falls back when custom colors are missing', () {
      expect(resolveTheme(AppData(theme: customThemeId)).id, themes.first.id);
      final data = AppData(
        theme: customThemeId,
        customColors: const CustomColors(accent: 0xFFFF7A00, background: 0xFF101018),
      );
      expect(resolveTheme(data).id, customThemeId);
    });

    test('every built-in theme has readable text', () {
      for (final t in themes) {
        expect(contrastRatio(t.ink, t.background), greaterThan(7), reason: t.id);
        expect(contrastRatio(t.onAccent, t.accent), greaterThanOrEqualTo(4.5), reason: t.id);
      }
    });
  });
}
