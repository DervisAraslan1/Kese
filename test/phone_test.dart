import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/models.dart';
import 'package:kese/core/phone.dart';
import 'package:kese/core/reminders.dart';
import 'package:kese/core/store.dart';
import 'package:kese/ui/app.dart';
import 'package:kese/ui/lock.dart';
import 'package:kese/ui/phone_sync.dart';

import 'core_test.dart' show MemoryPersistence, monthly, tx;

class FakePhone extends Phone {
  bool notificationsAllowed = true;
  bool hasScreenLock = true;
  bool failSends = false;
  UnlockResult nextUnlock = UnlockResult.success;
  bool launchedFromWidget = false;

  int unlockCalls = 0;
  int scheduleCalls = 0;
  List<PlannedNotification> scheduled = [];
  final alerts = <LimitAlert>[];
  final snapshots = <WidgetSnapshot>[];
  final quickAdds = StreamController<void>.broadcast();

  @override
  Future<bool> requestNotifications() async => notificationsAllowed;
  @override
  Future<void> schedule(List<PlannedNotification> plan) async {
    scheduleCalls++;
    scheduled = plan;
  }

  @override
  Future<void> showAlert(LimitAlert alert) async {
    if (failSends) throw StateError('no notifications');
    alerts.add(alert);
  }

  @override
  Future<void> updateWidget(WidgetSnapshot snapshot) async => snapshots.add(snapshot);
  @override
  Future<bool> canLock() async => hasScreenLock;
  @override
  Future<UnlockResult> unlock() async {
    unlockCalls++;
    return nextUnlock;
  }

  @override
  Future<bool> openedForQuickAdd() async => launchedFromWidget;
  @override
  Stream<void> get quickAddRequests => quickAdds.stream;
}

class Clock {
  DateTime now = DateTime(2026, 11, 18, 12);
}

Store storeOn(Clock clock) => Store(MemoryPersistence(), clock: () => clock.now)..startEmpty();

Future<void> pumpApp(WidgetTester tester, Store store, Phone phone) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KeseApp(store: store, phone: phone));
  await tester.pumpAndSettle();
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(NavigationDestination, 'Ayarlar'));
  await tester.pumpAndSettle();
}

