import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/models.dart';
import 'package:kese/core/store.dart';
import 'package:kese/ui/app.dart';

import 'core_test.dart' show MemoryPersistence;

Store makeStore() => Store(MemoryPersistence(), clock: () => DateTime(2026, 11, 18, 12));

Future<void> pumpApp(WidgetTester tester, Store store) async {
  // A small phone: layouts must fit here.
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KeseApp(store: store));
  await tester.pumpAndSettle();
}

Future<void> quickAdd(WidgetTester tester, String text) async {
  await tester.tap(find.byTooltip('Hızlı ekle'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pumpAndSettle();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// Scrolls like a person would, clear of the bar floating over the page.
Future<void> bringIntoView(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.3);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on the welcome screen, then an empty month', (tester) async {
    final store = makeStore();
    await pumpApp(tester, store);
    expect(find.text('Örnek verilerle dene'), findsOneWidget);

    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    expect(find.text('Bu ay kalan'), findsOneWidget);
    expect(store.data.onboarded, isTrue);
  });

  testWidgets('quick add saves an entry and offers undo', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);

    await quickAdd(tester, 'market 340 tl');
    expect(store.transactions.single.amount, 34000);
    expect(find.text('-340 ₺'), findsOneWidget, reason: 'the pouch');
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(store.transactions, isEmpty);
  });

  testWidgets('quick add shows the problem and saves nothing', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);

    await quickAdd(tester, 'market');
    expect(find.textContaining('Tutarı bulamadım'), findsOneWidget);
    expect(store.transactions, isEmpty);
  });

  testWidgets('swiping deletes, and undo brings it back', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await quickAdd(tester, 'kahve 85');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await bringIntoView(tester, find.text('kahve'));
    await tester.fling(find.text('kahve'), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    expect(store.transactions, isEmpty);

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(store.transactions.single.title, 'kahve');
  });

  testWidgets('editing a transaction changes it', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await quickAdd(tester, 'kahve 85');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await bringIntoView(tester, find.text('kahve'));
    await tester.tap(find.text('kahve'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Tutar'), '1.250,75');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(store.transactions.single.amount, 125075);
  });

  testWidgets('a one-line installment shows up as a plan and can be undone', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);

    await quickAdd(tester, 'telefon 30.000 6 taksit');
    expect(store.transactions.length, 6);
    await bringIntoView(tester, find.text('25.000 ₺ kaldı'));
    expect(find.text('Taksitler'), findsOneWidget);
    expect(find.text('Aralık 2026 taksitleri: 5.000 ₺'), findsOneWidget);
    expect(find.text('25.000 ₺ kaldı'), findsOneWidget);

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(store.transactions, isEmpty);
    expect(find.text('Taksitler'), findsNothing);
  });

  testWidgets('the form splits a purchase into installments', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await tester.tap(find.byTooltip('Hızlı ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form ile ekle'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Başlık'), 'Buzdolabı');
    await tester.enterText(find.widgetWithText(TextFormField, 'Tutar'), '12.000');
    await tester.tap(find.text('Peşin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 taksit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(store.transactions.map((t) => t.amount), [400000, 400000, 400000]);
    expect(store.transactions.last.planIndex, 3);
  });

  testWidgets('income cannot be split in the form', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await tester.tap(find.byTooltip('Hızlı ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form ile ekle'));
    await tester.pumpAndSettle();
    expect(find.text('Taksit'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<TxType>), matching: find.text('Gelir')));
    await tester.pumpAndSettle();
    expect(find.text('Taksit'), findsNothing);
  });

  testWidgets('a plan row deletes what is left and undo brings it back', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await quickAdd(tester, 'telefon 30.000 6 taksit');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await bringIntoView(tester, find.text('25.000 ₺ kaldı'));
    await tester.tap(find.text('25.000 ₺ kaldı'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalan taksitleri sil'));
    await tester.pumpAndSettle();
    expect(store.transactions.length, 1);

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(store.transactions.length, 6);
  });

  testWidgets('coming installments stay out of recent, and the month picker reaches them',
      (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await quickAdd(tester, 'telefon 30.000 3 taksit');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await bringIntoView(tester, find.textContaining('Taksit 1/3'));
    expect(find.textContaining('Taksit 1/3'), findsOneWidget);
    expect(find.textContaining('Taksit 2/3'), findsNothing);

    await tester.tap(find.widgetWithText(NavigationDestination, 'İşlemler'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Taksit 2/3'), findsOneWidget);
    await tester.tap(find.byTooltip('Sonraki ay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Taksit 3/3'), findsOneWidget);
    final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(next.onPressed, isNull, reason: 'nothing lies beyond the last installment');
  });

  testWidgets('a debt is added on one line, paid and closed', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await quickAdd(tester, 'ali 1.000 #alacak');
    expect(store.data.debts.single.kind, DebtKind.owed);
    expect(store.transactions, isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await bringIntoView(tester, find.text('ali'));
    await tester.tap(find.text('ali'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '400');
    await tester.tap(find.text('Ödeme ekle'));
    await tester.pumpAndSettle();
    expect(store.data.debts.single.remaining, 60000);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamamını kapat'));
    await tester.pumpAndSettle();
    expect(store.data.debts.single.settled, isTrue);
    expect(find.text('Kapandı'), findsOneWidget);
    expect(store.transactions, isEmpty, reason: 'debts stay out of the budget');
  });

  testWidgets('the debt dialog validates, then saves with a kind', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await bringIntoView(tester, find.byTooltip('Yeni borç veya alacak'));
    await tester.tap(find.byTooltip('Yeni borç veya alacak'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Kimle olduğunu yaz.'), findsOneWidget);
    expect(store.data.debts, isEmpty);

    await tester.tap(find.text('Borcum'));
    await tester.enterText(find.widgetWithText(TextField, 'Kişi veya açıklama'), 'Veli');
    await tester.enterText(find.widgetWithText(TextField, 'Tutar'), '2.500');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(store.data.debts.single.kind, DebtKind.owe);
    expect(store.data.debts.single.amount, 250000);
  });

  testWidgets('every tab renders the demo data without overflow', (tester) async {
    final store = makeStore()..startWithDemo();
    await pumpApp(tester, store);
    expect(tester.takeException(), isNull);

    for (final tab in ['İşlemler', 'Analiz', 'Ayarlar', 'Bu ay']) {
      await tester.tap(find.widgetWithText(NavigationDestination, tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('search finds entries from other months', (tester) async {
    final store = makeStore()..startWithDemo();
    await pumpApp(tester, store);
    await tester.tap(find.widgetWithText(NavigationDestination, 'İşlemler'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'NETFLİX');
    await tester.pumpAndSettle();
    final count = store.transactions.where((t) => t.title == 'Netflix').length;
    expect(count, greaterThan(1));
    expect(find.text('$count işlem'), findsOneWidget);
  });

  testWidgets('accepting an insight removes its card', (tester) async {
    final store = makeStore()..startWithDemo();
    await pumpApp(tester, store);

    final card = find.textContaining('Netflix” abonelik gibi');
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);
    final button = find.text('Abonelik olarak işaretle').first;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Netflix” abonelik gibi'), findsNothing);
    expect(
      store.transactions.where((t) => t.title == 'Netflix').first.category,
      Category.abonelik,
    );
  });

  testWidgets('a limit can be set and removed', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Ayarlar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yemek'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '5.000');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(store.data.limits[Category.yemek], 500000);

    await tester.tap(find.text('Yemek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limiti kaldır'));
    await tester.pumpAndSettle();
    expect(store.data.limits, isEmpty);
  });

  testWidgets('deleting everything asks first', (tester) async {
    final store = makeStore()..startWithDemo();
    await pumpApp(tester, store);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Ayarlar'));
    await tester.pumpAndSettle();

    final delete = find.text('Tümünü sil');
    await tester.scrollUntilVisible(delete, 200, scrollable: find.byType(Scrollable).last);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(store.transactions, isNotEmpty);

    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evet, sil'));
    await tester.pumpAndSettle();
    expect(store.transactions, isEmpty);
  });

  testWidgets('changing the theme applies it', (tester) async {
    final store = makeStore()..startEmpty();
    await pumpApp(tester, store);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Ayarlar'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Kum'), 200, scrollable: find.byType(Scrollable).last);
    await Scrollable.ensureVisible(tester.element(find.text('Kum')), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kum'));
    await tester.pumpAndSettle();
    expect(store.data.theme, 'kum');
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.brightness, Brightness.light);
  });
}
