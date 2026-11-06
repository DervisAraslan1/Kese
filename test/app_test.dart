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
    expect(find.text('-340 ₺'), findsNWidgets(2), reason: 'hero and list row');

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

    await tester.tap(find.text('kahve'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Tutar'), '1.250,75');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(store.transactions.single.amount, 125075);
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