Future<void> tapInSettings(WidgetTester tester, String text) async {
  await centerInSettings(tester, find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Mid-screen, clear of the navigation bar and the add button.
Future<void> centerInSettings(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).last);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

void leaveApp(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

Future<void> returnToApp(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

void main() {
  group('phone sync', () {
    late Clock clock;
    late FakePhone phone;

    setUp(() {
      clock = Clock();
      phone = FakePhone();
    });

    Store overLimit() {
      final store = storeOn(clock)
        ..setNotifications(limits: true)
        ..setLimit(Category.yemek, 100000);
      store.data.transactions = [tx('2026-11-05', 'A', 900, category: Category.yemek)];
      return store;
    }

    test('sends a limit alert once and remembers it', () async {
      final store = overLimit();
      final sync = PhoneSync(store, phone);
      await sync.run();
      await sync.run();
      expect(phone.alerts.length, 1);
      expect(store.data.notified, contains(phone.alerts.single.key));
    });

    test('regression: a failed alert is tried again', () async {
      final store = overLimit();
      phone.failSends = true;
      final sync = PhoneSync(store, phone);
      await sync.run();
      expect(store.data.notified, isEmpty);

      phone.failSends = false;
      await sync.run();
      expect(phone.alerts.length, 1);
    });

    test('a failed alert does not stop the widget update', () async {
      final store = overLimit();
      phone.failSends = true;
      await PhoneSync(store, phone).run();
      expect(phone.snapshots, isNotEmpty);
    });

    test('does not reschedule an unchanged plan', () async {
      final store = storeOn(clock)..setNotifications(evening: true);
      final sync = PhoneSync(store, phone);
      await sync.run();
      await sync.run();
      expect(phone.scheduleCalls, 1);
      expect(phone.scheduled, isNotEmpty);
    });

    test('clears the schedule when reminders are turned off', () async {
      final store = storeOn(clock)..setNotifications(evening: true);
      final sync = PhoneSync(store, phone);
      await sync.run();
      store.setNotifications(evening: false);
      await sync.run();
      expect(phone.scheduled, isEmpty);
    });

    test('quick changes reach the phone once, after the delay', () async {
      final store = storeOn(clock);
      final sync = PhoneSync(store, phone, delay: const Duration(milliseconds: 10))..start();
      await Future<void>.delayed(Duration.zero);
      final before = phone.snapshots.length;
      store.setTheme('kum');
      store.setTheme('gece');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(phone.snapshots.length, before + 1);
      sync.dispose();
    });
  });

  group('widget snapshot', () {
    AppData data({bool locked = false}) => AppData(lockEnabled: locked, transactions: [
          tx('2026-11-05', 'Maaş', 1000, category: Category.gelir, type: TxType.income),
          tx('2026-11-06', 'Kira', 300),
          tx('2026-10-06', 'Eski', 9000),
        ]);

    test('shows this month\'s balance', () {
      final snapshot = buildWidgetSnapshot(data(), '2026-11-18');
      expect(snapshot.amount, '700 ₺');
      expect(snapshot.title, contains('2026'));
    });

    test('regression: never shows the amount while the app is locked', () {
      final snapshot = buildWidgetSnapshot(data(locked: true), '2026-11-18');
      expect(snapshot.amount, isNot(contains('700')));
      expect(snapshot.amount, isNot(contains('₺')));
    });

    test('colors are in the form the Android side parses', () {
      const colors = CustomColors(accent: 0xFF0A0B0C, background: 0xFFFFFFFF);
      final snapshot = buildWidgetSnapshot(
        AppData(theme: customThemeId, customColors: colors),
        '2026-11-18',
      );
      for (final color in [snapshot.background, snapshot.ink, snapshot.accent]) {
        expect(color, matches(RegExp(r'^#[0-9A-F]{6}$')));
      }
      expect(snapshot.accent, '#0A0B0C');
    });
  });

  group('app lock', () {
    late Clock clock;
    late FakePhone phone;

    setUp(() {
      clock = Clock();
      phone = FakePhone();
    });

    testWidgets('asks on launch and opens on success', (tester) async {
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      expect(phone.unlockCalls, 1);
      expect(find.text('Kese kilitli'), findsNothing);
      expect(find.text('Bu ay kalan'), findsOneWidget);
    });

    testWidgets('stays locked after a cancelled attempt, then retries', (tester) async {
      phone.nextUnlock = UnlockResult.failed;
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      expect(find.text('Kese kilitli'), findsOneWidget);

      phone.nextUnlock = UnlockResult.success;
      await tester.tap(find.text('Kilidi aç'));
      await tester.pumpAndSettle();
      expect(find.text('Kese kilitli'), findsNothing);
    });

    testWidgets('explains a lockout', (tester) async {
      phone.nextUnlock = UnlockResult.lockedOut;
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      expect(find.textContaining('Çok fazla deneme'), findsOneWidget);
    });

    testWidgets('regression: removing the screen lock cannot lock out the owner', (tester) async {
      phone.nextUnlock = UnlockResult.unavailable;
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      expect(find.text('Kese kilitli'), findsNothing);
    });

    testWidgets('the lock screen blocks taps on what is underneath', (tester) async {
      phone.nextUnlock = UnlockResult.failed;
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      await tester.tap(find.byTooltip('Hızlı ekle'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a short trip away does not lock', (tester) async {
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      leaveApp(tester);
      clock.now = clock.now.add(lockGrace - const Duration(seconds: 1));
      await returnToApp(tester);
      expect(phone.unlockCalls, 1);
      expect(find.text('Kese kilitli'), findsNothing);
    });

    testWidgets('a long trip away locks again', (tester) async {
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      phone.nextUnlock = UnlockResult.failed;
      leaveApp(tester);
      clock.now = clock.now.add(lockGrace);
      await returnToApp(tester);
      expect(phone.unlockCalls, 2);
      expect(find.text('Kese kilitli'), findsOneWidget);
    });

    testWidgets('an open sheet is still there after unlocking', (tester) async {
      await pumpApp(tester, storeOn(clock)..setLock(true), phone);
      await tester.tap(find.byTooltip('Hızlı ekle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'kahve 85');

      phone.nextUnlock = UnlockResult.failed;
      leaveApp(tester);
      clock.now = clock.now.add(lockGrace);
      await returnToApp(tester);
      expect(find.text('Kese kilitli'), findsOneWidget);

      phone.nextUnlock = UnlockResult.success;
      await tester.tap(find.text('Kilidi aç'));
      await tester.pumpAndSettle();
      expect(find.text('kahve 85'), findsOneWidget);
    });

    testWidgets('turning it on needs a confirmed unlock', (tester) async {
      final store = storeOn(clock);
      await pumpApp(tester, store, phone);
      await openSettings(tester);

      phone.nextUnlock = UnlockResult.failed;
      await tapInSettings(tester, 'Uygulama kilidi');
      expect(store.data.lockEnabled, isFalse);

      phone.nextUnlock = UnlockResult.success;
      await tapInSettings(tester, 'Uygulama kilidi');
      expect(store.data.lockEnabled, isTrue);
    });

    testWidgets('turning it off needs a confirmed unlock', (tester) async {
      final store = storeOn(clock)..setLock(true);
      await pumpApp(tester, store, phone);
      await openSettings(tester);

      phone.nextUnlock = UnlockResult.failed;
      await tapInSettings(tester, 'Uygulama kilidi');
      expect(store.data.lockEnabled, isTrue);
    });

    testWidgets('says why a phone without a screen lock cannot use it', (tester) async {
      phone.hasScreenLock = false;
      final store = storeOn(clock);
      await pumpApp(tester, store, phone);
      await openSettings(tester);
      await tapInSettings(tester, 'Uygulama kilidi');
      expect(store.data.lockEnabled, isFalse);
      expect(phone.unlockCalls, 0);
      expect(find.textContaining('ekran kilidi veya parmak izi tanımla'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('a refused permission leaves the switch off', (tester) async {
      final phone = FakePhone()..notificationsAllowed = false;
      final store = storeOn(Clock());
      await pumpApp(tester, store, phone);
      await openSettings(tester);
      await tapInSettings(tester, 'Akşam hatırlatması');
      expect(store.data.notifyEvening, isFalse);
      expect(find.textContaining('Bildirim izni verilmedi'), findsOneWidget);
    });

    testWidgets('an allowed permission turns the switch on', (tester) async {
      final store = storeOn(Clock());
      await pumpApp(tester, store, FakePhone());
      await openSettings(tester);
      await tapInSettings(tester, 'Akşam hatırlatması');
      expect(store.data.notifyEvening, isTrue);
    });

    testWidgets('custom colors are picked, previewed and applied', (tester) async {
      final store = storeOn(Clock());
      await pumpApp(tester, store, FakePhone());
      await openSettings(tester);
      await tapInSettings(tester, 'Özel');
      expect(find.text('Özel tema'), findsOneWidget);
      expect(store.data.customColors, isNull, reason: 'nothing saved until confirmed');

      await tester.enterText(find.widgetWithText(TextField, 'Renk kodu'), 'FF7A00');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Temayı kullan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Temayı kullan'));
      await tester.pumpAndSettle();

      expect(store.data.customColors!.accent, 0xFFFF7A00);
      expect(store.data.theme, customThemeId);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.colorScheme.primary, const Color(0xFFFF7A00));
    });

    testWidgets('leaving the editor without saving changes nothing', (tester) async {
      final store = storeOn(Clock());
      await pumpApp(tester, store, FakePhone());
      await openSettings(tester);
      await tapInSettings(tester, 'Özel');
      await tester.enterText(find.widgetWithText(TextField, 'Renk kodu'), 'FF7A00');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(store.data.customColors, isNull);
      expect(store.data.theme, 'zumrut');
    });

    testWidgets('warns about an accent lost in the background', (tester) async {
      final store = storeOn(Clock())
        ..setCustomColors(const CustomColors(accent: 0xFF3FD6A0, background: 0xFF101010));
      await pumpApp(tester, store, FakePhone());
      await openSettings(tester);
      await centerInSettings(tester, find.byTooltip('Özel temayı düzenle'));
      await tester.tap(find.byTooltip('Özel temayı düzenle'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kayboluyor'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Renk kodu'), '111111');
      await tester.pumpAndSettle();
      expect(find.textContaining('kayboluyor'), findsOneWidget);
    });

    testWidgets('dragging the color box does not scroll the page', (tester) async {
      final store = storeOn(Clock());
      await pumpApp(tester, store, FakePhone());
      await openSettings(tester);
      await tapInSettings(tester, 'Özel');

      final hex = find.widgetWithText(TextField, 'Renk kodu');
      final before = tester.widget<TextField>(hex).controller!.text;
      final top = tester.getTopLeft(find.text('Vurgu')).dy;
      await tester.dragFrom(
        tester.getCenter(find.text('Vurgu')) + const Offset(0, 120),
        const Offset(30, -60),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Vurgu')).dy, top);
      expect(tester.widget<TextField>(hex).controller!.text, isNot(before));
    });
  });

  group('home screen widget', () {
    testWidgets('its add button opens quick add', (tester) async {
      final phone = FakePhone();
      await pumpApp(tester, storeOn(Clock()), phone);
      phone.quickAdds.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('pressing it twice opens one sheet', (tester) async {
      final phone = FakePhone();
      await pumpApp(tester, storeOn(Clock()), phone);
      phone.quickAdds
        ..add(null)
        ..add(null);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('it can start the app', (tester) async {
      final phone = FakePhone()..launchedFromWidget = true;
      await pumpApp(tester, storeOn(Clock()), phone);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('goals on the home page', () {
    Future<void> addGoal(WidgetTester tester, String title, String target) async {
      await tester.ensureVisible(find.byTooltip('Yeni hedef'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Yeni hedef'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Hedef adı'), title);
      await tester.enterText(find.widgetWithText(TextField, 'Hedef tutar'), target);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
    }

    testWidgets('a goal is created and saved into', (tester) async {
      final store = storeOn(Clock());
      await pumpApp(tester, store, FakePhone());
      await addGoal(tester, 'Tatil', '30.000');
      expect(store.data.goals.single.target, 3000000);

      await tester.tap(find.text('Tatil'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '500');
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();
      expect(store.data.goals.single.saved, 50000);
      expect(find.text('29.500 ₺ kaldı'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(store.data.goals.single.saved, 0);
    });

    testWidgets('rejects a goal with no name or amount', (tester) async {
      final store = storeOn(Clock());
      await pumpApp(tester, store, FakePhone());
      await addGoal(tester, ' ', 'çok');
      expect(store.data.goals, isEmpty);
      expect(find.text('Hedefe bir ad ver.'), findsOneWidget);
      expect(find.textContaining('Geçerli bir tutar'), findsOneWidget);
    });

    testWidgets('a goal can be edited and deleted', (tester) async {
      final store = storeOn(Clock())..addGoal('Tatil', 100000);
      await pumpApp(tester, store, FakePhone());

      await tester.tap(find.text('Tatil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Hedef adı'), 'Araba');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(store.data.goals.single.title, 'Araba');

      await tester.tap(find.text('Araba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(store.data.goals, isEmpty);
    });
  });

  testWidgets('"Ödedim" records the bill from its card', (tester) async {
    final store = storeOn(Clock());
    store.data.transactions =
        monthly('Kira', 21000, 22, 3, lastMonth: '2026-10', category: Category.ev);
    await pumpApp(tester, store, FakePhone());

    final button = find.text('Ödedim');
    await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
    await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(store.transactions.length, 4);
    expect(find.text('Ödedim'), findsNothing);
  });

  testWidgets('the undo snack bar goes away by itself', (tester) async {
    final store = storeOn(Clock())..addGoal('Tatil', 100000);
    await pumpApp(tester, store, FakePhone());
    await tester.tap(find.text('Tatil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Geri al'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Geri al'), findsNothing);
  });
}
